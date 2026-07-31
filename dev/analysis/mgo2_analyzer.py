#!/usr/bin/env python3
"""
MGO2 binary static analyzer — PPC64 big-endian (PS3).
Phase-by-phase pipeline: ELF parse -> section mapping -> targeted disassembly -> 
data-flow tracing -> string/symbol mining.

Address space: we map virtual addresses (given as offsets from base 0x1000 in MGO2) to file offsets.
"""
import struct, sys, io, os
from collections import defaultdict

PATH = r'F:\ClaudeHole\nomad\dev\ref\MGO2 (decrypted).elf'

# ─── ELF load helpers ──────────────────────────────────────────────────
def read_be_u64(data, off):
    return struct.unpack('>Q', data[off:off+8])[0]
def read_be_i32(data, off):
    return struct.unpack('>i', data[off:off+4])[0]
def read_be_u32(data, off):
    return struct.unpack('>I', data[off:off+4])[0]
def read_be_u16(data, off):
    return struct.unpack('>H', data[off:off+2])[0]

with open(PATH, 'rb') as f:
    DATA = f.read()

# ELF header fields (PPC64 BE)
SHDR_SZ = 64
e_shoff = read_be_u64(DATA, 0x28)
e_phoff = read_be_u64(DATA, 0x20)
e_shnum = read_be_u16(DATA, 0x3C)
e_shstrndx = read_be_u16(DATA, 0x3E)

# Read all section headers
raw_secs = []
for i in range(e_shnum):
    off = e_shoff + i * SHDR_SZ
    sec = dict(
        sh_name      = read_be_u32(DATA, off+0),
        sh_type      = read_be_u32(DATA, off+4),
        sh_flags     = read_be_u64(DATA, off+8),
        sh_addr      = read_be_u64(DATA, off+16),
        sh_offset    = read_be_u64(DATA, off+24),
        sh_size      = read_be_u64(DATA, off+32),
        sh_link      = read_be_u32(DATA, off+40),
        sh_info      = read_be_u32(DATA, off+44),
        sh_addralign = read_be_u64(DATA, off+48),
        sh_entsize   = read_be_u64(DATA, off+56),
    )
    raw_secs.append(sec)

# Section name table (STRTAB)
shstrtab_sec = raw_secs[e_shstrndx]
def sect_name(idx):
    start = shstrtab_sec['sh_offset'] + raw_secs[idx]['sh_name']
    end = DATA.find(b'\x00', start)
    return DATA[start:end].decode('ascii', errors='replace')

# Map: vaddr -> file_off -> data slice for each PROGBITS / NOBITS / REL64 section
VADDR_TO_SECT = {}  # (start_vaddr, size) -> (sec_idx, sec_offset_in_section)
SECTIONS_BY_ADDR = defaultdict(list)

for i, s in enumerate(raw_secs):
    if s['sh_type'] == 0:  # NULL
        continue
    SECTIONS_BY_ADDR[(s['sh_addr'], s['sh_size'])].append(i)

def vaddr_to_file(vaddr, n_bytes=1):
    """Map a virtual address to (file_offset_in_section, section_index).
    Returns (off_in_sec_data, sec_idx) or None."""
    for i, s in enumerate(raw_secs):
        if s['sh_type'] == 0:
            continue
        base = s['sh_addr']
        lim = base + s['sh_size'] - n_bytes + 1  
        # generous boundary check
        if base <= vaddr < base + s['sh_size']:
            return (vaddr - base + s['sh_offset'], i)
    return None

def get_vdata(vaddr, size=4):
    """Get bytes at virtual address. Returns raw bytes or None."""
    rc = vaddr_to_file(vaddr, size)
    if rc is None:
        return None
    fo, si = rc
    return DATA[fo:fo+size]

def get_vdata_int64(vaddr):
    """Read up to 1024 bytes from vaddr (for string scanning)."""
    rc = vaddr_to_file(vaddr, 1)
    if rc is None:
        return b''
    fo, si = rc
    end_data = DATA.find(b'\x00', fo, min(fo+512, raw_secs[si]['sh_offset']+raw_secs[si]['sh_size']))
    if end_data == -1:
        end_data = min(fo+512, raw_secs[si]['sh_offset']+raw_secs[si]['sh_size'])
    return DATA[fo:end_data]

print("=== SECTIONS ===", file=sys.stderr)
for i, s in enumerate(raw_secs):
    name = sect_name(i)
    tnames = {0:'NULL',1:'PROGBITS',2:'STRTAB',3:'SYMTAB',4:'RELA64',5:'HASH',
              6:'DYNAMIC',7:'NOTE',8:'NOBITS',9:'REL64',10:'GNU_STACK',
              11:'RELCOMPAT',14:'PREINIT_ARRAY',15:'PREINITARR64',
              16:'FINIT_ARRAY',17:'FINITAR64',18:'DYNAMIC' }
    tn = tnames.get(s['sh_type'], f"({s['sh_type']})")
    fn = ''
    if s['sh_flags'] & 0x1: fn += 'W'
    if s['sh_flags'] & 0x2: fn += 'A'  
    if s['sh_flags'] & 0x4: fn += 'X'
    print(f"#{i:2d} {name:20s} type={tn:10s} addr=0x{s['sh_addr']:08X} " 
          f"off=0x{s['sh_offset']:06X} sz=0x{s['sh_size']:X} flg={fn}")

# Identify key sections
TEXT_SECS = [i for i,s in enumerate(raw_secs) if s['sh_type']==1 and (s['sh_flags']&0x4)]
DATA_SECS = [i for i,s in enumerate(raw_secs) if s['sh_type']==1 and not (s['sh_flags']&0x4)]
BSS_SECS  = [i for i,s in enumerate(raw_secs) if s['sh_type']==8]
RODATA_SECS = [i for i,s in enumerate(raw_secs) if s['sh_type']==1 and (s['sh_addr'],s['sh_size']) not 
               in [(raw_secs[i2]['sh_addr'],raw_secs[i2]['sh_size']) for i2 in TEXT_SECS]]

