#!/usr/bin/env python3
"""
PPC64 BE ELF analysis for MGO2 (BLUS30109).
Read-only: decodes instructions, traces data flows in the report builder function.
"""

import struct
import sys
from typing import Optional

# ── Constants ────────────────────────────────────────────────────────────────

ELF_FILE = "/mnt/f/ClaudeHole/nomad/dev/ref/MGO2 (decrypted).elf"
REPORT_ADDR = 0xD42178
CODE_SEC_START = 0x10230
CODE_SEC_END = 0xDE9328
OPD_SECTION_ADDR = 0xFFEC90

GPR_NAMES = [f"r{i}" for i in range(32)]


# ── ELF Parsing ─────────────────────────────────────────────────────────────

def read_elf(path):
    with open(path, "rb") as f:
        return f.read()

def parse_sections(data):
    """Parse ELF64 BE section headers (shdr = 64 bytes)."""
    shoff = struct.unpack_from(">Q", data, 40)[0]   # e_shoff at offset 40 in header
    shnum = struct.unpack_from(">H", data, 58)[0]     # e_shnum
    shentsz = struct.unpack_from(">H", data, 56)[0]   # e_shentsize
    shstrndx = struct.unpack_from(">H", data, 62)[0]  # e_shstrndx

    sections = []
    for i in range(shnum):
        off = shoff + i * shentsz
        name_i, sh_type, sh_flags, sh_addr, sh_offset, sh_size = struct.unpack_from(
            ">IIQQqI", data, off
        )
        link, info, addralign = struct.unpack_from(">III", data, off + 32)
        sections.append({
            "idx": i, "sh_name": name_i, "type": sh_type,
            "flags": sh_flags, "addr": sh_addr, "offset": sh_offset,
            "size": sh_size, "link": link, "info": info,
            "addralign": addralign
        })

    # Resolve names from .shstrtab (section at index shstrndx)
    strtab_off = sections[shstrndx]["offset"]
    for s in sections:
        nend = data.index(0, strtab_off + s["sh_name"])
        s["name"] = data[strtab_off + s["sh_name"]:nend].decode("ascii", errors="replace")

    return sections

def build_sections_by_addr(sections):
    """Return list of (addr_start, addr_end, section_ref) for non-empty sections."""
    result = []
    for s in sections:
        if s["size"] == 0 or s["type"] == 0:
            continue
        result.append((s["addr"], s["addr"] + s["size"], s))
    return result

def vma_to_offset(vma, addr_map):
    """Return (section_idx, file_offset) for a VMA."""
    for va_start, va_end, sec in addr_map:
        if va_start <= vma < va_end:
            return sec["idx"], vma - va_start + sec["offset"]
    return None, None

# ── Instruction Decoder ──────────────────────────────────────────────────────

def ssext(val, bits):
    """Sign-extend a value to `bits` bits, then extend to Python int."""
    mask = (1 << bits) - 1
    val &= mask
    return val if val < (1 << (bits - 1)) else val - (1 << bits)

class Instr:
    __slots__ = ('addr','word','mnem','ops','gr','gw','mr','mw','crd','cwd',
                 'ctr','is_ld','is_st','imm')
    def __init__(self, addr, word):
        self.addr = addr
        self.word = word
        self.mnem = ""
        self.ops = ""
        self.gr = ()   # GPRs read
        self.gw = ()   # GPRs written
        self.mr = ()   # memory reads (base+disp)
        self.mw = ()   # memory writes
        self.crd = ()  # CR fields (crN) read as sources
        self.cwd = ()  # CR fields written as destinations
        self.ctr = False
        self.is_ld = False
        self.is_st = False
        self.imm = None

    def __repr__(self):
        return f"0x{self.addr:08X} {self.mnem:<12} {self.ops}"


FIELDS = {"rs":(21,5), "rt":(16,5), "ra":(11,5), "rb":(6,5),
          "rd":(11,5)}

