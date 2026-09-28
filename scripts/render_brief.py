#!/usr/bin/env python3
"""Render a logbook plan doc's brief or debrief block into a CTO-style HTML deck.

Standard library only. Each `##` section inside the block becomes one slide; the
section's first short paragraph becomes the slide headline. Fenced `mermaid`
blocks become diagrams, and fenced `html` or `svg` blocks pass through as
free-form diagrams after scripts and event handlers are stripped.
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


ACTIVE_TAGS = "script|style|iframe|frame|frameset|object|embed|applet|link|meta|base|form"
URL_ATTR = re.compile(r"""(\s)(href|src|xlink:href|action|formaction)(\s*=\s*)("[^"]*"|'[^']*'|[^\s>]+)""", re.I)


def neutralize_url(match):
    """Replace a script URL even when it hides behind spaces, tabs or character references."""
    raw = match.group(4)
    value = raw[1:-1] if raw[:1] in "\"'" else raw
    probe = re.sub(r"[\x00-\x20]+", "", html.unescape(value)).lower()
    if probe.startswith(("javascript:", "vbscript:", "data:text/html")):
        return f'{match.group(1)}{match.group(2)}="#"'
    return match.group(0)


def sanitize_html(fragment):
    """Keep author-drawn HTML/SVG but drop active content: scripts, embeds, handlers, script URLs.

    Runs until nothing changes, so a tag rebuilt by an earlier removal
    (for example `<scr<script>ipt>`) is removed on the next pass.
    """
    previous = None
    while previous != fragment:
        previous = fragment
        fragment = re.sub(rf"<\s*({ACTIVE_TAGS})\b[^>]*>.*?<\s*/\s*\1\s*>", "", fragment, flags=re.I | re.S)
        fragment = re.sub(rf"<\s*/?\s*({ACTIVE_TAGS})\b[^>]*>", "", fragment, flags=re.I)
        fragment = re.sub(r"\s+on[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)", "", fragment, flags=re.I)
        fragment = URL_ATTR.sub(neutralize_url, fragment)
    return fragment


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
        if lang in ("html", "svg"):
            return f'<div class="freeform">{sanitize_html(body)}</div>'
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
        return render_list(block[1], block[2])
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


def render_slide(index, total, title, body):
    blocks = parse_blocks(body)
    headline = title
    if blocks and blocks[0][0] == "p" and len(blocks[0][1]) <= 160:
        headline = blocks[0][1]
        blocks = blocks[1:]
    parts = "\n".join(render_block(b) for b in blocks)
    return (
        f'<section class="slide" id="s{index}">\n'
        f'<div class="slide-head"><span class="no">{index:02d} / {total:02d}</span><span>{inline(title)}</span></div>\n'
        f"<h2>{inline(headline)}</h2>\n{parts}\n</section>"
    )


def missing_diagrams(block_text):
    """Name the required pictures a block lacks: the main logic flow and the data-model change."""
    mermaid = "\n".join(re.findall(r"```mermaid\s*\n(.*?)```", block_text, re.S))
    missing = []
    if not re.search(r"^\s*(flowchart|graph|sequenceDiagram|stateDiagram)", mermaid, re.M):
        missing.append("main logic flowchart (mermaid flowchart or sequenceDiagram)")
    if not re.search(r"^\s*erDiagram", mermaid, re.M) and "ERD 변화 없음" not in block_text:
        missing.append("ERD change (mermaid erDiagram, or a line starting with 'ERD 변화 없음')")
    return missing


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


def main(argv):
    if len(argv) != 4 or argv[2] not in KINDS:
        fail("usage: render-brief.sh <plan-doc.md> <brief|debrief> <out.html>", 2)
    doc, kind, out = pathlib.Path(argv[1]), argv[2], pathlib.Path(argv[3])
    if not doc.is_file():
        fail(f"no such file: {doc}", 2)
    text = doc.read_text(encoding="utf-8")
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

    for warning in missing_diagrams(block):
        print(f"render-brief: warning: the {kind} block has no {warning}", file=sys.stderr)

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
    out.write_text(page, encoding="utf-8")
    print(f"rendered {total} slides ({kind}) -> {out}")


if __name__ == "__main__":
    main(sys.argv)
