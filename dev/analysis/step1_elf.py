#!/usr/bin/env python3
"""Comprehensive PPC64BE ELF analysis for MGO2 report-builder (0xD42178) tracing."""
import struct, sys, io
from collections import defaultdict

Path = r'F:\ClaudeHole\nomad\dev\ref\MGO2 (decrypted).elf'
print("=== Step 1: Parse ELF ===", file=sys.stderr)

with open(Path, 'rb') as f:
    raw = f.read()
    
with open(Path, 'rb') as f:
    # ELF header
    e_ident = f.read(16)
    assert e_ident[:4] == b'\x7fELF' and e_ident[5] == 2, "Must be 64-bit BE ELF"
    
    def read_u32(): 
        pos = f.tell()
        return struct.unpack('>I', raw[pos:pos+4])[0]
    def read_u64(): 
        pos = f.tell()
        return struct.unpack('>Q', raw[pos:pos+8])[0]
    
    e_type = struct.unpack('>H', raw[0x10:0x12])[0]
    e_machine = struct.unpack('>H', raw[0x12:0x14])[0]
    e_entry = struct.unpack('>Q', raw[0x18:0x20])[0]
    e_phoff = struct.unpack('>Q', raw[0x20:0x28])[0]
    e_shoff = struct.unpack('>Q', raw[0x28:0x30])[0]
    e_flags = struct.unpack('>I', raw[0x30:0x34])[0]
    e_ehsize = struct.unpack('>H', raw[0x34:0x36])[0]
    e_phentsize = struct.unpack('>H', raw[0x36:0x38])[0]
    e_phnum = struct.unpack('>H', raw[0x38:0x3A])[0]
    e_shentsize = struct.unpack('>H', raw[0x3A:0x3C])[0]
    e_shnum = struct.unpack('>H', raw[0x3C:0x3E])[0]
    e_shstrndx = struct.unpack('>H', raw[0x3E:0x40])[0]

print(f"e_machine=0xe_e_machine=e_machine}") 
# PPC64 = 0x15 (39) in official, but PS3 Cell BE uses different values
# Actually: 0x15 is PowerPC. Let's just note it and proceed.

# Read shstrtab first
print(f"\n=== Section Headers ===", file=sys.stderr)
shstrtab_off = read_u64() if False else struct.unpack('>Q', raw[e_shoff + e_shstrndx * e_shentsize + 0x18:e_shoff + e_shstrndx * e_shentsize + 0x20])[0]

sections = []
for i in range(e_shnum):
    off = e_shoff + i * e_shentsize
    sh_name_off = struct.unpack('>I', raw[off:off+4])[0]  
    sh_type = struct.unpack('>I', raw[off+4:off+8])[0]
    sh_flags = struct.unpack('>Q', raw[off+8:off+16])[0]
    sh_addr = struct.unpack('>Q', raw[off+16:off+24])[0]
    sh_offset = struct.unpack('>Q', raw[off+24:off+32])[0]  
    sh_size = struct.unpack('>Q', raw[off+32:off+40])[0]
    sh_link = struct.unpack('>I', raw[off+40:off+44])[0]
    sh_info = struct.unpack('>I', raw[off+44:off+48])[0]
    sh_addralign = struct.unpack('>Q', raw[off+48:off+56])[0]  
    sh_entsize = struct.unpack('>Q', raw[off+56:off+64])[0]   
    sections.append({
        'idx': i, 'name_off': sh_name_off, 'type': sh_type,
        'flags': sh_flags, 'addr': sh_addr, 'offset': sh_offset,
        'size': sh_size, 'link': sh_link, 'info': sh_info, 
        'entsize': sh_entsize
    })

# Get section names
for i in range(e_shnum): 
    base_off = e_shoff + e_shstrndx * e_shentsize  
    strtab_base = struct.unpack('>Q', raw[base_off+16:base_off+24])[0] 
    name_start = sections[i]['name_off']
    name_end = raw.find(b'\x00', strtab_base + name_start) 
    if name_end == -1:
        name_end = strtab_base + name_start + 32
    sections[i]['name'] = raw[strtab_base + name_start:name_end].decode('ascii', errors='replace')

print(f"Total sections: {e_shnum}")
for s in sections:
    type_names = {0:'NULL',1:'PROGBITS',2:'STRTAB',3:'SYMTAB',4:'RELA64',5:'HASH',6:'DYNAMIC',7:'NOTE',8:'NOBITS',9:'REL64'}
    fn = ''
    fval = s['flags'] 
    if fval & 0x1: fn += 'W'
    if fval & 0x2: fn +='A'  
    if fval & 0x4: fn += 'X'
    print(f"#{s['idx']:2d} {s['name']:20s} type={type_names.get(s['type'], hex(s['type'])):8s} " 
          f"addr=0x{s['addr']+0:08X} data_off=0x{s['offset']+0:X} sz=0x{s['size']:X} flg={fn}")

# Save for next step
with open('step1_output.txt', 'w') as f_out:
    f_out.write("Sections:\n")
    for s in sections:
        type_names = {0:'NULL',1:'PROGBITS',2:'STRTAB'}
        print(f"#{s['idx']:2d} addr=0x{s['addr']:08X} off=0x{s['offset']:X}", file=f_out)

print("\n\nDone with ELF parsing. Found sections:", len(sections), file=sys.stderr)
