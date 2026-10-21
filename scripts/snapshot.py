"""Snapshot a briefing page: a standalone HTML copy (doctype, UTF-8, local resources
inlined) and a full-height PNG taken with Google Chrome headless.

usage: snapshot.py <page.html> <out-dir>

Only the Python standard library is used. Chrome problems never raise; they leave the PNG
out and explain why in `note`. A page that cannot be read raises slack_config.Failure.
"""

import base64
import html
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from slack_config import FAILED, OK, Failure  # noqa: E402

MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"
WIDTH = 1280
MAX_HEIGHT = 16000
FALLBACK_HEIGHT = 4000
TIMEOUT = 90
MAC_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PATH_CHROMES = ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
                "chrome")
HEIGHT_ATTR = "data-logbook-height"

SKIP = re.compile(r"^(?:https?:|data:|#|mailto:|//|javascript:|about:|blob:)", re.I)
MERMAID_CLASS = re.compile(r"""class\s*=\s*["'][^"']*\bmermaid\b""", re.I)
MERMAID_SCRIPT = re.compile(r"mermaid(?:@[\w.\-]+)?(?:/dist)?/mermaid(?:\.min|\.esm(?:\.min)?)?\.m?js"
                            r"|mermaid\.min\.js|mermaid\.esm", re.I)
DOCTYPE = re.compile(r"^\s*(?:<!--.*?-->\s*)*<!doctype", re.I | re.S)


def find_chrome():
    """The Chrome binary to use, or None."""
    env = os.environ.get("LOGBOOK_CHROME")
    if env:
        if os.path.isfile(env) and os.access(env, os.X_OK):
            return env
        # An explicit setting wins; when it points nowhere, Chrome counts as missing.
        return shutil.which(env)
    if os.path.isfile(MAC_CHROME) and os.access(MAC_CHROME, os.X_OK):
        return MAC_CHROME
    for name in PATH_CHROMES:
        found = shutil.which(name)
        if found:
            return found
    return None


# --- standalone HTML -------------------------------------------------------------------

class Inliner:
    """Rewrites local references in a page to inline content, remembering what was missing."""

    def __init__(self):
        self.missing = []

    def _local(self, ref, base):
        """The local file `ref` points to, or None when it is remote or skipped.
        Records missing files and returns False for them."""
        ref = html.unescape(ref.strip())
        if not ref or SKIP.match(ref):
            return None
        path_part = urllib.parse.unquote(re.split(r"[?#]", ref, maxsplit=1)[0])
        if path_part.startswith("file://"):
            path_part = path_part[len("file://"):]
        if not path_part:
            return None
        path = Path(path_part)
        if not path.is_absolute():
            path = base / path
        if path.is_file():
            return path
        if ref not in self.missing:
            self.missing.append(ref)
        return False

    @staticmethod
    def _data_uri(path):
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        data = base64.b64encode(path.read_bytes()).decode("ascii")
        return f"data:{mime};base64,{data}"

    def _attr_to_data(self, text, base, tag, attr):
        """Replace `attr` of every `tag` with a data: URI of the local file."""
        tag_re = re.compile(rf"<{tag}\b[^>]*>", re.I)
        attr_re = re.compile(rf"""(\s{attr}\s*=\s*)(["'])(.*?)\2""", re.I | re.S)

        def fix_attr(m):
            path = self._local(m.group(3), base)
            if not path:
                return m.group(0)
            return f"{m.group(1)}{m.group(2)}{self._data_uri(path)}{m.group(2)}"

        return tag_re.sub(lambda m: attr_re.sub(fix_attr, m.group(0), count=1), text)

    def _css_urls(self, css, base):
        """Inline url(...) references in CSS text."""
        def fix(m):
            path = self._local(m.group(2), base)
            if not path:
                return m.group(0)
            return f"url({m.group(1)}{self._data_uri(path)}{m.group(1)})"
        return re.sub(r"""url\(\s*(["']?)([^"')]+?)\1\s*\)""", fix, css)

    def _stylesheets(self, text, base):
        link_re = re.compile(r"<link\b[^>]*>", re.I)

        def fix(m):
            tag = m.group(0)
            if not re.search(r"""\brel\s*=\s*["']?[^"'>]*\bstylesheet\b""", tag, re.I):
                return tag
            href = re.search(r"""\shref\s*=\s*(["'])(.*?)\1""", tag, re.I | re.S)
            if not href:
                return tag
            path = self._local(href.group(2), base)
            if not path:
                return tag
            css = self._css_urls(path.read_text(encoding="utf-8", errors="replace"), path.parent)
            css = re.sub(r"</style", r"<\\/style", css, flags=re.I)
            return f"<style>\n{css}\n</style>"

        return link_re.sub(fix, text)

    def _scripts(self, text, base):
        script_re = re.compile(r"<script\b([^>]*)>\s*</script\s*>", re.I | re.S)

        def fix(m):
            attrs = m.group(1)
            src = re.search(r"""\ssrc\s*=\s*(["'])(.*?)\1""", attrs, re.I | re.S)
            if not src:
                return m.group(0)
            path = self._local(src.group(2), base)
            if not path:
                return m.group(0)
            code = path.read_text(encoding="utf-8", errors="replace")
            code = re.sub(r"</script", r"<\\/script", code, flags=re.I)
            rest = attrs[:src.start()] + attrs[src.end():]
            return f"<script{rest}>\n{code}\n</script>"

        return script_re.sub(fix, text)

    def _iframes(self, text, base, depth):
        tag_re = re.compile(r"<iframe\b[^>]*>", re.I)

        def fix(m):
            tag = m.group(0)
            src = re.search(r"""\ssrc\s*=\s*(["'])(.*?)\1""", tag, re.I | re.S)
            if not src or not re.search(r"\.html?(?:[?#].*)?$", src.group(2).strip(), re.I):
                return tag
            path = self._local(src.group(2), base)
            if not path:
                return tag
            inner = path.read_text(encoding="utf-8", errors="replace")
            if depth < 3:
                inner = self.inline(inner, path.parent, depth + 1)
            srcdoc = html.escape(inner, quote=True)
            return tag[:src.start()] + f' srcdoc="{srcdoc}"' + tag[src.end():]

        return tag_re.sub(fix, text)

    def _inline_styles(self, text, base):
        style_re = re.compile(r"(<style\b[^>]*>)(.*?)(</style\s*>)", re.I | re.S)
        return style_re.sub(
            lambda m: m.group(1) + self._css_urls(m.group(2), base) + m.group(3), text)

    def inline(self, text, base, depth=0):
        text = self._iframes(text, base, depth)
        text = self._stylesheets(text, base)
        text = self._scripts(text, base)
        text = self._inline_styles(text, base)
        text = self._attr_to_data(text, base, "img", "src")
        text = self._attr_to_data(text, base, "source", "src")
        return text


