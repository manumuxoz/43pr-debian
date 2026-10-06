#!/usr/bin/env python3
"""Check that relative links in the repository's Markdown files exist.

Used by CI (.github/workflows/checks.yml) and runnable by hand:

    python3 tools/check-links.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    ROOT / "README.md",
    ROOT / "README.es.md",
    ROOT / "CHANGELOG.md",
    ROOT / "NOTICE.md",
    *sorted((ROOT / "docs").rglob("*.md")),
    *sorted((ROOT / ".github").rglob("*.md")),
]
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def main() -> int:
    errors = 0
    for md in FILES:
        if not md.is_file():
            continue
        text = md.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), 1):
            for target in LINK_RE.findall(line):
                target = target.split("#", 1)[0].strip()
                if not target or SCHEME_RE.match(target):
                    continue  # anchor-only, absolute URL or mailto:
                if not (md.parent / target).exists():
                    print(f"{md.relative_to(ROOT)}:{lineno}: broken link -> {target}")
                    errors += 1
    if errors:
        print(f"\n{errors} broken link(s) found.")
        return 1
    print("All relative links OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
