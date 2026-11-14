#!/usr/bin/env python3
"""Read-only extraction of textual BoxData input; does not evaluate Wolfram code."""
import re, sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
# A small box-expression parser sufficient for these notebooks.
tokens=re.compile(r'"(?:\\.|[^"\\])*"|[A-Za-z$][\w$]*|[^\s]',re.S)
def parse(ts,i):
    t=ts[i]; i+=1
    if t.startswith('"'):
        t=t[1:-1].replace('\\\n','').replace('\\n','\n').replace('\\t','\t').replace('\\"','"').replace('\\\\','\\')
        for a,b in [('\\[IndentingNewLine]','\n'),('\\[Rule]','->'),('\\[Pi]','Pi'),('\\[Infinity]','Infinity'),('\\[LeftDoubleBracket]','[['),('\\[RightDoubleBracket]',']]'),('\\<',''),('\\>','')]: t=t.replace(a,b)
        return t,i
    if t=='{':
        a=[]
        while ts[i]!='}':
            v,i=parse(ts,i); a.append(v)
            if ts[i]==',': i+=1
        return ''.join(a),i+1
    if i<len(ts) and ts[i]=='[':
        i+=1; a=[]
        while ts[i]!=']':
            v,i=parse(ts,i); a.append(v)
            if ts[i]==',':i+=1
        i+=1
        if t in ('RowBox','BoxData'): return ''.join(a),i
        if t in ('StyleBox','FormBox','TagBox'): return a[0],i
        if t=='FractionBox': return '('+a[0]+')/('+a[1]+')',i
        if t=='SuperscriptBox': return '('+a[0]+')^('+a[1]+')',i
        if t=='SqrtBox': return 'Sqrt['+a[0]+']',i
        return t+'['+','.join(a)+']',i
    return t,i
for m in re.finditer(r'Cell\[BoxData\[',s):
    start=m.end()-8
    # scan balanced brackets, respecting strings
    i=start+8; depth=1; instr=False; esc=False
    while i<len(s) and depth:
        c=s[i]
        if instr:
            if esc: esc=False
            elif c=='\\':esc=True
            elif c=='"':instr=False
        elif c=='"':instr=True
        elif c=='[':depth+=1
        elif c==']':depth-=1
        i+=1
    if re.match(r'\s*,\s*"Input"',s[i:i+30]):
        try:
            out,_=parse(tokens.findall(s[start:i]),0)
            print('\n(* notebook line',s.count('\n',0,m.start())+1,'*)\n'+out)
        except (IndexError,RecursionError) as e: print('(* extraction failed:',e,'*)')
