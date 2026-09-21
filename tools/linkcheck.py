"""Check relative markdown links and GitHub-style #anchors in every .md file.

Usage: python tools/linkcheck.py [repo root]   (defaults to the repository root)
Exits 1 when a link target or anchor does not exist. External URLs are not fetched.
"""
import io, os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
mds = []
for d, _, fs in os.walk(root):
    if '.git' in d.split(os.sep):
        continue
    for f in fs:
        if f.endswith('.md'):
            mds.append(os.path.join(d, f))


def anchors(path):
    out, seen, fence = set(), {}, False
    for line in io.open(path, encoding='utf-8'):
        if line.startswith('```'):
            fence = not fence
        if fence:
            continue
        m = re.match(r'#{1,6}\s+(.*?)\s*$', line)
        if not m:
            continue
        t = m.group(1).lower()
        t = re.sub(r'[^\w\- ]', '', t, flags=re.UNICODE).replace(' ', '-')
        n = seen.get(t, 0)
        seen[t] = n + 1
        out.add(t if n == 0 else '%s-%d' % (t, n))
    return out


bad = 0
for md in mds:
    text = io.open(md, encoding='utf-8').read()
    text = re.sub(r'```.*?```', '', text, flags=re.S)
    for target in re.findall(r'\]\(([^)\s]+)\)', text):
        if re.match(r'https?:', target):
            continue
        path, _, frag = target.partition('#')
        dest = os.path.normpath(os.path.join(os.path.dirname(md), path)) if path else md
        if not os.path.exists(dest):
            print('MISSING FILE  %s -> %s' % (os.path.relpath(md, root), target)); bad += 1
        elif frag and dest.endswith('.md') and frag not in anchors(dest):
            print('BAD ANCHOR    %s -> %s' % (os.path.relpath(md, root), target)); bad += 1
print('%d problem(s) in %d file(s)' % (bad, len(mds)))
sys.exit(1 if bad else 0)
