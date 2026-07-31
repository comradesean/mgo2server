#!/usr/bin/env python3
"""Traces every `result code -> dialogId` path in the retail binary.

`dump_error_table.py` resolves a dialogId into a sentence. It cannot tell you which *result
code* produces that dialogId, because that mapping is not in any table — it is compiled into
per-operation `cmpwi` chains in the dispatcher. Until now those chains were read by hand, which
produced a list that was partial (several "dialogId not recovered"), silent about each block's
default path, and wrong at least once by omission.

This tool replaces the reading. It emits `dev/analysis/dialog_paths.json`, consumed by
`dump_error_table.py`.

## How it works

The chains are *pure functions of the result code*: no loads, no calls, no global state, just
comparisons and register arithmetic ending at `bl 0x885A08`. So instead of symbolic execution —
which chokes on the branchless selects the compiler emitted, e.g. the xor/srawi/subf/srwi
sequence at 0xA7E45C — each chain is simply **run concretely, once per candidate code**. Every
run yields exactly one dialogId, and selects evaluate for free.

Every code in SWEEP is tried against every arm. That is what makes the result a complete
description rather than a transcription: a code-to-dialog edge is found whether it came from an
equality test, a range test (`bgt`/`bge` over a span), or arithmetic. Reading `cmpwi` immediates
by eye finds only the first kind, which is how the -833..-832 range in the mail block was missed.

The interpreter is deliberately partial and **fails loudly**. Anything it does not model — a
load, an indirect branch, an unrecognised opcode — aborts that path as UNMODELED rather than
guessing. An arm that reports UNMODELED paths has not been analysed; it has been declined.

## Regenerating

    python3 dev/tools/trace_dialog_paths.py

No external tools. The system objdump on this box has no PowerPC target, so the instruction
decoder below is built in rather than shelling out.
"""
import json
import pathlib
import struct
from collections import defaultdict

ELF = pathlib.Path(__file__).resolve().parents[1] / "ref" / "MGO2 (decrypted).elf"
OUT = pathlib.Path(__file__).resolve().parents[1] / "analysis" / "dialog_paths.json"

RAISE = 0x885A08        # 0x885A08(dialogId, resultCode, ctx) — raises the dialog

# The other way out of a chain. `lwz r9,100(r31); stw r29,0(r9); b 0xA7DCEC` stores the result
# code for the caller and returns to the state machine without raising anything. A code that
# lands here produces **no message at all** — the screen simply does not respond, which is a
# materially different outcome from a vague one and has to be reported separately.
SILENT = 0xA7E3F0

DISPATCH_TABLE = 0xA7DE74   # 31-arm jump table, indexed by the op ordinal at 104(r31)
DISPATCH_ARMS = 31
CODE_REG = 29           # the dispatcher holds the result code in r29

# Every code the sweep tries. The client's codes are small negatives; the positive tail is
# included so that a chain which special-cases success or a positive status shows it.
SWEEP = list(range(-4096, 257))

STEP_BUDGET = 4000


# --------------------------------------------------------------------------------------------
# ELF
# --------------------------------------------------------------------------------------------

class Image:
    """The loadable segments, addressable by virtual address."""

    def __init__(self, path):
        d = path.read_bytes()
        if d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 2:
            raise SystemExit(f"{path}: not a 64-bit big-endian ELF")
        e_phoff, = struct.unpack_from(">Q", d, 32)
        e_phentsize, e_phnum = struct.unpack_from(">HH", d, 54)
        self.segments = []
        for i in range(e_phnum):
            p = e_phoff + i * e_phentsize
            p_type, = struct.unpack_from(">I", d, p)
            p_offset, p_vaddr = struct.unpack_from(">QQ", d, p + 8)
            p_filesz, = struct.unpack_from(">Q", d, p + 32)
            if p_type == 1 and p_filesz:      # PT_LOAD
                self.segments.append((p_vaddr, p_vaddr + p_filesz, p_offset, d))

    def word(self, va):
        for lo, hi, off, d in self.segments:
            if lo <= va < hi - 3:
                return struct.unpack_from(">I", d, off + (va - lo))[0]
        return None


# --------------------------------------------------------------------------------------------
# Instruction decoding — the subset these chains use, and nothing else
# --------------------------------------------------------------------------------------------

