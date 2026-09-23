"""Rename the slash command /qt to /qtf across code and docs.

    python tools/rename_slash.py          rewrite the files in place
    python tools/rename_slash.py --check  exit 1 if anything is still /qt

Idempotent: /qtf is never touched again, so it can be re-run after merging a
branch that still says /qt. History is left as it was typed: the released
sections of CHANGELOG.md, and the dated measurement runs in docs/MEASUREMENTS.md.
So is any line that already mentions /qtf -- that line is about the rename.

Once every open branch has landed with /qtf, this script has done its job and
can be deleted.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OLD = re.compile(r"/qt(?![A-Za-z0-9_])")
NEW = "/qtf"

SKIP_DIRS = {".git", ".claude"}
SUFFIXES = {".lua", ".md", ".toc", ".yml", ".py"}

# (file, first line of the protected region, first line after it or None = EOF)
HISTORY = {
    "CHANGELOG.md": (re.compile(r"^## \d"), None),
    "docs/MEASUREMENTS.md": (re.compile(r"^### Measurement — "), re.compile(r"^### Still unverified")),
}


def files():
    for path in ROOT.rglob("*"):
        rel = path.relative_to(ROOT)
        if rel.parts and rel.parts[0] in SKIP_DIRS:
            continue
        if path.is_file() and path.suffix in SUFFIXES and path.name != "rename_slash.py":
            yield path, rel.as_posix()


def rewrite(text, rel):
    start, stop = HISTORY.get(rel, (None, None))
    out, protected = [], False
    for line in text.splitlines(keepends=True):
        if start and not protected and start.match(line):
            protected = True
        elif protected and stop and stop.match(line):
            protected = False
        # A line that already says /qtf is about the rename itself ("was /qt").
        keep = protected or NEW in line
        out.append(line if keep else OLD.sub(NEW, line))
    return "".join(out)


def main():
    check = "--check" in sys.argv
    left = 0
    for path, rel in files():
        text = path.read_text(encoding="utf-8")
        new = rewrite(text, rel)
        if new != text:
            left += len(OLD.findall(text)) - len(OLD.findall(new))
            if not check:
                path.write_bytes(new.encode("utf-8"))
            print(("still /qt: " if check else "rewrote:   ") + rel)
    if check and left:
        sys.exit(1)


if __name__ == "__main__":
    main()
