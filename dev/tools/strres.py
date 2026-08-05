"""Resolve MGO2 disc string-resource ids to their text, in all six languages.

`scenerio_strres/<n>.bin` (produced by `gcx.exe -res`, see dev/docs/ASSETS.md) is TWO things
concatenated, thirteen times over: each group declared in `scenerio.gcl` owns a range of **index
records**, and its **string pool** is the files between that range and the next group's.

    id = index_file_number - group_index_start

Index record, little-endian:

    06 <u24 group_tag> <tag> <u24 name_hash> [flag] <6 varints> 00
      tag 0x06 -> no flag byte; tag 0x0d -> one 0x01 flag byte follows
      varint: b >= 0xC1 -> b - 0xC1 | b == 0x02 -> next byte | b == 0x01 -> next 2 bytes LE
      value 0 = "no string", else pool_file = (pool_start - 1) + value

The six values are JP, EN, FR, DE, IT, ES; two languages sharing text share a pool file, which is
why COUNTING records drifts and reading them does not.

`name_hash` is the same rot-5-add 24-bit hash the ELF uses (0xD25D0), so a resource name in the
binary resolves straight to its record without knowing its id -- see `find_hash`.

NOTE the two different group identifiers. The `[hash]` in scenerio.gcl names the SET; the record's
own `group_tag` is what the ELF passes as the resolver's first argument. They are not equal:
gcl `[2f0293]` records carry tag 0x00F914BF (the constant at 0x8E0C24, the lobby/Create Game text)
and gcl `[e60831]` records carry tag 0x6B01B5 (the mailbox text). Match on the tag when starting
from the binary, and on the gcl hash when starting from the script.

    python3 dev/tools/strres.py 10337            # by index file
    python3 dev/tools/strres.py --id 2f0293 548  # by group tag + id
    python3 dev/tools/strres.py --name CLAN_SUBJECT

Point MGO2_STRRES at the dump if it is not in the default location.
"""
import os
import sys

D = os.environ.get("MGO2_STRRES", "/mnt/f/ClaudeHole/mgo2_extract/gcx/scenerio_strres")
GROUPS=[(0x40eff4,0,341),(0x7a133b,1527,3389),(0x2f0293,9789,11033),(0x642318,16524,16738),
 (0xe60831,17779,17942),(0xd97d38,18866,18926),(0x1c4a02,19156,19229),(0xb0e35e,19568,19606),
 (0x4f1c53,19717,19743),(0xd2c5a4,19814,20082),(0x6acf0d,21055,21115),(0x03d915,21368,21898),
 (0xf0d736,24954,25816)]
POOL={}
for k,(g,s,e) in enumerate(GROUPS):
    nxt = GROUPS[k+1][1] if k+1<len(GROUPS) else 28693
    POOL[g]=(e+1,nxt-1)
def raw(i): return open(f"{D}/{i}.bin","rb").read()
def txt(f):
    d=raw(f).rstrip(b'\x00')
    return d.decode('utf-8',errors='replace')
def dec_vals(b,p):
    vals=[]
    while p<len(b):
        t=b[p]
        if t==0x00: p+=1; break
        if t>=0xC1: vals.append(t-0xC1); p+=1
        elif t==0x02: vals.append(b[p+1]); p+=2
        elif t==0x01: vals.append(b[p+1]|(b[p+2]<<8)); p+=3
        else: vals.append(-t); p+=1
    return vals
def parse(i):
    b=raw(i)
    if len(b)<8: return None
    if b[0]!=0x06: return None
    grp=b[1]|(b[2]<<8)|(b[3]<<16)
    tag=b[4]
    if tag not in (0x06,0x0d): return None
    h=b[5]|(b[6]<<8)|(b[7]<<16)
    p=8; flag=0
    if tag==0x0d: flag=b[p]; p+=1
    return dict(grp=grp,tag=tag,hash=h,flag=flag,vals=dec_vals(b,p))
def gof(fi):
    for g,s,e in GROUPS:
        if s<=fi<=e: return g
    return None
def resolve(fi):
    r=parse(fi)
    if not r: return None
    g=gof(fi); base=POOL[g][0]-1
    files=[base+v if v else None for v in r['vals']]
    r['files']=files; r['text']=[txt(f) if f else None for f in files]; r['file']=fi
    return r
def h24(name):
    h=0
    for c in name.encode():
        h=(((h<<5)|(h>>19))+c)&0xFFFFFF
    return h


def id_of(fi):
    """The group-relative string id for an index file, or None if it is not an index file."""
    for g, s_, e in GROUPS:
        if s_ <= fi <= e:
            return fi - s_
    return None


def by_id(group_tag, sid):
    """Resolve by group tag (e.g. 0x2f0293) and group-relative id."""
    for g, s_, e in GROUPS:
        if g == group_tag:
            return resolve(s_ + sid)
    return None


def find_hash(name):
    """Find the index record whose name_hash matches `name`. Returns (index_file, record)."""
    want = h24(name)
    for g, s_, e in GROUPS:
        for fi in range(s_, e + 1):
            r = parse(fi)
            if r and r["hash"] == want:
                return fi, resolve(fi)
    return None, None


def _show(fi, r):
    if not r:
        print(f"{fi}: not an index record")
        return
    sid = id_of(fi)
    print(f"index file {fi}  group 0x{r['grp']:06x}  id {sid}  hash 0x{r['hash']:06x}")
    for lang, t in zip(("JP", "EN", "FR", "DE", "IT", "ES"), r["text"]):
        if t is not None:
            print(f"  {lang}: {t}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print(__doc__)
    elif a[0] == "--name":
        fi, r = find_hash(a[1])
        if fi is None:
            print(f"no index record hashes to {a[1]} (0x{h24(a[1]):06x})")
        else:
            _show(fi, r)
    elif a[0] == "--id":
        tag = int(a[1], 16)
        sid = int(a[2])
        r = by_id(tag, sid)
        _show((r or {}).get("file", -1), r)
    else:
        fi = int(a[0])
        _show(fi, resolve(fi))