def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def s64(v):
    v &= (1 << 64) - 1
    return v - (1 << 64) if v & (1 << 63) else v


def rot32(v, n):
    v &= 0xFFFFFFFF
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF if n else v


def rot64(v, n):
    v &= (1 << 64) - 1
    return ((v << n) | (v >> (64 - n))) & ((1 << 64) - 1) if n else v


def mask32(mb, me):
    if mb <= me:
        return sum(1 << (31 - i) for i in range(mb, me + 1))
    return sum(1 << (31 - i) for i in list(range(mb, 32)) + list(range(0, me + 1)))


class Unmodeled(Exception):
    """The interpreter met something it does not model. Never guessed around."""


# --------------------------------------------------------------------------------------------
# Concrete interpreter
# --------------------------------------------------------------------------------------------

class Run:
    """One concrete execution of a chain, for one result code."""

    def __init__(self, image, code, code_reg=CODE_REG):
        self.img = image
        self.r = [None] * 32          # None == unknown; using one aborts the run
        self.r[code_reg] = code & ((1 << 64) - 1)
        self.cr = [None] * 8          # per field: (lt, gt, eq)
        self.code = code

    def get(self, i):
        v = self.r[i]
        if v is None:
            raise Unmodeled("read of an unknown register")
        return v

    def setr(self, i, v):
        self.r[i] = None if v is None else v & ((1 << 64) - 1)

    def run(self, entry):
        """Execute from `entry` until the raise site. Returns the dialogId in r3."""
        pc = entry
        for _ in range(STEP_BUDGET):
            if pc == SILENT:
                return None                # swallowed: no dialog is raised on this path
            w = self.img.word(pc)
            if w is None:
                raise Unmodeled(f"no code at {pc:#x}")
            nxt = self.step(pc, w)
            if isinstance(nxt, tuple):     # ("raise", dialogId)
                return nxt[1]
            pc = nxt
        raise Unmodeled("step budget exhausted")

    # -- helpers ------------------------------------------------------------------------------

    def cmp_set(self, bf, a, b):
        self.cr[bf] = (a < b, a > b, a == b)

    def branch_taken(self, bo, bi):
        bo &= 0x1E                      # drop the y hint bit
        if bo & 0x10:
            return True                 # branch always
        if not bo & 0x04:
            raise Unmodeled("CTR-decrementing branch")
        field, bit = bi >> 2, bi & 3
        cond = self.cr[field]
        if cond is None:
            raise Unmodeled("branch on an unset CR field")
        if bit == 3:
            raise Unmodeled("branch on summary overflow")
        return cond[bit] == bool(bo & 0x08)

    # -- the step -----------------------------------------------------------------------------

    def step(self, pc, w):
        op = w >> 26
        rd, ra, rb = (w >> 21) & 31, (w >> 16) & 31, (w >> 11) & 31

        if op == 14:                                            # addi / li
            base = 0 if ra == 0 else self.get(ra)
            self.setr(rd, base + s16(w & 0xFFFF))
            return pc + 4
        if op == 15:                                            # addis / lis
            base = 0 if ra == 0 else self.get(ra)
            self.setr(rd, base + (s16(w & 0xFFFF) << 16))
            return pc + 4
        if op == 8:                                             # subfic
            self.setr(rd, s16(w & 0xFFFF) - s64(self.get(ra)))
            return pc + 4
        if op in (12, 13):                                      # addic / addic.
            self.setr(rd, s64(self.get(ra)) + s16(w & 0xFFFF))
            return pc + 4
        if op == 24:                                            # ori  (rA = rS | UIMM)
            self.setr(ra, self.get(rd) | (w & 0xFFFF))
            return pc + 4
        if op == 26:                                            # xori
            self.setr(ra, self.get(rd) ^ (w & 0xFFFF))
            return pc + 4

        if op == 11:                                            # cmpi / cmpwi / cmpdi
            bf, l = (w >> 23) & 7, (w >> 21) & 1
            v = self.get(ra)
            v = s64(v) if l else s32(v)
            self.cmp_set(bf, v, s16(w & 0xFFFF))
            return pc + 4
        if op == 10:                                            # cmpli / cmplwi / cmpldi
            bf, l = (w >> 23) & 7, (w >> 21) & 1
            v = self.get(ra)
            v = v & ((1 << 64) - 1) if l else v & 0xFFFFFFFF
            self.cmp_set(bf, v, w & 0xFFFF)
            return pc + 4

        if op == 18:                                            # b / ba / bl / bla
            li = w & 0x03FFFFFC
            if li & 0x02000000:
                li -= 0x04000000
            target = li if w & 2 else pc + li
            if w & 1:                                           # bl
                return self.call(pc, target)
            return target
        if op == 16:                                            # bc
            bd = w & 0xFFFC
            if bd & 0x8000:
                bd -= 0x10000
            target = bd if w & 2 else pc + bd
            if w & 1:
                raise Unmodeled("conditional call")
            return target if self.branch_taken((w >> 21) & 31, (w >> 16) & 31) else pc + 4

        if op == 19:
            xo = (w >> 1) & 0x3FF
            if xo == 16:                                        # bclr / blr
                raise Unmodeled("return out of the chain")
            if xo == 528:                                       # bcctr
                raise Unmodeled("indirect branch")
            if xo in (257, 449, 193, 289, 225, 33, 129):        # cr logical ops
                raise Unmodeled("CR logical op")
            raise Unmodeled(f"opcode 19/{xo} at {pc:#x}")

        if op == 31:
            xo = (w >> 1) & 0x3FF
            if xo == 444:                                       # or / mr
                self.setr(ra, self.get(rd) | self.get(rb))
                return pc + 4
            if xo == 316:                                       # xor
                self.setr(ra, self.get(rd) ^ self.get(rb))
                return pc + 4
            if xo == 28:                                        # and
                self.setr(ra, self.get(rd) & self.get(rb))
                return pc + 4
            if xo == 40:                                        # subf  (rD = rB - rA)
                self.setr(rd, s64(self.get(rb)) - s64(self.get(ra)))
                return pc + 4
            if xo == 266:                                       # add
                self.setr(rd, s64(self.get(ra)) + s64(self.get(rb)))
                return pc + 4
            if xo == 104:                                       # neg
                self.setr(rd, -s64(self.get(ra)))
                return pc + 4
            if xo == 986:                                       # extsw
                self.setr(ra, s32(self.get(rd)))
                return pc + 4
            if xo == 922:                                       # extsh
                self.setr(ra, s16(self.get(rd) & 0xFFFF))
                return pc + 4
            if xo == 824:                                       # srawi
                self.setr(ra, s32(self.get(rd)) >> ((w >> 11) & 31))
                return pc + 4
            if xo == 0:                                         # cmp
                bf, l = (w >> 23) & 7, (w >> 21) & 1
                a, b = self.get(ra), self.get(rb)
                self.cmp_set(bf, s64(a) if l else s32(a), s64(b) if l else s32(b))
                return pc + 4
            if xo == 32:                                        # cmpl
                bf, l = (w >> 23) & 7, (w >> 21) & 1
                a, b = self.get(ra), self.get(rb)
                m = ((1 << 64) - 1) if l else 0xFFFFFFFF
                self.cmp_set(bf, a & m, b & m)
                return pc + 4
            if xo == 467:                                       # mtspr — mtctr/mtlr
                return pc + 4
            raise Unmodeled(f"opcode 31/{xo} at {pc:#x}")

        if op == 21:                                            # rlwinm — srwi/slwi/clrlwi
            sh, mb, me = (w >> 11) & 31, (w >> 6) & 31, (w >> 1) & 31
            self.setr(ra, rot32(self.get(rd), sh) & mask32(mb, me))
            return pc + 4
        if op == 30:                                            # rldicl / rldicr / rldic
            form = (w >> 2) & 7
            sh = ((w >> 11) & 31) | (((w >> 1) & 1) << 5)
            n = ((w >> 6) & 31) | (((w >> 5) & 1) << 5)
            v = rot64(self.get(rd), sh)
            if form == 0:                                       # rldicl — clrldi
                self.setr(ra, v & (((1 << (64 - n)) - 1) if n < 64 else 0))
                return pc + 4
            if form == 1:                                       # rldicr
                keep = 64 - n - 1
                self.setr(ra, v & ~((1 << keep) - 1) if keep > 0 else v)
                return pc + 4
            if form == 2:                                       # rldic
                self.setr(ra, v & (((1 << (64 - n)) - 1) if n < 64 else 0))
                return pc + 4
            raise Unmodeled(f"opcode 30/{form} at {pc:#x}")

        if op == 0 and w == 0:
            raise Unmodeled("zero word")
        if w == 0x60000000:                                     # nop
            return pc + 4

        raise Unmodeled(f"opcode {op} at {pc:#x} (word {w:#010x})")

    def call(self, pc, target):
        if target == RAISE:
            d = self.r[3]
            if d is None:
                raise Unmodeled("reached the raise site with an unknown dialogId")
            # r4 is the result code the client will print in the (nnnn:FFFFFFFF) suffix. If our
            # guess at which register holds the code is right, it arrives here equal to what we
            # injected. That equality is what promotes a guessed code register to a verified one.
            self.verified = self.r[4] is not None and s32(self.r[4]) == self.code
            self.raised_at = pc
            return ("raise", s32(d))
        raise Unmodeled(f"call to {target:#x}")


