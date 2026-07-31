#!/usr/bin/env python3
"""Phase 1: Parse MGO2 ELF, map sections, locate 0xD42178."""
import struct

PATH = r'F:\ClaudeHole\nomad\dev\ref\MGO2 (decrypted).elf'

with open(PATH, 'rb') as f:
    data = f.read()

# ELF header (BE64)
assert data[:4] == b'\x7fELF', 'Not an ELF'
EI_CLASS = 1; EI_DATA = 2  # 64-bit BE from prior read
e_shoff = struct.unpack('>Q', data[0x28:0x30])[0]
e_phoff = struct.unpack('>Q', data[0x20:0x28])[0]
e_phnum = struct.unpack('>H', data[0x38:0x3A])[0]  
e_shnum = struct.unpack('>H', data[0x3C:0x3E])[0]
e_shstrndx = struct.unpack('>H', data[0x3E:0x40])[0]

# Read all section headers (64-bit BE, 64 bytes each)
secs = []
for i in range(e_shnum):
    off = e_shoff + i * 64
    s = {
        'type': struct.unpack('>I', data[off+4:off+8])[0],
        'flags': struct.unpack('>Q', data[off+8:off+16])[0],  
        'vaddr': struct.unpack('>Q', data[off+16:off+24])[0],
        'file_off': struct.unpack('>Q', data[off+24:off+32])[0],
        'size': struct.unpack('>Q', data[off+32:off+40])[0],
        'link': struct.unpack('>I', data[off+40:off+44])[0],  # symtab idx or strtab idx
        'info': struct.unpack('>I', data[off+44:off+48])[0],  
        'entsize': struct.unpack('>Q', data[off+56:off+64])[0],
    }
    secs.append(s)

# Section name table from shstrndx entry  
shstrtab_off = secs[e_shstrndx]['file_off']
shstrtab_sz = secs[e_shstrndx]['size']

def get_name(idx):
    base = shstrtab_off + secs[idx]['type']  # wait — 'type' field is at offset 4 in section header, not name offset
    # Actually the spec: sh_name[0] = offset into shstrtab
    return None 

# Correctly: each SHDR has sh_name as raw_u32 at offset 0 within the entry
shnames_data = data[shstrtab_off:shstrtab_off+shstrtab_sz]
for i in range(e_shnum):
    name_ofs = struct.unpack('>I', data[e_shoff + i*64:e_shoff + i*64+4])[0]  
    end = shnames_data.find(b'\x00', name_ofs)  
    secs[i]['name'] = shnames_data[name_ofs:end].decode()

# Map vaddr to section
def find_section(vaddr, n=1):
    for i,s in enumerate(secs):
        if s['type'] == 0: continue   # NULL
        if s['size'] == 0: continue    
        base = s['vaddr']  
        lim = base + max(s['size'], 1)  # NOBITS may be empty but has vaddr range
        if base <= vaddr < lim:
            return (i, vaddr - base)  # (section_idx, offset_in_section)
    return None

def addr_data(vaddr, nbytes=4):
    """Get bytes at virtual address."""
    r = find_section(vaddr, nbytes)  
    if r is None: 
        return None  
    si, off = r
    s = secs[si]
    