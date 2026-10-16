#!/usr/bin/env python3
"""Lists every command and environment a KaTeX release defines.

Usage: python3 tool/katex_commands.py <KaTeX checkout> <out.json>

The JSON feeds tool/probe/katex_coverage_probe.dart, which reports which of
them this package's parser does not support yet.
"""
import re, glob, sys, json
K = sys.argv[1]
names=set(); envs=set()
def add(s):
    s = s.encode('latin-1','backslashreplace').decode('unicode_escape') if '\\u' in s else s.replace('\\\\','\\')
    names.add(s)
for p in glob.glob(K+'/src/functions/*.ts')+[K+'/src/functions.ts']:
    t=open(p,encoding='utf-8').read()
    for m in re.finditer(r'names:\s*\[(.*?)\]', t, re.S):
        for q in re.findall(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'', m.group(1)):
            add(q[0] or q[1])
for p in glob.glob(K+'/src/environments/*.ts'):
    t=open(p,encoding='utf-8').read()
    for m in re.finditer(r'names:\s*\[(.*?)\]', t, re.S):
        for q in re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)): envs.add(q)
for p in [K+'/src/macros.ts', K+'/src/symbols.ts']+glob.glob(K+'/src/functions/*.ts'):
    t=open(p,encoding='utf-8').read()
    for m in re.finditer(r'defineMacro\(\s*"((?:[^"\\]|\\.)*)"', t): add(m.group(1))
    for m in re.finditer(r'defineSymbol\([^,]+,[^,]+,[^,]+,[^,]+,\s*"((?:[^"\\]|\\.)*)"', t): add(m.group(1))
names = sorted(n for n in names if n.startswith('\\') and not n.startswith('\\\\') and '@' not in n and len(n) > 1)
envs = sorted(e for e in envs if re.fullmatch(r'[A-Za-z*]+', e))
json.dump({'commands': names, 'environments': envs}, open(sys.argv[2],'w'), ensure_ascii=False)
print(len(names), 'commands', len(envs), 'envs')