def raise_sites(image):
    """Every `bl 0x885A08` in the loadable image — the complete set of ways a dialog is raised."""
    out = []
    for lo, hi, off, d in image.segments:
        for va in range(lo, hi - 3, 4):
            w = struct.unpack_from(">I", d, off + (va - lo))[0]
            if w >> 26 != 18 or not w & 1 or w & 2:
                continue
            li = w & 0x03FFFFFC
            if li & 0x02000000:
                li -= 0x04000000
            if va + li == RAISE:
                out.append(va)
    return out


# --------------------------------------------------------------------------------------------
# Driving the sweep
# --------------------------------------------------------------------------------------------

def trace(image, entry, code_reg=CODE_REG, codes=SWEEP):
    """Every code, run against one chain entry.

    Returns (mapping, unmodeled, sites, verified) where mapping is code -> dialogId for the
    codes that resolved.
    """
    mapping, unmodeled, sites, verified = {}, {}, set(), 0
    for code in codes:
        r = Run(image, code, code_reg)
        r.raised_at, r.verified = None, False
        try:
            mapping[code] = r.run(entry)
            if r.raised_at:
                sites.add(r.raised_at)
            verified += bool(r.verified)
        except Unmodeled as e:
            unmodeled[code] = str(e)
    return mapping, unmodeled, sites, verified