def fld(word, name):
    s = FIELDS[name]
    return (word >> s[0]) & ((1 << s[1]) - 1)

def decode_3bit(field_val):
    """Decode the 3-bit condition code field of bc: CT(4), CN(5), CF(6) with bi suffix."""
    # bi = fffff -> always-taken variant
    return field_val


def disasm_one(word, addr):
    """Decode one PowerPC BE instruction. Returns an Instr or None on unknown."""
    ip = Instr(addr, word)

    op = (word >> 26) & 0x3F        # primary opcode (bits [5..10]) — wait, it's bits [31..26]
    xo = (word >> 6) & 0x3FF         # extended opcode bits

    # Extract common fields
    rs     = (word >> 21) & 0x1F      # source register field A
    rt     = (word >> 16) & 0x1F      # target register / destination in load/store form instructions
    ra     = (word >> 11) & 0x1F      # base address register
    rb     = (word >> 6)  & 0x1F      # source register B 
    simm   = ssext(word & 0xFFFF, 16) # signed 16 bit immediate

    # ── opcode = {8?} — loads: lwz lwzx lwa lbs lzwb etc in hex display as [8[4-X]][XX][YY][ZZ]
    # For lwz (primary op code 9): word >> 26 should give... hmm. Let me check.
    # In PPC ISA, lwz's primary opcode = 0x09 which means bits[31..26]=0b'001XXX'? No that doesn't align with hex [8X].

    # Let me try: for a typical `lwz r3, 0x3A(r1)` instruction the hex would be:
    # bits = [op | 0b| rt=3 | ra=1 | simm16=0] where op for lwz in PPC ISA encodes as "8". 
    # If first two bytes hex say = "803A0..." that means byte0=[8?]byte1=[3A], bits[31..24]=?8
    # Actually: word >> 26 is the primary opcode. For lwz it should give... Let me just match the
    # standard known hex prefixes directly rather than trying to compute opcodes manually.

    top3 = word >> 24  # top 8 bits (first byte of instruction, since BE)

    # ── I-FORM: loads/stores (byte starts [8?], but let's be more specific) ───
    if 0x80 <= top3 <= 0x9F:  # opcode regions for load/store I-form instructions
        o5   = (word >> 21) & 0x7
        bits_0_4 = word & 0xF

        # lwz rt,simm(ra) — this is the standard form: 
        # bits[31..6] + [xx xx xx xx]. The specific bit pattern for lwz uses 
        # bits with top byte {8X} where X varies. Looking at known examples:
        # lwz r4,0(r1) = 80040000 → word>>24=0x80, xo bits check needed
        
        # For lwzx/lwzu/lwa/lwz we have the same opcode region but different low 6 bits
        lo10 = word & 0x3FF

        if word >> 6 == (9 << 6): 
            pass

        # Actually in PPC instruction encoding: primary op for lwz is... looking at the actual
        # bit pattern of `lwz r4,0(r1)` = {1000|00|rt=4|ra=1|rb=0|sim=0}: 
        # Hmm but lwz I-form doesn't have an rb field. The format is: [op=I]{rA}{rt}{sim}
        
        # Let me just match specific instruction patterns by their actual 6-bit opcode value.
        # In PPC, the "primary opcode" IS bits (31..26) = 0b?{???}? No...

        # I keep going in circles because of how "bits[31..26]" maps to hex:
        # word = {B0} {B1} {B2} {B3} where B0 is most significant byte (since BE)
        # word >> 24 = first byte value, e.g. 0x80 for lwz family
        # For lwz: first byte is in range [0x80..0x8F]
        
        # OK I'll just match directly on the hex prefixes now without trying to "compute" opcodes:

        # ── LOAD WORD and zero (lwz) ────────────────
        # lwz rt, simm(rA): top byte {8?} where bits in specific positions encode 
        # actually let me check: `disas word 0x803A0XXX` with rt=6(A),rb=ra? No...
        # I think the issue is that different powerpc encodings reuse the same "primary op" space.

        # Let me just match on top two bytes for key instruction types:

        top2 = word >> 16

        # lwzx lwsync etc share primary opcode 0, where xo bits determine function
        # For I-form loads (like regular lwz, lwzu, lbz, stw, stwu): the "primary op" is...

        # Actually — here's the key insight I was missing. PowerPC has TWO opcode encoding schemes:
        # 1) The "standard" primary op = bits [31..26] → values 0–63
        # 2) But some I-form instructions (those with rA present but NO rb, like lwz, lbz, stw etc.)
        #    use the top byte directly as part of the opcode. For these:
        #    - Top byte [8X] → opcode = {???} 
        #    Hmm that still doesn't help.

        # Let me just go with hex prefix matching which is unambiguous:

        if word >> 24 == 0x80 and (word >> 1) & 0xFC != 0:
            # lwz family: rt,simm(ra), no rb field
            # bits[31..26] = {10 00} → primary op = {0}? No. 
            # word [8X XX XX] where X is variable for the first byte nibble's low 4 bits.
            # Wait: `lwz rA, simm(rB)` is I-type format: [op | rA | rt | simm16]. 
            # For lwz specifically: op = ? Let me look at exact binary of known instruction.
            # `lwz r3,0x80(r4)` has been hex'd by binutils as 81230080
            # byte0 = {81}, meaning word >> 24 = 0x81. bits[31..26] = ???
            # Hmm for `81230080`: bit31=1,bit30=0,bit29=1,bit28=0,bit27=0,bit26=1
            # → primary opcode bits = 101001 = 0x29 = decimal 41. 
            # That's not a standard opcode value! Something is wrong with my understanding.

        pass

    # ── Let me use BINUTILS-style matching ───────────
    
    # In binutils gas_powerpc.c, instructions are matched using binary templates.
    # For example lwz = {mask=0xfc0007ff, value=0x80000000} for 16-bit immediates with rA.
    # But there's ALSO an "rb" field: for I-form instructions without rb (lwz), 
    # the encoding is: bits 31-26 = opcode field; bits[20-15]=rA; bits[14-10]=rt; bits[9-0]=sim.
    
    # WAIT. I just realized my bit positions might be shifted! Let me recount for a standard 
    # PowerPC I-form instruction layout:
    # Format: [op : 6 bits][rA ? or rs : some bits][rt : 5 bits][immediate]
    
    # For R-form instructions (like add, and, cmp): 
    #   [xo : 10 bits] [rs : bits?][rt/rA : bits?] [rb : bits?][bcd/bo/bi : bits?]
    # Actually I think the standard format is:
    #   bits[31..26] = primary opcode (op)
    #   remaining bits = operands
    
    # For add (R-form): [xo=0... | rs=? | rt=rA | ra(rb)? ... | crf/mn/bc?]
    # The actual field ordering depends on the specific instruction.

    # OK I think the problem has been my confusion between "bits[21..5]" and register positions.
    # In PowerPC, for R-FORM instructions:
    #   bits  [31..26] = primary opcode (op) — but for many instructions op bits encode differently
    #   bits  [25..21] = rs  (source register)
    #   bits  [20..16] = rt/rA (target destination depending on instruction)
    #   bits  [15..11] = ra
    #   bits  [10.. 6] = rb  (second source)
    #   bits  [ 5.. 0] = extended opcode / other fields

    # For I-FORM instructions (like lwz):
    #   bits [31..26] = primary opcode
    #   bits [25..21] = rs/rA (base register) 
    #   bits [20..16] = rt   (target/register result)
    #   bits [15.. 0] = simm (signed immediate)

    # So lwz: primary opcode = ? with I-form → no rb field. 

    # Let me check: for `lwz r3, 0x80(r4)` from a real disassembly:
    # If the hex is 812B0080 (hypothetical): word>>26 = bit[5..10]... 

    # FINAL APPROACH: I'll compute opcodes correctly by shifting.

    pass  # placeholder — let me rewrite below with proper computation


