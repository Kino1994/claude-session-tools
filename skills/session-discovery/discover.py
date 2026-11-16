#!/usr/bin/env python3
"""List past Claude Code sessions for a folder (optionally including subfolders).
Usage: discover.py [folder] [--sub] [--limit N] [--json] [--exclude SESSION_ID]
NOTE: reads ~/.claude/projects/*/*.jsonl, an internal, undocumented format."""
import json, os, re, sys, glob, datetime, argparse

ap = argparse.ArgumentParser()
ap.add_argument('dir', nargs='?', default=os.getcwd())
ap.add_argument('--sub', action='store_true', help='include subfolders')
ap.add_argument('--limit', type=int, default=15)
ap.add_argument('--json', action='store_true')
ap.add_argument('--exclude', default=None, help='session id to skip (the current one)')
a = ap.parse_args()

enc_path = lambda p: re.sub(r'[^A-Za-z0-9]', '-', p)
target = os.path.realpath(os.path.expanduser(a.dir))
enc = enc_path(target)
root = os.path.expanduser('~/.claude/projects')
dirs = [d for d in glob.glob(os.path.join(root, '*'))
        if os.path.basename(d) == enc or (a.sub and os.path.basename(d).startswith(enc + '-'))]

def text_of(msg):
    c = msg.get('content')
    if isinstance(c, str): return c
    if isinstance(c, list):
        return ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')
    return ''

out = []
for d in dirs:
    for f in glob.glob(os.path.join(d, '*.jsonl')):
        sid = os.path.basename(f)[:-6]
        if sid == a.exclude: continue
        title = first = last_prompt = cwd = branch = None
        n_user = 0; end = None; cwds = set()
        try:
            with open(f, errors='ignore') as fh:
                for line in fh:
                    try: o = json.loads(line)
                    except Exception: continue
                    t = o.get('type')
                    if t == 'ai-title': title = o.get('aiTitle') or title
                    elif t == 'summary': title = title or o.get('summary')
                    elif t == 'last-prompt' and o.get('lastPrompt'): last_prompt = o['lastPrompt']
                    if o.get('cwd'):
                        cwds.add(o['cwd'])
                        if not cwd: cwd = o['cwd']; branch = o.get('gitBranch')
                    if o.get('timestamp'): end = o['timestamp']
                    if t == 'user' and not o.get('isSidechain') and not o.get('isMeta'):
                        txt = text_of(o.get('message', {})).strip()
                        if txt and not txt.startswith('<'):
                            n_user += 1
                            first = first or txt
        except OSError: continue
        if not n_user: continue
        # folder from which `claude --resume <id>` finds this session
        pdir = os.path.basename(d)
        resume_dir = next((c for c in cwds if enc_path(c) == pdir), cwd)
        if resume_dir and not a.sub and os.path.realpath(resume_dir) != target: continue
        if resume_dir and a.sub and not (resume_dir == target or resume_dir.startswith(target + os.sep)): continue
        out.append(dict(id=sid, resume_dir=resume_dir, title=title, first=first, last=last_prompt,
                        branch=branch, msgs=n_user, end=end or
                        datetime.datetime.utcfromtimestamp(os.path.getmtime(f)).isoformat()))

out.sort(key=lambda s: s['end'] or '', reverse=True)
seen = set(); out = [s for s in out if not (s['id'] in seen or seen.add(s['id']))]  # same session copied into 2 projects
out = out[:a.limit]
if a.json:
    print(json.dumps(out, ensure_ascii=False, indent=2)); sys.exit()
if not out:
    print(f'No past sessions in {target}' + (' or its subfolders' if a.sub else '')); sys.exit()
short = lambda s, n=90: (s or '').replace('\n', ' ')[:n]
for i, s in enumerate(out, 1):
    when = (s['end'] or '')[:16].replace('T', ' ')
    print(f"{i:>2}. [{when}] {short(s['title'] or s['first'], 70)}")
    print(f"    id={s['id']}  msgs={s['msgs']}  resume_dir={s['resume_dir']}"
          + (f"  branch={s['branch']}" if s['branch'] and s['branch'] != 'HEAD' else ''))
    if s['first'] and s['title']: print(f"    first: {short(s['first'])}")
    if s['last'] and s['last'] != s['first']: print(f"    last:  {short(s['last'])}")
