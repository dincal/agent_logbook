#!/usr/bin/env python3
"""Render a logbook plan doc's brief or debrief block into an HTML slide deck.

Standard library only. Each `##` section inside the block becomes one slide; the
section's first short paragraph becomes the slide headline. Fenced `mermaid`
blocks become diagrams, and a list whose items all start with a bold number
becomes tiles. The markdown itself carries no HTML, so it reads the same in any
markdown viewer: a document with HTML blocks or tags is refused (exit 4).
"""
import html
import pathlib
import re
import sys

KINDS = {"brief": ("구현 전 브리핑", "브리핑"), "debrief": ("구현 후 디브리핑", "디브리핑")}
TEMPLATE = pathlib.Path(__file__).resolve().parent.parent / "templates" / "brief.html"
LIST_ITEM = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")
URL_CHARS = r"[A-Za-z0-9\-._~:/?#\[\]@!$&*+,;=%]"


def fail(message, code):
    print(f"render-brief: {message}", file=sys.stderr)
    sys.exit(code)


def extract_block(text, kind):
    """Return the text between marker lines that stand alone; mentions inside prose do not count."""
    pattern = rf"^[ \t]*<!--\s*{kind}:begin\s*-->[ \t]*$(.*?)^[ \t]*<!--\s*{kind}:end\s*-->[ \t]*$"
    match = re.search(pattern, text, re.S | re.M)
    return match.group(1) if match else None


HTML_NAMES = {
    "a", "abbr", "article", "aside", "audio", "b", "blockquote", "br", "button", "canvas", "caption",
    "center", "circle", "code", "dd", "defs", "details", "div", "dl", "dt", "ellipse", "em", "embed",
    "figcaption", "figure", "font", "footer", "form", "g", "h1", "h2", "h3", "h4", "h5", "h6",
    "header", "hr", "i", "iframe", "img", "input", "kbd", "label", "li", "line", "link", "main",
    "mark", "meta", "nav", "object", "ol", "option", "p", "path", "picture", "polygon", "polyline",
    "pre", "rect", "s", "script", "section", "select", "small", "source", "span", "strong", "style",
    "sub", "summary", "sup", "svg", "table", "tbody", "td", "text", "textarea", "tfoot", "th",
    "thead", "tr", "u", "ul", "video",
}
HTML_TAG = re.compile(r"<\s*(/?)\s*([A-Za-z][A-Za-z0-9-]*)\b([^<>]*)>")
CLOSING_TAG = re.compile(r"<\s*/\s*([A-Za-z][A-Za-z0-9-]*)")
VOID_NAMES = {"br", "hr", "img", "wbr"}
# Names that double as placeholders in prose, such as `<path>` or `<label>`. A bare opening
# tag with one of these names counts only when the document also closes it somewhere.
PLACEHOLDER_NAMES = {
    "a", "article", "aside", "audio", "button", "canvas", "caption", "circle", "code", "defs",
    "details", "ellipse", "embed", "figure", "font", "footer", "form", "g", "header", "input",
    "label", "line", "link", "main", "mark", "meta", "nav", "object", "option", "path", "picture",
    "polygon", "polyline", "rect", "section", "select", "small", "source", "summary", "text", "video",
}


def is_html_tag(match, closed):
    """True for a tag a viewer would treat as HTML, false for a placeholder like `<path>`."""
    slash, name, rest = match.group(1), match.group(2).lower(), match.group(3)
    if name not in HTML_NAMES:
        return False
    if slash or name in VOID_NAMES or "=" in rest or rest.rstrip().endswith("/"):
        return True
    return name not in PLACEHOLDER_NAMES or name in closed


def html_in_markdown(text):
    """Return (line number, snippet) for HTML that a markdown viewer would show or drop.

    Counts `html`/`svg` code blocks and HTML tags in prose, tables and mermaid blocks.
    HTML comments are markers that viewers hide, and tags inside inline code or
    inside other code blocks are examples, so neither counts.
    """
    found = []
    scanned = visible_lines(text, found)
    closed = {name.lower() for _, scan in scanned for name in CLOSING_TAG.findall(scan)}
    for number, scan in scanned:
        tag = next((m for m in HTML_TAG.finditer(scan) if is_html_tag(m, closed)), None)
        if tag:
            found.append((number, tag.group(0)))
    return sorted(found)


