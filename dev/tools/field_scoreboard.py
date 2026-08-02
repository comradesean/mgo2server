import re,glob,collections,subprocess
files=sorted(glob.glob('dev/proto/inbound/*.ksy')+glob.glob('dev/proto/outbound/*.ksy')+glob.glob('dev/proto/*.ksy'))
# A field counts as "explained" when its doc states WHY nothing more is knowable. The vocabulary
# is deliberately broad: batches phrase the same finding as "no reader", "no live consumer",
# "dead accessor", "uncalled and unregistered". Missing a phrasing silently understates the work.
NEG=re.compile(r'\b(swept|no store found|no reader|no caller|no live consumer|no consumer'
               r'|dead code|dead accessor|uncalled|unregistered|never read|no writer|moot'
               r'|inert|discarded|unknowable|hazard, not bug|open question)\b',re.I)
# which ids the server actually implements
src=subprocess.run(['bash','-c',"command grep -rhoE '0x4[0-9a-fA-F]{3}|0x[23][0-9a-fA-F]{3}' src/main/java | tr 'A-F' 'a-f' | sort -u"],capture_output=True,text=True).stdout.split()
served=set(src)
per={}
for f in files:
    m=re.search(r'cmd_([0-9a-f]{4})',f); cid='0x'+m.group(1) if m else f
    txt=open(f,encoding='utf-8',errors='replace').read()
    n=na=ne=0
    for p in re.split(r'\n(?=\s*- id: )',txt)[1:]:
        mm=re.match(r'\s*- id: (\S+)',p)
        if not mm: continue
        n+=1
        if not mm.group(1).startswith(('unknown','unk_','reserved','pad')): na+=1
        elif NEG.search(p): ne+=1
    per[f]=(cid,n,na,ne)
def bucket(v):
    cid,n,na,ne=v
    if n==0: return 'empty payload'
    if na==n: return 'fully named'
    if na+ne==n: return 'named or explained'
    return 'has bare unknowns'
b=collections.Counter(bucket(v) for v in per.values())
print("=== COMMANDS (317 schema files) ===")
for k in ['fully named','named or explained','has bare unknowns','empty payload']:
    print(f"  {k:22s} {b[k]:4d}")
print()
print("=== of the commands we SERVE ===")
bs=collections.Counter()
srvfiles=[(f,v) for f,v in per.items() if v[0] in served]
for f,v in srvfiles: bs[bucket(v)]+=1
print("  served ids with a schema:",len(srvfiles))
for k in ['fully named','named or explained','has bare unknowns','empty payload']:
    print(f"  {k:22s} {bs[k]:4d}")
print()
print("=== served commands still carrying BARE unknowns ===")
rows=sorted([(v[1]-v[2]-v[3],v[0],f.split('/')[-1]) for f,v in srvfiles if bucket(v)=='has bare unknowns'],reverse=True)
for c,cid,f in rows: print(f"  {c:4d} bare   {cid}  {f}")
print("  total bare unknowns in served commands:",sum(r[0] for r in rows))
