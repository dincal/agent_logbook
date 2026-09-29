#!/usr/bin/env python3
"""Check that the project docs in docs/system/ still match the code they describe.

Each doc starts with a marker comment such as

    <!-- logbook:system sources="package.json src/api/**" tables="12" checked="2026-09-28" -->

`sources` lists git path patterns for the code the doc describes. A doc is
behind the code when that code changed after the doc did. By default the
baseline is the last commit that touched the doc, and uncommitted edits count.
`--range A...B` checks a pull request instead: code a doc describes changed in
the range while the doc did not. `tables` is the number of database tables the
schema defines; the ERD in data-model.md must show that many tables. A doc that
carries HTML gets a warning, since markdown viewers show it as raw code.

Standard library only. Prints one line per finding and a summary line.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from render_brief import html_in_markdown  # noqa: E402

ORDER = ["overview.md", "stack.md", "flows.md", "data-model.md"]
MARKER = re.compile(r"<!--\s*logbook:system\b(?P<attrs>.*?)-->", re.S)
ATTR = re.compile(r'([A-Za-z_]+)="([^"]*)"')
INLINE_CODE = re.compile(r"`([^`\s]+)`")
FILE_LIKE = re.compile(r"(/|\.[A-Za-z0-9]{1,6})$")
ENTITY = r'("[^"]+"|[A-Za-z_][A-Za-z0-9_\-]*)(?:\[[^\]]*\])?'
CARD_LEFT = r"(?:\|o|\|\||\}o|\}\|)"
CARD_RIGHT = r"(?:o\||\|\||o\{|\|\{)"
RELATION = re.compile(rf"^\s*{ENTITY}\s*{CARD_LEFT}(?:--|\.\.){CARD_RIGHT}\s*{ENTITY}")
BLOCK_OPEN = re.compile(rf"^\s*{ENTITY}\s*\{{")
LONE = re.compile(rf"^\s*{ENTITY}\s*$")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def lines_of(result):
    return [line for line in result.stdout.splitlines() if line.strip()]


def ordered_docs(folder):
    docs = sorted(p.name for p in folder.glob("*.md"))
    return [n for n in ORDER if n in docs] + [n for n in docs if n not in ORDER]


def parse_marker(text):
    match = MARKER.search(text)
    return dict(ATTR.findall(match.group("attrs"))) if match else None


def pathspecs(patterns):
    return [f":(glob){p}" for p in patterns]


def erd_tables(text):
    """Distinct entity names across the doc's mermaid erDiagram blocks."""
    names = set()
    for block in re.findall(r"```mermaid[ \t]*\n(.*?)```", text, re.S):
        body = block.strip().splitlines()
        if not body or not body[0].strip().startswith("erDiagram"):
            continue
        in_attrs = False
        for line in body[1:]:
            stripped = line.strip()
            if in_attrs:
                in_attrs = not stripped.startswith("}")
                continue
            if not stripped or stripped.startswith("%%"):
                continue
            relation = RELATION.match(line)
            if relation:
                names.update(n.strip('"') for n in relation.groups())
                continue
            opened = BLOCK_OPEN.match(line)
            if opened:
                names.add(opened.group(1).strip('"'))
                in_attrs = "}" not in stripped
                continue
            lone = LONE.match(line)
            if lone:
                names.add(lone.group(1).strip('"'))
    return names


def missing_paths(text, root):
    """Inline-code paths (with a slash, ending in `/` or a file extension) that do not exist."""
    missing = []
    for token in INLINE_CODE.findall(text):
        token = token.rstrip(".,;:)")
        if "/" not in token or not FILE_LIKE.search(token):
            continue
        if re.search(r"[*?<>{}\[\]$~@=]|://|\.\.", token) or token.startswith(("/", "-")):
            continue
        if (root / token).exists() or token in missing:
            continue
        if git("check-ignore", "-q", token).returncode == 0:
            continue  # a local-only path such as .logbook/ is fine to mention
        missing.append(token)
    return missing