print(f"\n=== TARGET ADDRESSES ===", file=sys.stderr)
TARGETS = {
    'report_builder': 0xD42178,   # statB present path (traced 2026-07-24) 
    'opd_table':      0xFFEC90,   # function descriptor table
}
for name, va in TARGETS.items():
    rc = vaddr_to_file(va, 1)
    if rc:
        fo, si = rc
        print(f"{name}: vaddr=0x{va:08X} -> file_off=0x{fo:X}, section={sect_name(si)}")
    else:
        print(f"{name}: vaddr=0x{va:08X} -> NOT IN ANY SECTION (scan all)")

# ─── PPC64 instruction disassembly helpers ──────────────────────────────
# PowerPC64 BE encoding (doubleword = 8 bytes, instruction = 4 bytes)
# For MGO2 we need standard PPC32/PPC64 instructions. The binary is a PS3 binary, 
# so it likely uses the 32-bit PPC mode with relative branches (PowerPC ABI).

def ppc_disassemble(data_bytes):
    """Disassemble PPC32BE instructions from bytes and yield (offset, encoding, mnemonic, opcds)."""
    results = []
    i = 0
    N = len(data_bytes) - 3
    while i <= N:
        if i + 4 > len(data_bytes):
            break
        enc = struct.unpack('>I', data_bytes[i:i+4])[0]
        
        # Extract fields
        op = (enc >> 26) & 0x3F       # primary opcode
        xop = enc & 0x3FF              # extended opcode (for op=19/0x13 etc)
        
        mnemonic, isbranch = disasm_one(op, xop, enc)
        results.append((i, enc, mnemonic))
        i += 4
    return results

def disasm_one(op, xop_raw, enc):
    """Return (mnemonic_str, is_branch_bool) for a single PPC instruction."""
    if op == 0:                        # NOP / special
        if (enc >> 16) & 0x7FF == 0:
            return ('nop', False) if (enc & 0xFFFF) == 0 else ('clrif', False)  
        return ('special', False)
    if op == 19:                       # BC, BCL, BLRL, BLR, B, BL
        bi = (enc >> 21) & 0x1F
        bt = (enc >> 16) & 1
        bg = (enc >> 15) & 1
        aa = (enc >> 14) & 1
        lk = (enc >> 13) & 1
        field_a = enc >> 26   # this is wrong, let me redo
        pass
    op_val = op
    
    if op == 0 or op + 3 != 3:         # handle special vs regular
        pass
    
    return disasm_instrumented(op, xop_raw, enc)

def disasm_instrumented(op, xop_raw, enc):
    """Standard PPC32 instruction decoding based on primary opcode."""
    if op == 0:
        ra = (enc >> 16) & 0x1F
        rb = (enc >> 11) & 0x1F  
        # special instructions  
        if ra == 0 and rb == 0 and enc == 0:
            return ('nop', False)
        
        rt = (enc >> 21) & 0x1F  
        # This is a special function decode using the full encoding
        sf = enc & 0x3FF
        if   sf == 256: return ('clr', False)  
        
        return (f'special_{sf:#x}', False)
    
    # Branch instructions
    if op in (18, 19):  # B, BC
        offset = enc & 0xFFFF
        # sign-extend to 16 bits, then multiply by 4
        if offset & 0x8000:
            offset -= 0x10000    # sign extend
        # The branch target would be PC + offset*4 (or offset*1 depending on B/BC) 
        mnemonic = 'B' if op == 18 else 'BC'
        lk = (enc >> 13) & 1
        if lk: mnemonic += '.L'
        mnemonic += f'+{offset*4:#x}'   # show displacement
        return (mnemonic, True)
    
    if op == 20:      # BL (branch & link) 
        offset = enc & 0xFFFFF
        if offset & 0x80000:
            offset -= 0x100000  
        mnemonic = f'BL+{offset*4:#x}'   # or raw addr for long-bl
        return (mnemonic, op > 16)  # all branches include returns
    
    if op == 21:      # BCCTR with LK
        offset = enc & 0xFFFFF  
        if offset & 0x80000:
            offset -= 0x100000
        return (f'BCCTR.L+{offset*4:#x}', True)
    
    # Load/Store instructions (these are what we care about for data flow)  
    if op == 32 or op == 59:   # LWZ/STW variants
        pass
    
    # Generic decode by opcode category 
    mnemonic = f'OP{op}'
    
    if op in (7,8,9): 
        # ADDI / LI
        mnemonic = ('ADDIS', 'LI', 'ADDI')[op-7] + '_IMM'  
    elif op == 14:     
        mnemonic = 'FCMP'
    elif op in (15, 23, 26):
        # FMTU, FMU
        mnemonic = ('FMTO', 'FMLA', 'FSEL')[op - 15] if op-15 < 3 else '?FM?'
    elif op == 27:      # CMP/CMPW
        mnemonic = 'CMP'
    elif op == 31:      # MATH/ALU (dual opcode)  
        return decode_op31_xop(enc, xop_raw)
    elif op in range(32, 40):   # LWZ, SWI, LBZ, LHZ ... / STW, STLWAR, STF...
        mnemonic = [('LWZ','LWZU','LDARX','LDWX','LWZX')[op-32][1] if op-32 < 5 else 'LOADx'][0]  
    elif op in range(46,54):     # STW, STD... / STLWAR
        mnemonic = [('STW',)[0]] 
    
    return (f'OP{op}', False)


# Actually let me restart this properly. I'll use proper instruction decoding tables.