def visible_lines(text, found):
    """(line number, text) a viewer renders as prose, tables or mermaid, without inline
    code and HTML comments. `html`/`svg`/`xml` code blocks are added to `found`."""
    scanned, fence, in_comment = [], None, False
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if fence is None and not in_comment and stripped.startswith("```"):
            fence = stripped[3:].strip().lower()
            if fence in ("html", "svg", "xml"):
                found.append((number, stripped))
            continue
        if fence is not None:
            if stripped.startswith("```"):
                fence = None
                continue
            if fence != "mermaid":
                continue
        scan = re.sub(r"`[^`]*`", "", line)
        if in_comment:
            if "-->" not in scan:
                continue
            scan, in_comment = scan.split("-->", 1)[1], False
        scan = re.sub(r"<!--.*?-->", "", scan)
        if "<!--" in scan:
            scan, in_comment = scan.split("<!--", 1)[0], True
        scanned.append((number, scan))
    return scanned


def html_problem(name, found):
    """One line naming where the HTML is and what to use instead."""
    where = ", ".join(f"{number}줄 {snippet}" for number, snippet in found[:5])
    more = f" 외 {len(found) - 5}곳" if len(found) > 5 else ""
    return (
        f"{name}에 HTML이 있습니다({where}{more}). md 파일에는 HTML을 넣지 않습니다. "
        "그림은 mermaid로, 숫자 요약은 굵은 숫자로 시작하는 목록으로, 비교는 표로 바꾸세요"
    )


def inline(text):
    """Escape text and apply inline markdown: code, links, bare URLs, bold, italics."""
    codes, links = [], []

    def keep_code(m):
        codes.append("<code>" + html.escape(m.group(1), quote=False) + "</code>")
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", keep_code, text)
    text = html.escape(text, quote=True)

    def keep_link(m):
        links.append(f'<a href="{m.group(2)}">{m.group(1)}</a>')
        return f"\x01{len(links) - 1}\x01"

    # The text is already escaped, so a quote inside a URL shows up as an entity, never as markup.
    text = re.sub(rf"\[([^\]]+)\]\((https?://{URL_CHARS}+)\)", keep_link, text)

    def bare(m):
        url, tail = m.group(1), ""
        while url and url[-1] in ".,;:!?" and not url.endswith(("&amp;", "&quot;", "&#x27;")):
            url, tail = url[:-1], url[-1] + tail
        return f'<a href="{url}">{url}</a>{tail}'

    text = re.sub(rf"(https?://{URL_CHARS}+)", bare, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![*\w])\*(?![\s*])([^*]+?)\*(?![*\w])", r"<em>\1</em>", text)
    text = re.sub(r"\x01(\d+)\x01", lambda m: links[int(m.group(1))], text)
    text = re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)
    return text


def split_row(row):
    """Split a markdown table row on pipes that are outside code spans."""
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|"):
        row = row[:-1]
    cells, current, in_code = [], "", False
    for ch in row:
        if ch == "`":
            in_code = not in_code
        if ch == "|" and not in_code:
            cells.append(current.strip())
            current = ""
        else:
            current += ch
    cells.append(current.strip())
    return cells


def parse_blocks(markdown):
    lines = markdown.splitlines()
    blocks, i, n = [], 0, len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if not stripped or re.fullmatch(r"<!--.*-->", stripped):
            i += 1
            continue
        if stripped.startswith("```"):
            lang, body = stripped[3:].strip().lower(), []
            i += 1
            while i < n and not lines[i].strip().startswith("```"):
                body.append(lines[i])
                i += 1
            i += 1
            blocks.append(("code", lang, "\n".join(body)))
            continue
        if stripped.startswith("### "):
            blocks.append(("h3", stripped[4:].strip()))
            i += 1
            continue
        if stripped.startswith("|") and i + 1 < n and re.match(r"^\s*\|?\s*:?-{3,}", lines[i + 1]):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(lines[i])
                i += 1
            blocks.append(("table", rows))
            continue
        if stripped.startswith(">"):
            quote = []
            while i < n and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            blocks.append(("quote", " ".join(q for q in quote if q)))
            continue
        match = LIST_ITEM.match(line)
        if match:
            ordered, items = match.group(2)[0].isdigit(), []
            while i < n:
                item = LIST_ITEM.match(lines[i])
                if item:
                    depth = 1 if len(item.group(1).expandtabs(2)) >= 2 else 0
                    items.append([depth, item.group(3)])
                    i += 1
                elif lines[i].strip() and lines[i].startswith("  ") and items:
                    items[-1][1] += " " + lines[i].strip()
                    i += 1
                else:
                    break
            blocks.append(("list", ordered, items))
            continue
        paragraph = [stripped]
        i += 1
        while i < n and lines[i].strip() and not re.match(r"^\s*(```|\||>|### |[-*]\s|\d+\.\s)", lines[i]):
            paragraph.append(lines[i].strip())
            i += 1
        blocks.append(("p", " ".join(paragraph)))
    return blocks