def check_doc(args, root, rel, doc_paths):
    """Return (changed files that make the doc stale, warnings) for one doc."""
    text = (root / rel).read_text(encoding="utf-8")
    warnings = []
    marker = parse_marker(text)
    patterns = (marker or {}).get("sources", "").split()
    if marker is None:
        warnings.append('첫 줄 주석(<!-- logbook:system sources="..." -->)이 없습니다')
        marker = {}
    elif not patterns:
        warnings.append("첫 줄 주석에 sources(이 문서가 설명하는 코드 경로)가 없어서 뒤처졌는지 검사할 수 없습니다")
    for pattern in patterns:
        if not lines_of(git("ls-files", "--", f":(glob){pattern}")):
            warnings.append(f"경로 패턴 '{pattern}'에 맞는 파일이 없습니다")
    for path in missing_paths(text, root):
        warnings.append(f"없는 파일을 가리킵니다: {path}")
    found = html_in_markdown(text)
    if found:
        where = ", ".join(f"{number}줄 {snippet}" for number, snippet in found[:3])
        warnings.append(f"HTML이 들어 있습니다({where}). md에는 HTML 대신 mermaid, 표, 목록을 씁니다")
    if rel.endswith("/data-model.md"):
        tables = erd_tables(text)
        declared = marker.get("tables", "")
        if not tables:
            warnings.append("ERD(mermaid erDiagram)가 없습니다")
        if not declared:
            warnings.append("첫 줄 주석에 tables(스키마에서 센 테이블 수)가 없습니다")
        elif not declared.isdigit():
            warnings.append(f"첫 줄 주석의 tables 값 '{declared}'가 숫자가 아닙니다")
        elif tables and int(declared) != len(tables):
            warnings.append(f"ERD에 나온 테이블은 {len(tables)}개인데, 첫 줄 주석의 tables는 {declared}입니다")

    changed = []
    if patterns and args.range:
        result = git("diff", "--name-only", args.range, "--", *pathspecs(patterns))
        if result.returncode != 0:
            print(f"system-check: git이 범위 {args.range}를 읽지 못했습니다. {result.stderr.strip()}", file=sys.stderr)
            sys.exit(2)
        if not lines_of(git("diff", "--name-only", args.range, "--", rel)):
            changed = lines_of(result)
    elif patterns:
        base = git("log", "-1", "--format=%H", "--", rel).stdout.strip()
        editing = lines_of(git("status", "--porcelain", "--", rel))
        if base and not editing:
            changed = lines_of(git("diff", "--name-only", base, "--", *pathspecs(patterns)))
            changed += lines_of(git("ls-files", "--others", "--exclude-standard", "--", *pathspecs(patterns)))
    changed = [f for f in dict.fromkeys(changed) if f not in doc_paths]
    return changed, warnings


def describe(files):
    shown = ", ".join(files[:3])
    return shown + (f" 외 {len(files) - 3}개" if len(files) > 3 else "")


def main():
    parser = argparse.ArgumentParser(description="docs/system/의 프로젝트 문서가 코드와 맞는지 확인합니다.")
    parser.add_argument("--dir", default="docs/system", help="프로젝트 문서 폴더(기본 docs/system)")
    parser.add_argument("--range", help="PR 범위. 예: origin/main...HEAD")
    parser.add_argument("--strict", action="store_true", help="뒤처진 문서나 경고가 있으면 종료 코드 1")
    args = parser.parse_args()

    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0:
        print("system-check: git 저장소 안에서 실행하세요.", file=sys.stderr)
        sys.exit(2)
    root = pathlib.Path(top.stdout.strip())
    os.chdir(root)
    folder_rel = args.dir.strip("/")
    folder = root / folder_rel
    if not folder.is_dir() or not any(folder.glob("*.md")):
        print(f"{folder_rel}/이 없습니다. /sync로 프로젝트 문서를 만드세요.")
        print("system-check: 문서 0개")
        sys.exit(1 if args.strict else 0)

    names = ordered_docs(folder)
    doc_paths = {f"{folder_rel}/{n}" for n in names}
    stale_count = warn_count = 0
    for name in names:
        changed, warnings = check_doc(args, root, f"{folder_rel}/{name}", doc_paths)
        if changed:
            stale_count += 1
            print(f"뒤처짐\t{name}\t설명하는 코드가 바뀌었습니다: {describe(changed)}")
        for warning in warnings:
            warn_count += 1
            print(f"경고\t{name}\t{warning}")
        if not changed and not warnings:
            print(f"정상\t{name}")
    print(f"system-check: 문서 {len(names)}개, 뒤처진 문서 {stale_count}, 경고 {warn_count}")
    sys.exit(1 if args.strict and (stale_count or warn_count) else 0)


if __name__ == "__main__":
    main()