PROBE = list(range(-1250, -1180)) + list(range(-300, -140)) + [-24, -36, -71, 0]


def code_register(image, entry):
    """Which register holds the result code on entry to this chain.

    Inferred, then checked: a run is only counted when the code we injected reappears in r4 at
    the raise site, which is where the client reads it to print the (nnnn:FFFFFFFF) suffix. A
    wrong guess leaves r4 unknown or constant and scores zero, so this does not silently settle
    on a plausible-looking wrong answer.
    """
    best, best_score = None, 0
    for reg in range(3, 32):
        _, _, _, verified = trace(image, entry, reg, PROBE)
        if verified > best_score:
            best, best_score = reg, verified
    return best, best_score


def spans(mapping, default):
    """Compress a code -> dialogId map into contiguous runs, dropping the default."""
    out, cur = [], None
    for code in sorted(mapping):
        d = mapping[code]
        if d == default:
            cur = None
            continue
        if cur and cur["dialog"] == d and code == cur["hi"] + 1:
            cur["hi"] = code
        else:
            cur = {"lo": code, "hi": code, "dialog": d}
            out.append(cur)
    return out


def discover_tables(image, sites):
    """Every switch jump table in the image whose arms sit near a raise site.

    GCC emits these as `cmplwi crN,rX,BOUND` / `lwzx` / `add` / `bctr` with the offset table
    laid down immediately after the `bctr`, offsets relative to the table itself. That shape is
    distinctive enough to find by scanning, which is how the "near-identical copies" of the
    dispatcher get found rather than guessed at.
    """
    found = []
    site_set = sorted(sites)
    for lo, hi, off, d in image.segments:
        for va in range(lo, hi - 3, 4):
            if struct.unpack_from(">I", d, off + (va - lo))[0] != 0x4E800420:   # bctr
                continue
            bound = None
            for back in range(1, 17):
                w = image.word(va - 4 * back)
                if w is None:
                    break
                if w >> 26 == 10 and not (w >> 21) & 1:      # cmplwi
                    bound = w & 0xFFFF
                    break
            if bound is None or not 1 <= bound < 256:
                continue
            base = va + 4
            targets = []
            for i in range(bound + 1):
                e = image.word(base + 4 * i)
                if e is None:
                    break
                t = base + s32(e)
                if not lo <= t < hi or t & 3:
                    targets = []
                    break
                targets.append(t)
            if len(targets) != bound + 1:
                continue
            span_lo, span_hi = min(targets), max(targets)
            if not any(span_lo - 0x400 <= s <= span_hi + 0x1000 for s in site_set):
                continue
            found.append((base, targets))
    return found