def render_list(ordered, items):
    """Top-level items become <li>; deeper items nest as a <ul> inside the item above them."""
    tag, out, i = ("ol" if ordered else "ul"), [], 0
    while i < len(items):
        depth, text = items[i]
        if depth:  # a nested item with no parent above it
            out.append(f"<li>{inline(text)}</li>")
            i += 1
            continue
        children = []
        i += 1
        while i < len(items) and items[i][0]:
            children.append(f"<li>{inline(items[i][1])}</li>")
            i += 1
        nested = f'<ul class="md sub">{"".join(children)}</ul>' if children else ""
        out.append(f"<li>{inline(text)}{nested}</li>")
    return f'<{tag} class="md">{"".join(out)}</{tag}>'


TILE_ITEM = re.compile(r"^\*\*(?P<num>[^*]{1,20})\*\*\s*(?P<rest>.*)$")


def tile_items(items):
    """Tiles for a flat list of two or more items that each start with a bold number, else None."""
    if len(items) < 2 or any(depth for depth, _ in items):
        return None
    tiles = []
    for _, text in items:
        match = TILE_ITEM.match(text)
        if not match or not re.search(r"\d", match.group("num")):
            return None
        what, _, how = match.group("rest").strip().partition(":")
        if not how and "：" in what:
            what, _, how = what.partition("：")
        tiles.append((match.group("num").strip(), what.strip(), how.strip()))
    return tiles


def render_tiles(tiles):
    cells = []
    for num, what, how in tiles:
        num_html = re.sub(r"\s*(/|→)\s*", r" <em>\1</em> ", html.escape(num, quote=False))
        cells.append(
            f'<div class="tile"><div class="num">{num_html}</div>'
            f'<div class="what">{inline(what)}</div><div class="how">{inline(how)}</div></div>'
        )
    return f'<div class="tiles">{"".join(cells)}</div>'


def render_block(block):
    kind = block[0]
    if kind == "p":
        return f"<p>{inline(block[1])}</p>"
    if kind == "h3":
        return f"<h3>{inline(block[1])}</h3>"
    if kind == "code":
        lang, body = block[1], block[2]
        if lang == "mermaid":
            return f'<div class="diagram"><pre class="mermaid">{html.escape(body, quote=False)}</pre></div>'
        return (
            '<div class="code"><button class="copy" type="button">복사</button>'
            f"<pre><code>{html.escape(body, quote=False)}</code></pre></div>"
        )
    if kind == "table":
        rows = block[1]
        head = "".join(f"<th>{inline(c)}</th>" for c in split_row(rows[0]))
        body = "".join(
            "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in split_row(r)) + "</tr>" for r in rows[2:]
        )
        return f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'
    if kind == "quote":
        text = block[1]
        match = re.match(r"^([^:：]{1,24})[:：]\s*(.*)$", text)
        if not match:
            return f'<div class="callout">{inline(text)}</div>'
        label, rest = match.group(1).strip(), match.group(2)
        css = "callout"
        if label.startswith("판단 필요"):
            css += " ok" if rest.startswith("없음") else " warn"
        return f'<div class="{css}"><strong>{inline(label)}</strong> {inline(rest)}</div>'
    if kind == "list":
        tiles = None if block[1] else tile_items(block[2])
        return render_tiles(tiles) if tiles else render_list(block[1], block[2])
    return ""