def add_before_body_end(text, snippet):
    idx = text.lower().rfind("</body>")
    if idx < 0:
        return text + snippet
    return text[:idx] + snippet + text[idx:]


def standalone(page, base):
    """The standalone copy of `page` and the list of local files it could not find."""
    inliner = Inliner()
    text = inliner.inline(page, base)
    if not DOCTYPE.match(text):
        text = ("<!doctype html>\n<html lang=\"ko\"><head><meta charset=\"utf-8\">"
                "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                "</head><body>" + text + "</body></html>")
    if MERMAID_CLASS.search(text) and not MERMAID_SCRIPT.search(text):
        text = add_before_body_end(
            text,
            f'<script src="{MERMAID_URL}"></script>\n'
            "<script>mermaid.initialize({startOnLoad: true});</script>\n")
    return text, inliner.missing


# --- PNG -------------------------------------------------------------------------------

MEASURE_SCRIPT = """<script>
(function () {
  function mark() {
    var h = Math.max(document.documentElement.scrollHeight,
                     document.body ? document.body.scrollHeight : 0);
    document.documentElement.setAttribute('%s', String(h));
  }
  window.addEventListener('load', function () { setTimeout(mark, 1500); });
})();
</script>
""" % HEIGHT_ATTR


# Under --virtual-time-budget, Date.now() can return the same value twice in a row, and
# mermaid names each diagram by Date.now(): two diagrams then share an id and the second
# comes out blank. The copies Chrome renders get a Date.now() that always moves forward.
CLOCK_SCRIPT = """<script>
(function () {
  var now = Date.now.bind(Date), last = 0;
  Date.now = function () { var t = now(); last = t > last ? t : last + 1; return last; };
})();
</script>
"""


def add_clock(text):
    """`text` with CLOCK_SCRIPT placed before any other script runs."""
    m = re.search(r"<head\b[^>]*>", text, re.I) or re.search(r"<html\b[^>]*>", text, re.I) \
        or DOCTYPE.match(text)
    if not m:
        return CLOCK_SCRIPT + text
    return text[:m.end()] + CLOCK_SCRIPT + text[m.end():]


def run_chrome(args):
    """Run Chrome, killing its whole process group on timeout. Returns (code, stdout)."""
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            stdin=subprocess.DEVNULL, start_new_session=True)
    try:
        out, _ = proc.communicate(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        raise
    return proc.returncode, out.decode("utf-8", errors="replace")


def chrome_base(chrome, profile):
    return [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            f"--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check",
            "--virtual-time-budget=10000"]


def measure(chrome, text, work):
    """The page's full height in CSS pixels, or None when it cannot be measured."""
    probe = work / "measure.html"
    probe.write_text(add_before_body_end(add_clock(text), MEASURE_SCRIPT), encoding="utf-8")
    profile = work / "profile-measure"
    args = chrome_base(chrome, profile) + [f"--window-size={WIDTH},1000", "--dump-dom",
                                           probe.as_uri()]
    try:
        code, out = run_chrome(args)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if code != 0:
        return None
    m = re.search(rf'{HEIGHT_ATTR}="(\d+)"', out)
    return int(m.group(1)) if m else None


def screenshot(chrome, html_path, png_path, work):
    """Take the PNG. Returns (png path or None, list of note sentences)."""
    notes = []
    text = html_path.read_text(encoding="utf-8")
    height = measure(chrome, text, work)
    if not height or height <= 0:
        height = FALLBACK_HEIGHT
        notes.append(f"페이지 높이를 재지 못해 {FALLBACK_HEIGHT}px 높이로 찍었습니다.")
    elif height > MAX_HEIGHT:
        notes.append(f"페이지 높이가 {height}px라서 {MAX_HEIGHT}px까지만 찍었습니다.")
        height = MAX_HEIGHT
    if png_path.exists():
        png_path.unlink()
    # Render a temp copy carrying the clock fix; the standalone HTML stays as the page is.
    shot = work / "shot.html"
    shot.write_text(add_clock(text), encoding="utf-8")
    profile = work / "profile-shot"
    args = chrome_base(chrome, profile) + [
        "--force-device-scale-factor=1", f"--window-size={WIDTH},{height}",
        f"--screenshot={png_path.resolve()}", shot.as_uri()]
    try:
        code, _ = run_chrome(args)
    except subprocess.TimeoutExpired:
        return None, notes + [f"Chrome이 {TIMEOUT}초 안에 끝나지 않아 PNG 없이 HTML만 만들었습니다."]
    except OSError as e:
        return None, notes + [f"Chrome을 실행하지 못해 PNG 없이 HTML만 만들었습니다({e})."]
    if code != 0 or not png_path.is_file() or png_path.stat().st_size == 0:
        return None, notes + [f"Chrome이 PNG를 만들지 못해(종료 코드 {code}) HTML만 만들었습니다."]
    return png_path, notes


# --- entry points ----------------------------------------------------------------------

def snapshot(page_path, out_dir):
    """Write <out_dir>/<stem>.html and, when Chrome works, <out_dir>/<stem>.png.
    Returns {"png": str|None, "html": str, "note": str}."""
    page_path = Path(page_path)
    try:
        page = page_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise Failure(f"화면 파일을 읽지 못했습니다: {page_path} ({e.__class__.__name__})")
    out = Path(out_dir)
    try:
        out.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        raise Failure(f"출력 폴더를 만들지 못했습니다: {out} ({e.__class__.__name__})")

    text, missing = standalone(page, page_path.resolve().parent)
    html_path = out / f"{page_path.stem}.html"
    try:
        html_path.write_text(text, encoding="utf-8")
    except OSError as e:
        raise Failure(f"HTML 사본을 쓰지 못했습니다: {html_path} ({e.__class__.__name__})")

    notes = []
    if missing:
        notes.append("찾지 못한 파일: " + ", ".join(missing))
    png = None
    chrome = find_chrome()
    if not chrome:
        notes.append("Chrome이 없어 PNG 없이 HTML만 만들었습니다.")
    else:
        work = Path(tempfile.mkdtemp(prefix="logbook-snapshot-"))
        try:
            png_path, shot_notes = screenshot(chrome, html_path, out / f"{page_path.stem}.png",
                                              work)
            notes.extend(shot_notes)
            png = str(png_path) if png_path else None
        except Exception as e:  # Chrome problems never stop the caller
            notes.append(f"PNG를 만들지 못해 HTML만 만들었습니다({e.__class__.__name__}).")
        finally:
            shutil.rmtree(work, ignore_errors=True)
    return {"png": png, "html": str(html_path), "note": " ".join(notes)}


def main(argv):
    if len(argv) != 2 or argv[0] in ("-h", "--help"):
        print("usage: snapshot.py <page.html> <out-dir>", file=sys.stderr)
        return 2
    try:
        result = snapshot(argv[0], argv[1])
    except Failure as e:
        print(str(e))
        return FAILED
    if result["png"]:
        print(f"PNG: {result['png']}")
    print(f"HTML: {result['html']}")
    if result["note"]:
        print(result["note"])
    if result["png"]:
        print("PNG와 HTML 사본을 만들었습니다.")
        return OK
    print("PNG는 만들지 못했고 HTML 사본만 만들었습니다.")
    return FAILED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