def successors(image, va):
    """Where control can go from one instruction. Falls back to fallthrough for plain ops."""
    w = image.word(va)
    if w is None:
        return []
    op = w >> 26
    if op == 18:                                          # b / bl
        li = w & 0x03FFFFFC
        if li & 0x02000000:
            li -= 0x04000000
        target = li if w & 2 else va + li
        return [va + 4] if w & 1 else [target]            # bl returns; b does not
    if op == 16:                                          # bc
        bd = w & 0xFFFC
        if bd & 0x8000:
            bd -= 0x10000
        target = bd if w & 2 else va + bd
        if w & 1:
            return [va + 4]
        bo = (w >> 21) & 0x1E
        return [target] if bo & 0x10 else [target, va + 4]
    if op == 19:                                          # blr / bctr
        return []
    return [va + 4]


def chain_heads(image, site, window=0x1200):
    """Entry candidates for the straight-line chain that ends at a raise site.

    Not every error block is reached through a jump table — the mail and character handlers hold
    theirs inline. Finding those needs the backward CFG walk proper: collect every instruction in
    a window that can actually reach the raise site, then take the nodes in that set which no
    other member branches into. Those are the ways in.

    A candidate is only a guess about layout. It is acted on solely when the sweep then verifies
    it, by finding the injected code in r4 at the raise site *and* by the chain discriminating on
    the code at all.
    """
    lo, hi = site - window, site + 0x400
    preds = defaultdict(list)
    for va in range(lo, hi, 4):
        for s in successors(image, va):
            if lo <= s < hi:
                preds[s].append(va)

    seen, stack = {site}, [site]
    while stack:
        for p in preds.get(stack.pop(), ()):
            if p not in seen:
                seen.add(p)
                stack.append(p)

    return sorted(seen)


def code_reg_at_site(image, site, limit=12):
    """Which register carries the result code into the raise, read off the call site itself.

    The tail is `extsw r4,rX` (or `mr r4,rX`) then `bl 0x885A08`, so rX is the code register —
    no search needed. `li r4,<const>` instead means this site reports a fixed code and is not
    part of any result-code chain.
    """
    for back in range(1, limit + 1):
        w = image.word(site - 4 * back)
        if w is None:
            return None
        op = w >> 26
        if op == 14 and (w >> 21) & 31 == 4:                      # li/addi r4,...
            return None
        if op == 31:
            xo, rs, ra = (w >> 1) & 0x3FF, (w >> 21) & 31, (w >> 16) & 31
            if xo in (986, 922) and ra == 4:                      # extsw/extsh r4,rS
                return rs
            if xo == 444 and ra == 4:                             # mr r4,rS
                return rs
    return None


def analyse(image, base, targets, covered):
    """One switch table: infer its code register, then sweep every arm."""
    reg, score = None, 0
    for t in targets:
        r, s = code_register(image, t)
        if s > score:
            reg, score = r, s
    if reg is None:
        return None

    arms = []
    for i, entry in enumerate(targets):
        mapping, unmodeled, sites, verified = trace(image, entry, reg)
        covered |= sites
        tally = defaultdict(int)
        for dv in mapping.values():
            tally[dv] += 1
        default = max(tally, key=tally.get) if tally else None
        arms.append({
            "index": i,
            "entry": f"0x{entry:X}",
            "default": default,
            "spans": spans(mapping, default),
            "resolved": len(mapping),
            "verified": verified,
            "unmodeled": len(unmodeled),
            "unmodeled_reason": sorted(set(unmodeled.values()))[:3],
        })
    return {"table": f"0x{base:X}", "code_register": f"r{reg}", "arms": arms}


