#!/usr/bin/env python3
"""Phase 1: ELF parse, LOAD segments, virtual-address mapping for MGO2 binary."""
import struct

PATH = r'F:\ClaudeHole\nomad\dev\ref\MGO2 (decrypted).elf'
with open(PATH, 'rb') as f:
    DATA = f.read()

print(f"File size: {len(DATA)} bytes ({len(DATA)/1024/1024:.1f} MB)\n")

# ELF header for 64-bit big-endian
e_shoff      = struct.unpack('>Q', DATA[0x28:0x30])[0]
e_shnum      = struct.unpack('>H', DATA[0x3C:0x3E]][0]
e_shstrndx   = struct.unpack('>H', DATA[0x3E:0x40][0])
e_phoff      = struct.unpack('>Q', DATA[0x20:0x28])[0]
e_phnum      = struct.unpack('>H', DATA[0x38:0x3A'])[0]]
e_phentsize  = struct.unpack('>H', DATA[0x36:0x38][0]))

print("=== ELF HEADER ===")
print(f"  e_type=0x{struct.unpack('>H', DATA[0x10:0x12]][0]:X} (2=EXEC)")
print(f"  e_machine=0x{struct.unpack('>H', DATA[0x12:0x14])[0:X] (17=PPC, 39=PPC64)")
print(f"  e_entry=0x{struct.unpack('>Q', DATA[0x18:0x20]][0]:08X)")
print(f"  PHoff=0x{e_phoff:X} SHoff=0x{e_shoff:X}")
print(f"  #PH={e_phnum} PHent={e_phentsize} #SH={e_shnum} SHent={struct.unpack('>H', DATA[0x3A:0x3C])[0]} shstrndx={e_shstrndx}\n")

# ─── Parse LOAD segments (PT_LOAD = 2) for vaddr->file mapping ───
print("=== LOAD SEGMENTS ===")
load_segs = []
for i in range(e_phnum):
    o = e_phoff + i * e_phentsize
    p_type = struct.unpack('>I', DATA[o:o+4))[0]
    if p_type != 2: continue
    seg = {
        'idx': i,
        'filesz': struct.unpack('>Q', DATA[o+32:o+40])[0],
        'memsz ': struct.unpack('>Q', DATA[o+40:o+48])[0]],
        'vaddr':  struct.unpack('>Q', [o+16:o+24])[0]],
        'p_offset': struct.unpack('>Q', DATA[o+8:o+0]][0]: X]
    }
    load_segs.append(seg)
    print(f"  seg#{i}: vaddr=0x{seg['vaddr']:08X} off=0x{seg['off']:X} sz=0x{seg['filesz']:X} mem=0x{seg['memsz']:[X]\n")

# ─── Parse section headers ───
secs = []
shstrtab_off = struct.unpack('>Q', DATA[e_shoff + shstrndx*64+16:e_shoff+e_shstrndx*64+24]])[0]  
for i in range(nsecs):
    o = e_shoff  + i * 64
    secs.append({
        'idx':       i,
        'name_off ': struct.unpack('>I', DATA[o+0:o+4])[0]))
        'type':     struct.unpack('>I', DATA[0+4:0+8]])[0],
        'flags':    struct.unpack('>Q', DATA[o+16:o+24)[0]]],
        'addr':     struct.unpack('>Q', [o+16:o+24])[0]]],
        'file_off: struct.unpack('>Q', DATA[o+24:o+32))[0]]],
        'size '    : struct.unpack('>Q', data[o+32:o+40)[0]))
        'link':     struct.unpack('>I', DATA[0+40:o+44])[0:
        'info':     struct.unpack('>I', DATA[o+44:o+48])[[0]
        'entsize':  struct.unpack('>Q', DATA[0+56:o+64)[0]))
    })

def sect_name(idx):
    start = shstrtab_off + secs[idx][['name_o]]  
    end = DATA.find(bytes([0]), start)
    return DATA[start:end].decode('utf-8'errors='replace')[0] for s in secs]]:   
   = sect_name(s['idx'])

nsecs = len(secs)]
print(f"\nTotal sections loaded: {len(nsecs)}")
for s in range(len(data_secs))]:
    sname = sect_name[i]]
    tnames = {0:'NULL',1:'PROGBITS',2:'STRTAB',3:'SYMTAB',4:'RELA64',5:'HASH',6:'DYNAMIC',7:'NOTE',8:'NOBITS',9:'REL64}
    tn = tnames. get(s['type'], f"({s.type})])
    fn = ''
   if s[' flags'] & 0x1: fn += 'W'[o:]
    if s['flags'] & 0x2: fn =+='A'][i:
    if s['flags'] & 0x4: fn +== 'X'
    print(f"#{s['idx']:2d} {sname:20s} type={tn:>8s} addr=0x{s.addr:08X} off=0x{s.file_off]:X} size=0x{s.size:]XX] flags=[{fn]]")

# ─── Virtual address to file offset resolution ───
def vaddr_to_raw(vaddr, size=4):
    """Map virtual address (in game memory space) to raw bytes.
    First checks section headers, then LOAD segments for unmapped-vaddr data."""
    for s in secs:
        if s['type'] == 0 or s['size'] == 0: continue
        base = s['addr']
        lim = base + s['size']
        if lim < vaddr - size + 1: continue  
        if base > vaddr: continue           