def split_sections(block_text):
    """Split on `## ` headings that sit outside fenced code."""
    sections, title, body, in_fence = [], None, [], False
    for line in block_text.splitlines():
        if line.strip().startswith("```"):
            in_fence = not in_fence
        if line.startswith("## ") and not in_fence:
            if title is not None:
                sections.append((title, "\n".join(body)))
            title, body = line[3:].strip(), []
        elif title is not None:
            body.append(line)
    if title is not None:
        sections.append((title, "\n".join(body)))
    return sections


def render_slide(index, total, title, body, label=None):
    """One `##` section as a slide. `label` replaces the section title in the slide head."""
    blocks = parse_blocks(body)
    headline = title
    if blocks and blocks[0][0] == "p" and len(blocks[0][1]) <= 160:
        headline = blocks[0][1]
        blocks = blocks[1:]
    parts = "\n".join(render_block(b) for b in blocks)
    head = inline(label) if label is not None else inline(title)
    return (
        f'<section class="slide" id="s{index}">\n'
        f'<div class="slide-head"><span class="no">{index:02d} / {total:02d}</span><span>{head}</span></div>\n'
        f"<h2>{inline(headline)}</h2>\n{parts}\n</section>"
    )


def render_meta(line):
    chips = []
    for part in (p.strip() for p in line.split("·")):
        if not part:
            continue
        match = re.match(rf"^([^:：]+)[:：]\s*(https?://{URL_CHARS}+)$", part)
        if match:
            chips.append(f'<a href="{html.escape(match.group(2))}">{html.escape(match.group(1).strip())}</a>')
        else:
            chips.append(f'<span class="chip">{html.escape(part)}</span>')
    return "\n".join(chips)


def standalone(argv):
    """Remove `--standalone` from argv; it asks for a doctype, for a file opened locally.
    An Artifact gets no doctype, since publishing wraps the page in its own document."""
    flag = "--standalone" in argv
    return [a for a in argv if a != "--standalone"], ("<!doctype html>\n" if flag else "")


def main(argv):
    argv, doctype = standalone(argv)
    if len(argv) != 4 or argv[2] not in KINDS:
        fail("usage: render-brief.sh [--standalone] <plan-doc.md> <brief|debrief> <out.html>", 2)
    doc, kind, out = pathlib.Path(argv[1]), argv[2], pathlib.Path(argv[3])
    if not doc.is_file():
        fail(f"no such file: {doc}", 2)
    text = doc.read_text(encoding="utf-8")
    found = html_in_markdown(text)
    if found:
        fail(html_problem(doc.name, found), 4)
    block = extract_block(text, kind)
    if block is None:
        fail(f"no <!-- {kind}:begin --> ... <!-- {kind}:end --> block in {doc}", 3)
    sections = split_sections(block)
    if not sections:
        fail(f"the {kind} block has no ## sections", 3)

    title_line = next((l for l in text.splitlines() if l.startswith("# ")), "# 플랜")
    heading = title_line[2:].strip()
    issue = re.search(r"\(#(\d+)\)", heading)
    name = re.sub(r"\s*\(#\d+\)\s*$", "", heading) or heading
    meta_line = next((l[1:].strip() for l in text[: text.find(block)].splitlines() if l.startswith(">")), "")
    eyebrow, short = KINDS[kind]
    if issue:
        eyebrow += f" · #{issue.group(1)}"

    total = len(sections)
    slides = "\n\n".join(render_slide(i, total, t, b) for i, (t, b) in enumerate(sections, start=1))
    page = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "{{PAGE_TITLE}}": html.escape(f"{name} {short}"),
        "{{EYEBROW}}": html.escape(eyebrow),
        "{{HEADING}}": inline(name),
        "{{META}}": render_meta(meta_line),
        "{{SLIDES}}": slides,
        "{{FOOTER}}": html.escape(f"원본: {doc.name}의 {kind} 블록"),
    }
    for key, value in replacements.items():
        page = page.replace(key, value)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(doctype + page, encoding="utf-8")
    print(f"rendered {total} slides ({kind}) -> {out}")


if __name__ == "__main__":
    main(sys.argv)