def main():
    image = Image(ELF)

    all_sites = raise_sites(image)
    covered = set()

    arms = []
    for i in range(DISPATCH_ARMS):
        off = image.word(DISPATCH_TABLE + 4 * i)
        entry = DISPATCH_TABLE + s32(off)
        mapping, unmodeled, sites, verified = trace(image, entry)
        covered |= sites

        # The default is whatever the great majority of codes land on. Ties are impossible in
        # practice — a chain names a handful of codes and sends the rest one way.
        tally = defaultdict(int)
        for d in mapping.values():
            tally[d] += 1
        default = max(tally, key=tally.get) if tally else None

        arms.append({
            "index": i,
            "entry": f"0x{entry:X}",
            "default": default,
            "spans": spans(mapping, default),
            "resolved": len(mapping),
            "unmodeled": len(unmodeled),
            "unmodeled_reason": sorted(set(unmodeled.values()))[:3],
        })

    others = []
    for base, targets in discover_tables(image, all_sites):
        if base == DISPATCH_TABLE:
            continue
        got = analyse(image, base, targets, covered)
        if got and any(a["default"] is not None for a in got["arms"]):
            others.append(got)

    # Everything the tables did not account for: try each remaining raise site as the tail of an
    # inline chain. Kept only when the sweep verifies the code register, so a bad layout guess
    # drops out rather than being reported.
    inline, constant, fixed_code = [], [], 0
    for site in sorted(set(all_sites) - covered):
        reg = code_reg_at_site(image, site)
        if reg is None:
            fixed_code += 1              # raises a constant code: not on the result-code path
            continue
        # The chain head is the lowest reachable address that still runs to completion. Anything
        # lower includes the load that fetched the code and aborts, so the first address that
        # verifies is the entry.
        best = None
        for head in chain_heads(image, site):
            if head == site:
                continue
            _, _, s, v = trace(image, head, reg, PROBE[:16])
            if not s or not v:
                continue
            mapping, unmodeled, sites, verified = trace(image, head, reg)
            if not sites or not verified:
                continue
            tally = defaultdict(int)
            for dv in mapping.values():
                tally[dv] += 1
            default = max(tally, key=tally.get) if tally else None
            best = {
                "entry": f"0x{head:X}",
                "raise_site": f"0x{site:X}",
                "code_register": f"r{reg}",
                "default": default,
                "spans": spans(mapping, default),
                "verified": verified,
                "unmodeled": len(unmodeled),
                "_sites": sites,
            }
            break
        if best is None:
            continue
        covered |= best.pop("_sites")
        # A site whose dialogId is the same for every code is not a code-to-sentence mapping —
        # it is a fixed raise that happens to carry the code into the (nnnn:FFFFFFFF) suffix.
        # Worth counting, but it belongs in a different list from the chains that discriminate.
        (inline if best["spans"] else constant).append(best)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "inline_chains": inline,
        "constant_raises": constant,
        "fixed_code_sites": fixed_code,
        "other_tables": others,
        "table": f"0x{DISPATCH_TABLE:X}",
        "raise": f"0x{RAISE:X}",
        "sweep": [SWEEP[0], SWEEP[-1]],
        "arms": arms,
        "raise_sites": len(all_sites),
        "raise_sites_covered": sorted(f"0x{s:X}" for s in covered),
        "raise_sites_uncovered": sorted(f"0x{s:X}" for s in set(all_sites) - covered),
    }, indent=1) + "\n", encoding="utf-8")

    ok = sum(1 for a in arms if a["unmodeled"] == 0)
    print(f"{ok}/{len(arms)} arms fully traced -> {OUT}")
    print(f"raise sites: {len(covered)}/{len(all_sites)} reached by these arms")
    for a in arms:
        note = "" if not a["unmodeled"] else f"  UNMODELED {a['unmodeled']}: {a['unmodeled_reason']}"
        print(f"  arm {a['index']:2d} {a['entry']}  default={a['default']}  "
              f"spans={len(a['spans'])}{note}")


if __name__ == "__main__":
    main()
