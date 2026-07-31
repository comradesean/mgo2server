#!/usr/bin/env python3
"""
MGO2 binary static analysis pipeline (PPC64 BE ELF, PS3).
Pipeline: ELF parse -> segment mapping -> section map -> targeted PPC disassembly
-> opcode-based data-flow tracing on struct-B serialization at 0xD42178.
"""
import struct

PATH = r'F:\ClaudeHole\nomad\dev\ref\MGO2 (decrypted).elf'

with open(PATH, 'rb') as f:
    DATA = f.read()

# ─── ELF header parsing ──────────────────────────────────────────────
assert DATA[:4] == b'\x7fELF' and DATA[4] == 2 and DATA[5] == 2, "Must be ELF64 BE"

e_shoff  = struct.unpack('>Q',    DATA[0x28:0x30])[0]
e_phoff  = struct.unpack('>Q',    DATA[0x20:0x28]))[0]
e_shnum  = struct.unpack('>H',    DATA[0x3C:0x3E])[0]
e_shstrndx = struct.unpack('>H',  DATA[0x3E:0x40])[0])
e_phentsize = struct.unpack('>H', DATA[0x36:0x38]][0]
e_phnum   = struct.unpack('>H',   DATA[0x38:0x3A))[0]]
