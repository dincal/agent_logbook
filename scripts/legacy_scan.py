#!/usr/bin/env python3
"""List what does not fit logbook's layout in a repository: traces of earlier agent
tools (paperclip, autopilot) and documents outside the places logbook keeps them.

Prints one tab-separated line per item: kind, path, note. Prints nothing when the
repository fits. Standard library only; reads, never writes.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

LEGACY_PATHS = [
    ".paperclip", ".agent-conventions", ".claude-skills-convention", ".autopilot",
    ".specs", ".state", ".claude/specs", ".claude/plans", ".claude/designs", ".claude/state",
    ".agents/specs", ".agents/state",
    "docs/diagram-convention.md", "docs/kanban.md", "docs/board.md",
]
MENTION = r"paperclip|agent-conventions|claude-skills-convention|issue-tracker-sync|\.autopilot/|AUTOPILOT:BEGIN"
OLD_SECTION = re.compile(
    r"문서\s*맵|document\s*map|구조\s*맵|structure\s*map|project\s*structure|작성\s*스타일|writing\s*style|"
    r"style\s*rules|변경\s*반영|change[-\s]*reflection|이슈\s*트래커|issue\s*tracker",
    re.I,
)
OLD_IGNORE = re.compile(
    r"paperclip|agent-conventions|claude-skills-convention|autopilot|^/?\.specs/?$|^/?\.state/?$|"
    r"\.claude/(specs|state|plans|designs)|\.agents/(specs|state)",
    re.I,
)
DOC_PLACES = re.compile(r"^docs/(plans/(\d+-[^/]+\.md|\.gitkeep)|system/|designs/|manual/)")
ROOT_DOCS = {"readme.md", "changelog.md", "agents.md", "claude.md", "license.md", "contributing.md",
             "security.md", "code_of_conduct.md"}


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def lines_of(result):
    return [line for line in result.stdout.splitlines() if line.strip()]


def tracking(path):
    if lines_of(git("ls-files", "--", path)):
        return "git이 관리함"
    if git("check-ignore", "-q", path).returncode == 0:
        return "git이 무시함"
    return "git이 관리하지 않음"


def under_legacy(path):
    return any(path == p or path.startswith(p + "/") for p in LEGACY_PATHS)


def rule_files():
    """AGENTS.md and CLAUDE.md, each real file once (a symlink counts as its target)."""
    seen, files = set(), []
    for name in ("AGENTS.md", "CLAUDE.md"):
        path = pathlib.Path(name)
        if not path.exists():
            continue
        real = path.resolve()
        if real in seen:
            continue
        seen.add(real)
        files.append(name if not path.is_symlink() else os.path.relpath(real))
    return files


def scan():
    items = []
    for path in LEGACY_PATHS:
        if os.path.lexists(path):
            items.append(("옛 도구 파일", path, tracking(path)))

    root = pathlib.Path.cwd().resolve()
    for line in lines_of(git("worktree", "list", "--porcelain")):
        if not line.startswith("worktree "):
            continue
        tree = pathlib.Path(line[len("worktree "):]).resolve()
        try:
            rel = tree.relative_to(root).as_posix()
        except ValueError:
            continue
        if under_legacy(rel):
            changes = len(lines_of(git("-C", str(tree), "status", "--porcelain")))
            items.append(("옛 worktree", rel, f"바뀐 파일 {changes}개"))

    for name in rule_files():
        inside_logbook = False
        for number, line in enumerate(pathlib.Path(name).read_text(encoding="utf-8").splitlines(), start=1):
            if line.startswith("<!-- logbook:begin"):
                inside_logbook = True
            elif line.startswith("<!-- logbook:end"):
                inside_logbook = False
            elif re.match(r"\s*<!--\s*AUTOPILOT:BEGIN", line):
                items.append(("옛 규칙", f"{name}:{number}", "AUTOPILOT 블록"))
            elif not inside_logbook and re.match(r"#{1,6}\s", line) and OLD_SECTION.search(line):
                items.append(("옛 규칙", f"{name}:{number}", line.strip()))

    grep = git("grep", "-I", "-i", "-c", "-E", MENTION)
    for line in lines_of(grep):
        path, _, count = line.rpartition(":")
        if under_legacy(path) or path == ".gitignore" or path.startswith("docs/plans/"):
            continue
        items.append(("옛 도구 언급", path, f"{count}줄"))

    if os.path.isfile(".gitignore"):
        for number, line in enumerate(pathlib.Path(".gitignore").read_text(encoding="utf-8").splitlines(), start=1):
            if line.strip() and OLD_IGNORE.search(line.strip()):
                items.append(("옛 무시 목록", f".gitignore:{number}", line.strip()))

    links = set()
    for entry in sorted(pathlib.Path(".").iterdir()):
        if entry.is_symlink() and entry.name != "CLAUDE.md" and entry.name.lower().endswith(".md"):
            target = os.readlink(entry)
            if os.path.basename(target) in ("AGENTS.md", "CLAUDE.md"):
                links.add(entry.name)
                items.append(("다른 규칙 링크", entry.name, f"{target}를 가리키는 링크"))

    docs = lines_of(git("ls-files", "--", "docs")) + lines_of(git("ls-files", "--others", "--exclude-standard", "--", "docs"))
    for path in dict.fromkeys(docs):
        if not DOC_PLACES.match(path) and not under_legacy(path):
            items.append(("자리 밖 문서", path, tracking(path)))
    for path in lines_of(git("ls-files", "--", "*.md")):
        if "/" not in path and path.lower() not in ROOT_DOCS and path not in links:
            items.append(("자리 밖 문서", path, tracking(path)))
    return items


def main():
    parser = argparse.ArgumentParser(description="logbook 규약에 맞지 않는 옛 도구의 흔적과 자리 밖 문서를 찾습니다.")
    parser.add_argument("--dir", help="검사할 저장소(기본: 지금 폴더의 저장소)")
    args = parser.parse_args()
    if args.dir:
        os.chdir(args.dir)
    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0:
        print("legacy-scan: git 저장소 안에서 실행하세요.", file=sys.stderr)
        sys.exit(2)
    os.chdir(top.stdout.strip())
    for kind, path, note in scan():
        print(f"{kind}\t{path}\t{note}")


if __name__ == "__main__":
    main()
