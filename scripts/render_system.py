#!/usr/bin/env python3
"""Render the project docs in docs/system/ into one HTML slide deck (the handbook).

Each doc's `##` sections become slides after a table-of-contents slide. The
slide renderer and template are the ones render_brief.py uses, and like it this
refuses docs that carry HTML (exit 4). Standard library only.
"""
import html
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from render_brief import (  # noqa: E402
    TEMPLATE,
    fail,
    html_in_markdown,
    html_problem,
    inline,
    render_meta,
    render_slide,
    split_sections,
)

ORDER = ["overview.md", "stack.md", "flows.md", "data-model.md"]


def git(*args, cwd=None):
    result = subprocess.run(["git", *args], capture_output=True, text=True, cwd=cwd)
    return result.stdout.strip() if result.returncode == 0 else ""


def ordered_docs(folder):
    docs = sorted(p.name for p in folder.glob("*.md"))
    return [n for n in ORDER if n in docs] + [n for n in docs if n not in ORDER]


def title_of(text, fallback):
    line = next((l for l in text.splitlines() if l.startswith("# ")), "")
    return line[2:].strip() or fallback


def meta_line(text):
    """The first `>` line before the first `##` section, where the handbook link lives."""
    head = text.split("\n## ", 1)[0]
    return next((l[1:].strip() for l in head.splitlines() if l.startswith(">")), "")


def main(argv):
    if len(argv) != 3:
        fail("usage: render-system.sh <docs/system> <out.html>", 2)
    folder, out = pathlib.Path(argv[1]), pathlib.Path(argv[2])
    if not folder.is_dir():
        fail(f"no such folder: {folder}", 2)
    names = ordered_docs(folder)
    if not names:
        fail(f"no .md docs in {folder}", 3)

    docs, problems = [], []
    for name in names:
        text = (folder / name).read_text(encoding="utf-8")
        found = html_in_markdown(text)
        if found:
            problems.append(html_problem(name, found))
            continue
        sections = split_sections(text)
        if sections:
            docs.append((name, text, title_of(text, name), sections))
    if problems:
        fail(" / ".join(problems), 4)
    if not docs:
        fail(f"the docs in {folder} have no ## sections", 3)

    total = 1 + sum(len(d[3]) for d in docs)
    repo = str(folder.resolve())
    cards, slides, index = [], [], 2
    for name, text, title, sections in docs:
        links = " · ".join(f'<a href="#s{index + i}">{inline(t)}</a>' for i, (t, _) in enumerate(sections))
        last = git("log", "-1", "--format=%cs · %h", "--", name, cwd=repo)
        when = f"<p>마지막 수정: {html.escape(last)}</p>" if last else "<p>아직 커밋하지 않은 문서</p>"
        cards.append(f'<div class="card"><b>{inline(title)}</b><p>{links}</p>{when}</div>')
        for section_title, body in sections:
            slides.append(render_slide(index, total, section_title, body, label=f"{title} · {section_title}"))
            index += 1
    toc = (
        '<section class="slide" id="s1">\n'
        f'<div class="slide-head"><span class="no">01 / {total:02d}</span><span>목차</span></div>\n'
        f"<h2>문서 {len(docs)}개를 {total - 1}장에 담았습니다</h2>\n"
        f'<div class="freeform"><div class="cards">{"".join(cards)}</div></div>\n</section>'
    )

    overview = next((d for d in docs if d[0] == "overview.md"), docs[0])
    name = re.sub(r"\s*\(#\d+\)\s*$", "", overview[2])
    chips = render_meta(meta_line(overview[1]))
    branch = git("rev-parse", "--abbrev-ref", "HEAD", cwd=repo)
    commit = git("rev-parse", "--short", "HEAD", cwd=repo)
    if commit:
        date = git("log", "-1", "--format=%cs", cwd=repo)
        chips += f'\n<span class="chip">{html.escape(f"기준: {branch}@{commit} · {date}")}</span>'
        if git("status", "--porcelain", "--", ".", cwd=repo):
            chips += '\n<span class="chip">커밋하지 않은 수정 포함</span>'

    page = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "{{PAGE_TITLE}}": html.escape(f"{name} 프로젝트 문서"),
        "{{EYEBROW}}": "프로젝트 문서",
        "{{HEADING}}": inline(name),
        "{{META}}": chips,
        "{{SLIDES}}": toc + "\n\n" + "\n\n".join(slides),
        "{{FOOTER}}": html.escape(f"원본: {folder.as_posix().rstrip('/')}/"),
    }
    for key, value in replacements.items():
        page = page.replace(key, value)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    print(f"rendered {total} slides (system) -> {out}")


if __name__ == "__main__":
    main(sys.argv)