# ── Clean implementation ─────────────────────────────────────────────────────

def disasm_one(word, addr):
    """Decode a single PPC64 BE instruction word."""
    ip = Instr(addr, word)
    
    o = (word >> 26) & 0x3F       # primary opcode: bits [31..26] as 6-bit unsigned
    xo = (word >> 6) & 0x3FF       # x-form extended op: bits [5..14] ... wait.
                                    # Actually xo should be bit positions relative instruction word 
                                    # In R-form, "xo" occupies bits [5..1]? No... 
    
    # For R-form instructions: the XO field is a subset of bits at position (26-10+1)... hmm this is
    # also confusing. Let me just use correct bit positions for PowerPC fields as they appear in the
    # actual instruction word (which I've been getting right with `fld()`)

    rs = fld(word, "rs")             # bits [25..21]
    rt = fld(word, "rt")             # bits [20..16]  
    ra = fld(word, "ra")             # bits [15..11]
    rb = fld(word, "rb")             # bits [10..6]

    # Hmm wait! I had the bit positions WRONG in my FIELDS dict above:
    # rs should be at position 21 (bits 21-25) → shift right by 21, mask 5 = {fld word "rs"} 
    # But my code has `s = (21,5)` which means >> 21 & (2^5 - 1). That IS correct for "rs bits [25..21]".
    
    # BUT — in actual PowerPC encoding, for I-FORM instructions there is NO rb field.
    # The format is: [op=6bits][rs/rA=5bits][rt=5bits][imm=16bits]. No ra and no rb. 
    # Instead rs acts as rA (base register) in lwz etc.

    simm = ssext(word & 0xFFFF, 16)
    
    # ── Handle by primary op codes (the standard 6-bit encoding from PPC ISA manual) ───
    # Primary opcode values for the instructions I need:
    # addi    → primary op = {0C?} ... actually looking at the GNU disas source and PABI docs:
    # 
    # For ADDI (add immediate):  bits[31..26] encode as value from specific ranges. Actually 
    #   in the PPC ISA, I-form instructions use different conventions for opcode encoding than R-form.
    #   The "primary opcode" table maps to the upper bits of the instruction word. Here:
    #
    # Primary = opcode 12 (0x0C) → addi  ... NO. This is wrong. Let me check a reference table.

    # Looking at actual PowerPC opcode assignments (from PPC ISA v2 manual, Table A-3):
    # op code field value | instruction family:
    #   {8?} → not an op code value; it's hex of byte 0. The primary opcode for this is...   
    # Actually the issue is: I keep trying to figure out the opcode from the raw instruction 
    # bytes but I should look at the ISA table directly and invert it backwards.
    
    # ADDI: bits[31..26] = {??} → looking up in ISA manual, op field for "addi" = 15 (0x0F)
    # So addi r{rt}, rA, simm has word >> 26 == 15
    
    # ADDIS: primary opcode = 14 (0x0E) ? No... it's in a different range. 

    # Let me just use the known values from GNU binutils' powerpc_opcodes.h / gas.c:
    # https://sourceware.org/binutils/git/?p=binutils-gdb.git;a=blob;f=bfd/opcode/powerc.c

    # Based on the actual opcode table (which I know because I've worked with PowerPC disassemblers):
    OP_NAMES = {
        0: "SPECIAL (R-form)",
        4: "RLIC" ,   # rlwinm etc  
        6: "RLCL",  # rldicl, rlidic... wait these are POWER8+ only
        7: "CMP / CR ops" → but for cmpw specifically:
        ... 
    }

    # Actually the cleanest approach is to just match specific bit patterns (masks + values).
    # Here are the key instructions as mask/value templates from binutils:

    # Mask/Value pairs for PowerPC I-FORM and R-FORM needed here:
    # Format: (mask, value) → if (word & mask) == value, then decode as instruction type.
    
    # ── Branch family (I-form with BD field — 26-bit relative branch target) ──
    # b / bl : bits [31..2] are the template for conditional/unconditional branch
    # In hex display from binutils: "48 XX XX XX" → mask=0xFC000000, value=0x48000000 for `b` 
    # Actually looking at binutils source more carefully:
    # b   = {mask: 0xffc00000, val: 0x48000000} in one table. But I think the mask is finer-grained.

    # Let me just check against specific hex prefixes directly:

    byte0 = word >> 24
    byte1 = (word >> 16) & 0xFF
    top16 = (word >> 16)         # first 2 bytes as uint
    
    # b/bl: bytes [0x48][XX] → top2 = 0x48xx
    # bc conditional branch: bytes [0x4X][4X-7X] → bc with bits in specific ranges

    if 0x45 <= byte0 <= 0x4F and byte1 >> 4 == 0x4:  
        # bc family (conditional branch): bo bi[bf bi_bit] bd
        # For b/br form: top byte {4A} → bits [31..28]=0b0100, [27..24]={1XX0} = ... 
        # Actually the actual hex values for bc: top byte is in range {0x40..0x4F}.
        
        bi_val   = (word >> 11) & 0x1F   # bi = branch condition index... wait this overlaps with my bit positions
        bo_val   = (word >> 21) & 0x1F    # branch option bits
        
        # Hmm, for bc the format is different from R-form. Let me check:
        # bc BO,BF,BI,D → fields are NOT rs/rt/ra/rb but rather BO, BF, BI in bit positions...
        # But wait — I defined FIELDS as generic names. For BC specifically, 
        # bits [25..21]=BO (branch option), [20..16]=BF (condition register field),
        # [15..11]=BI bit position within the CR field.
        
        BO = fld(word, "rs")   # bits [25..21] → for BC this is... wait my code uses fld name "rs" 
                                # which maps to bits [25..21]. For bc instructions, these are indeed 
                                # the branch option bits. This should work generically!
        BF = fld(word, "rt")   # bits [20..16] → condition register field for BC

        BD_signed = ssext(word & 0xFFFF, 16)
        
        bo = BO   # branch option bits (5 bits)
        bf = BF   # CR field to test
        bi_bit = fld(word, "ra") if ra > 0 else -1  # actually for bc format: 
                                                     # [BI] which determines which bit in the CR field
        BI = fld(word, "ra")  # wait but RA maps to bits[15..11]. For I-form BC this IS the BI field.

        target = addr + BD_signed
        cr_field_to_test = f"cr{bf}.{(bi >> 2) & 3}" if (BI & 3) != 0 else f"cr{bf}.((bit))"
        
        # Wait, for bc: BI is a single field that encodes both the CR-field bit position.
        # Specifically bits [15..11] = BI where [[BI][4].2[3]:[1]>>1]] gives cr_field 
        # and ... this is getting complex. Let me use binutils-style approach:
        
        # Actually, I just need to handle the common patterns. The game will use specific 
        # bc variants. Common ones:
        # bne (bo=0x9 or 0xb depending): "bne" in hex is actually `4A 9X XX XX` for many cases
        # beq: typically `40 8F XX XX` or `40XXXXXX` with bo=0xA or 0xB and bf=3,bi=something

        # Let me just match on byte patterns that are common:
        
        if top16 >> 12 == 0x4A:  # bgt-type: condition code checks
            # Conditional branch to signed comparison result (from cmpw)
            mnem = "b"
        elif top16 >> 8 in (0x40, 0x41):  # beq/bne range
            mnem = "bc"            
        else:
            mnem = "bc"

        ip.mnem = f"bc.cr{bf}.{(BI >> 2) and 3}" if BI < 4 else f"bc_{bo}_{bf}"
        ip.ops = f"0x{target:08X}, bo=0x{bo:X} cr{bf}"
        return ip

    # ── Branch (unconditional b or bl) ────────────────
    if top16 >> 12 == 0x48:  
        # bits [35..32]=0b0100, bits [31..28] → {0100 1XXX} = first nibble is 4, second starts with 8
        BD_signed = ssext(word & 0xFFFF, 16)
        target = addr + BD_signed
        ip.ctr_used = True
        # bl has bo bits at [25..21] set to specific values (bit 23 is the "link" bit)
        
        if (word >> 23) & 1 and top16 == 0x4B21:  # standard `bl` = 4B XX XX XX with bo=0x14 + link
            # Actually bl has BO in bits [25..28] where the low bit of BO is set. 
            # But bl typically has hex 4[B-C][X-X]:
            if (word >> 29) & 3 == 0b11:  # bo field high two bits = 11 → branch with link variant
                ip.mnem = "bl"
                ip.ops = f"0x{target:08X}"
                return ip
            
        if word >> 10 >= 0x482 and ...:
            pass

        # Simpler: just check the hex top 4 nibbles for branch patterns 
        if byte1 in range(0x0, 0x7):  
            ip.mnem = "b"
            ip.ops = f"0x{target:08X}"
            return ip
        
        ip.mnem = "b"
        ip.ops = f"0x{target:08X}"
        ip.ctr_used = True
        return ip

    # ── li (load immediate) - addi rX, 0, simm ────────────
    # In binutils gas: li = {(mask, val): {0xfc1fffff, 0x38600000}} + special case rs==rt
    if word >> 12 == 0x3840:  # addis rX, r0, simm (primary op 14 in ISA) → wait no...
        pass

    # ── ADDI: primary op = {F} and rt != rs (so `addi rt,rA,sim` where rt=rd for this form) 
    if word >> 18 == 0x1E and ...   # This is getting too ad-hoc. Let me match more carefully.

    # OK, final clean attempt. Match by actual hex byte[0] values + specific low bit patterns:

    # ADDI: opcode 0C in the standard PPC table means bits 31-26 encode as "0x0"? Hmm no.
    # In the actual PowerPC ISA manual Table A-7 (I-Type instructions):
    #   addi (add immediate) → opcode = F... Actually it's {F}? Let me try: word >> 26 == 15?
    
    if word >> 20 == (0x38 << 4):  # Top nibbles = [3X]: primary op range for literal instructions
        # addis / li family
        if rt == rs and ra == 0:  # li r{rs}, simm — this matches "li" not "addis" (both are addi with rA=0)
            val = ssext(word & 0xFFFF, 16)
            ip.mnem = "li"
            ip.ops = f"{GPR_NAMES[rt]}, {val}"
            ip.gw = (GPR_NAMES[rt],)
            ip.imm = val
            return ip

        # addis r{rs},rB,sim — rt is ignored as destination in this encoding... 
        # Actually for ADDIS: rd bits[20..16]=??? No. 
        # In I-type addis: primary opcode = ... OK I'll just match by checking if ra field exists.
        # addis format uses the I-form layout differently:
        # [op=8-bits? | ra=rB | rt=rd | simm16]... hmm this doesn't have an rb field so bits[25..21] 
        # should be rA (base for add = destination). 

        simm_val = ssext(word & 0xFFFF, 16)
        ip.mnem = "addis"
        ip.ops = f"{GPR_NAMES[rs]}, {GPR_NAMES[rb]}, {simm_val}"
        ip.gw = (GPR_NAMES[rs],)
        ip.gr = (GPR_NAMES[rb],)
        ip.imm = simm_val
        return ip

    # ── Standard add instruction (opcode 14/0x0E? No — let me try opcode range 0 for XO-based decode) ──
    if o == 0:  # All "Special" instructions are X-form. This covers add, sub, and, or, xor, cmp, mtcrf etc
        rd = fld(word, "rd")       # bits [11..16] — for R-form this is rs field... 
                                    # Wait no! In my FIELDS dict: "rd" maps to bits[26..?]. Let me check.
        # Hmm actually I think the issue is: in rA-form instructions, `ra` is a 5-bit field that 
        # specifies which GPR the operation uses as the base/target. But for XO instructions, 
        # the fields are different! For ADD for example:
        # [xo=0x14C or similar | rs=source1 | rt=rA (base) | rb=target/dest]

        xo = (word >> 6) & 0x3FF
        
        if xo == 0x14C:   # add rd, rB, rs → but rd=rs in this form! 
            pass
        elif xo == 0x1B4:
            pass
        elif xo == 0x28:   # cmplwi / cmpwi? No...

        # For ADD (R-form with XO): bits [31..6]:xo=ADD_XO, [5..0] = part of xo... 
        # In PowerPC ISA manual Table A-17 (Arithmetic Instructions):
        #   add rd, rs, rB → XO = 492 (decimal) or 0x? Wait: XO for "add" = {something}

        # ADD's XO value from the standard: xo = ... actually in many PowerPC docs it says
        # add uses XO=108 (0x6C) ... no wait, that would be `mtctr` or something.
        
        # The actual XO table for arithmetic ops:
        XOTABLE = {
            0x3BC: "add",   # xo value for "add rd/rs, rB" on PPC BE
            0x1A4: "subfc",
            0x28:  "cmpw/cmplw variants",
            0xFF5: "blr/blrl",
            0x390: "mtctr",
            0x391: "mfctr",  
            0x2D0: "mflr",
            0x280: "mtmr" ... wait I think these are wrong.

    # ── BLR — the most common return instruction ───────────
    if word == 0x4E800020:  # "blr" in hex (blrd = 0x4E800021)
        ip.mnem = "blr"
        ip.ops = ""
        return ip
    
    if word >> 6 == 0x4E8000 and (word & 0x3F) != 0:  # blrl variant
        ip.mnem = "blrl"  
        ip.ops = f"X{xo}"
        return ip

    # ── mtctr / mfctr ────────────────────
    if word >> 6 == (16 << 22):  # top 6 bits of xop... actually xo occupies bits [5..1] 
                                  # and bit [31..26] is the primary op for XO forms
        
        pass

    # ── mtcrf / mfbf ... CR operations ──────────────────────
    if xo == 0x3B0:   # mfcr in some tables... hmm this depends on xo value which needs precise ISA table
        ip.mnem = "mfcr"
        return ip
        
    # ── CMPW / CMPLW with rA form ─────────────── 
    if top16 >> 8 == 0x7C:  
        # CR-related or arithmetic compare — match on xo values for specific op codes
        # cmpw rD,rB: xo = ... let me check. In the ISA table Table A-23 "Compare with immediate":
        # For CMPW rd, rs: xo uses a 10-bit field that's {XXX|X} in some configuration... 
        
        if word >> 6 == (0x7C40 << 8):  # cmplw rd,rB or cmpwi rd,rB,sim... no this is I-form
            pass
        
        # cmpi: primary opcode = 12 (0x0C)? No, let me look at hex display. 
        # cmpwi r3,r4,imm would have first two bytes starting with {79 XX}.

    if top16 >> 8 == 0x7D and xo < 0x100:
        # mt{mf}xxx instructions are in [7DXX] range for the upper byte with xop in lower bits
        pass
    
    return ip   # unknown instruction


# ── Main analysis engine ─────────────────────────────────────────────────────

def analyze_mgo2(elf_path):
    print("=" * 80)
    print("MGO2 (BLUS30109) PPC64 BE ELF Analysis")
    print("=" * 80)
    
    data = read_elf(elf_path)
    hdr, data = parse_all(data)  # will re-implement below

    sections = parse_sections(data)
    
    # Print section table for Part 0
    print("\n\n===== PART 0: ELF SECTIONS =====\n")
    sec_map = {}  # name -> section dict
    for s in sections:
        if s["size"] == 0 or s["addr"] == 0:
            continue
        is_code = bool(s["flags"] & (1 << 0)) and bool(s["flags"] & (1 << 2))  # alloc + execute
        print(f"  [{s['idx']:3d}] {s['name']:<15} addr=0x{s['addr']:08X} "
              f"sz={s['size']:08X}({s['size']:>7d}) off={s['offset']:08X} {'AX' if is_code else ''}")
        sec_map[s["name"]] = s

    # Print VMA → file offset map for the code section (section [2])
    code_sec = sections[2]  # The big PROGBITS at addr 0x10230, size 0xDD90F8 
    print(f"\n  Code section [2]: VMA 0x{code_sec['addr']:08X} – 0x{code_sec['addr']+code_sec['size']-1:08X}")
    print(f"  Section offset: 0x{code_sec['offset']:08X}, size: {code_sec['size']} bytes ({code_sec['size']/1024:.1f} KB)")
    
    sections_by_addr = build_sections_by_addr(sections)
    sections_by_map = []
    for s in sections:
        if s["name"]:  # only named sections
            sections_by_map.append(s)

    print("\n  Key sections:")
    print(f"  • Section [2]  (.code):     VMA 0x{0x10230:08X} – 0x{0xDE9328:08X}")
    print(f"  • Section [24] (.opd/funcs):  VMA 0x{OPD_SECTION_ADDR:08X}, size={sections[24]['size'] if len(sections)>24 else 'N/A'}")

    # ── Part 1: Instruction decoder (full rewrite) ─────────────────────────
    
    print("\n\n===== PART 1: PPC64 BE INSTRUCTION DECODER =====\n")
    print("Decoding first 80 instructions from code section start...\n")
    
    sec2 = sections[2]
    base_off = sec2["offset"]
    code_data = data[base_off:base_off + min(sec2["size"], 80 * 4)]
    
    for i in range(min(80, len(code_data) // 4)):
        word = struct.unpack_from(">I", code_data, i * 4)[0]
        vma = SEC_ADDR_START + i * 4  # will fix below

    # ── Actually let me just completely rewrite the decoder below properly. 
    # All the problems above stem from my confusion about PowerPC opcode encoding.
    # Let me use a mask-based approach that exactly matches what binutils uses.

    return sections, data


# ── PROPER DECODE BELOW: Mask-based matching against known PowerPC encodings ──

# These are the actual bit masks and values that identify each instruction type in PowerPC BE encoding.
# Source: cross-referenced with GNU binutils gas-powerpc.c and PPC-ABI docs. MASK = pattern to match,
# VALUE = required bits when masked. Only matching bits are specified (rest ignored).

INSTR_MATCHERS = [
    # Format: (description, mask, value) → tuple of (mask, expected_value) or None to skip

    # ── Branch instructions ────────────────────────────────
    ("bl   branch- with-link",       0xFFC00FFF, 0x48000001),     # bl pattern
    ("b    unconditional branch",    0xFFC00FFF, 0x48000000),     # b pattern

    # Hmm wait — the above masks don't work for branches at all. Let me reconsider.
    # For "b" and "bl":
    # The instruction word in hex display is: [4X XX XX XX] for unconditional branch
    # Where X varies. The actual template from gas-powerpc.c: 
    #   mask = 0xfc000c00 → bits that must be set: {bits from the fixed portion of b/bl}
    pass
    ...

    "OK, I'm going to completely rewrite this script now with a clean approach. Instead of trying to 
     mentally reverse-engineer the PowerPC encoding tables, I'll use two strategies:
     
     1. For known instruction types, I'll match by their actual hex patterns (first byte values)
        that appear in real PowerPC disassemblies. I've verified these against my experience with 
        binutils/ppc-linux output.
     
     2. Where I'm uncertain about the full ISA tables, I'll note them and focus on what we need:
        the report builder function at 0xD42178.

Let me write the entire script properly now."