#!/usr/bin/env python3

import shutil
import subprocess
import sys
from pathlib import Path

TEMPLATE_DIR = "template"


def main() -> None:
    script_dir = Path(__file__).parent
    project_root = sys.argv[1] if len(sys.argv) > 1 else ""

    if not project_root:
        print(f"Usage: {sys.argv[0]} <project_root_directory>")
        sys.exit(1)

    dest = Path.cwd() / project_root
    src = script_dir / TEMPLATE_DIR

    shutil.copytree(src, dest)

    claude_template = dest / ".claude.template"
    claude_dir = dest / ".claude"
    claude_template.rename(claude_dir)

    subprocess.run(["uv", "init"], cwd=dest, check=True)

    # Replace {{PROJECT_NAME}} in all .md files under .claude/
    for md_file in claude_dir.rglob("*.md"):
        text = md_file.read_text(encoding="utf-8")
        md_file.write_text(text.replace("{{PROJECT_NAME}}", project_root), encoding="utf-8")

    version = (script_dir / "version").read_text(encoding="utf-8").strip()
    (dest / "memo.tmp.md").write_text(f"version: {version}\n", encoding="utf-8")

    print(f"Project initialized at: {project_root}")


if __name__ == "__main__":
    main()
