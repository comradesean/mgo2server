#!/usr/bin/env python3
"""Editor for MGO2's ``d/testhk`` server-address override.

MGO2's twelve server hostnames and two ports are NOT in ``MGO2.SELF``. They are string
resources in ``o/stage/lobby/scenerio.gcx`` (entries 28654-28691, three regional blocks).
But the GCX native that loads them (``0x7F9310``) opens ``d/testhk`` FIRST, and if that file
yields a 16-byte header it takes the whole table from the file and never touches the disc data.

So pointing the game at your own server needs no patching: write this one file. Deleting it
restores stock behaviour exactly.

The format, read instruction by instruction out of the loader at ``0x7F94B8``:

    16 bytes  header. Only byte 0 matters, and only its low two bits:
              bit 0 -> OR 1 into the flag word at 0x016194CC
              bit 1 -> OR 2 into the same word
              Bits 2-7 and bytes 1-15 are read and never referenced.
              There is NO magic, version, count, length or checksum. The only validation in
              the whole header path is that the read returned exactly 16 bytes.
    then 16x  <string bytes> 0x00      NUL-terminated, read one byte at a time
                                       (12x on the release-day disc build)
              <2 bytes>                BIG-endian port -- used for slots 0 and 1 only,
                                       read and discarded for slots 2-11, but MANDATORY:
                                       omit them and the loader eats the next record's
                                       first two characters as a port.

Minimum file: 16 + 16*3 = 64 bytes for 1.36 (was 16 + 12*3 = 52 on the disc build).
Nothing after the sixteenth record is read.

**The port endianness is opposite to the disc.** The loader does ``lhz`` on the raw file bytes
(``0x7F95C0``), so the file is big-endian: 15731 is ``3D 73``. The stage-resource path decodes
little-endian (``0xDF9A8``), which is why the disc holds ``73 3D``. A byte-swapped port is
exactly the mistake that wastes a live test.

Failure is safe. A missing file, a short header, or any truncated read closes the handle and
falls through to the disc table, which overwrites every slot. There is no half-loaded state.

**The file is encrypted.** ``d/testhk`` is opened with the flag bit that routes it to the
path-keyed asset opener (``0x2EE48``), which derives its key from the directory component of
the path -- ``d`` -- exactly as ``stage/lobby`` keys the lobby assets. A plaintext file will
not load. This tool builds the plaintext and then calls Solideye to encrypt it.

Slot order is confirmed from the setters (``0x28AB00`` writes host i to ``0x016188C8 + i*256``;
``0x28AAB0`` writes port i to ``0x016194C8 + i*2``), not inferred from what the strings look like.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field, replace
from pathlib import Path

#: What each slot feeds, from the consumer trace.
#:
#: Slots 0-11 are the release-day disc build's table. Slots 12-15 exist ONLY in the 1.36 build,
#: which reads SIXTEEN records -- see BUILD_1_36_SLOT_COUNT below and dev/docs/BUILD_1_36.md.
SLOTS = (
	("Gate server", "host only; port below. Read by the connect at 0x9462C0"),
	("STUN server", "host only; port below. NAT port check"),
	("Web base URL", "version check (uupdate.cc) and static documents"),
	("Auth URL", "the full login URL (uaccount.cc). Change https->http here"),
	("STUN HTTP URL", "the /sttn/ endpoint"),
	("KONAMI ID URL", "account site link"),
	("Community URL", "menu link"),
	("Manual URL", "menu link"),
	("Reward URL", "menu link"),
	("MPT shop URL", "menu link"),
	("Official site URL", "menu link"),
	("Info service URL", "region info document"),
	# --- 1.36 ONLY. The disc build reads twelve records and stops. ---
	("[1.36] Commerce URL A", "returned raw by a getter at 0xAB35B4 (1.36 addr)"),
	("[1.36] Commerce query base", "gets /query.html appended (0xEA632C cluster)"),
	("[1.36] Product URL", "formatted %s?prod=%d (0xAC22CC); stock default http://127.0.0.1/"),
	("[1.36] PSN update URL", "strncpy 511 then the shared HTTP entry (0x990234)"),
)

#: The stock tables, read off the disc (strres 28654-28691). Ports are the real values;
#: this tool writes them big-endian as the loader expects.
STOCK = {
	"US": (
		[
			"mgo2gateus.konamionline.com",
			"mgo2stunna.konamionline.com",
			"https://mgo2web.konami.com/us/mgo2/",
			"https://mgo2auth.konami.com/us/mgo2/kid/gidauth5.html",
			"http://mgo2stunna.konamionline.com/sttn/",
			"https://id.konami.net/",
			"https://mgo2web.konami.com/community/",
			"http://mgo2web.konami.com/us/mgo2/red/man.html",
			"https://mgo2web.konami.com/reward/",
			"http://mgo2web.konami.com/us/mgo2/red/mptshop.html",
			"http://mgo2web.konami.com/us/mgo2/red/official.html",
			"http://info.service.konamionline.com/VT006-U1/info/",
		],
		15731,
		3478,
	),
	"EU": (
		[
			"mgo2gateeu.konamionline.com",
			"mgo2stuneu.konamionline.com",
			"https://mgo2web.konami.com/eu/mgo2/",
			"https://mgo2auth.konami.com/eu/mgo2/kid/gidauth5.html",
			"http://mgo2stuneu.konamionline.com/sttn/",
			"https://id.konami.net/",
			"https://mgo2web.konami.com/community/",
			"http://mgo2web.konami.com/eu/mgo2/red/man.html",
			"https://mgo2web.konami.com/reward/",
			"http://mgo2web.konami.com/eu/mgo2/red/mptshop.html",
			"http://mgo2web.konami.com/eu/mgo2/red/official.html",
			"http://info.service.konamionline.com/VT006-E1/info/",
		],
		25731,
		3478,
	),
	"JP": (
		[
			"mgo2gatejp.konamionline.com",
			"mgo2stunjp.konamionline.com",
			"https://mgo2web.konami.com/jp/mgo2/",
			"https://mgo2auth.konami.com/jp/mgo2/kid/gidauth5.html",
			"http://mgo2stunjp.konamionline.com/sttn/",
			"https://id.konami.net/",
			"https://mgo2web.konami.com/community/",
			"http://mgo2web.konami.com/jp/mgo2/red/man.html",
			"https://mgo2web.konami.com/reward/",
			"http://mgo2web.konami.com/jp/mgo2/red/mptshop.html",
			"http://mgo2web.konami.com/jp/mgo2/red/official.html",
			"http://info.service.konamionline.com/VT006-J1/info/",
		],
		5731,
		3478,
	),
}

HEADER_BYTES = 16

#: The loop exits at index 255 without terminating the buffer, and the copy that follows is an
#: unbounded strcpy into a 256-byte slot. 255 usable characters is the real ceiling, and going
#: over it is a buffer overrun rather than a truncation.
MAX_STRING = 255

#: How many records the DISC build reads: `cmpwi cr7,r27,11` at 0x7F955C.
DISC_SLOT_COUNT = 12

#: How many the 1.36 build reads: `cmpwi cr7,r27,15` at 0x8EF324 (1.36 addresses).
#: Corroborated structurally -- 1.36's port accessors sit at 4096 (16 * 256) where the disc build
#: uses 3072 (12 * 256), and all four new indices have live call sites.
BUILD_1_36_SLOT_COUNT = 16

#: What this tool WRITES. Sixteen, because a 16-record file is correct for BOTH builds: the disc
#: build reads the first twelve and stops, and never looks at the rest.
#:
#: A 12-record file is NOT correct for both. 1.36 consumes through record 11, tries record 12, hits
#: EOF, and falls back to the string-resource table SILENTLY -- so the client dials the real Konami
#: hostnames, nothing answers, and it reports 0703:00000000 with a ZERO code and no diagnostic.
#: That is a whole debugging session; the asymmetry is the reason this default is 16 and not 12.
SLOT_COUNT = BUILD_1_36_SLOT_COUNT


#: Slot 14's own default inside the 1.36 binary (VA 0x00FE8718). Used to pad slots 12-15, for
#: which no stock value exists on the disc.
PLACEHOLDER_URL = "http://127.0.0.1/"


class TesthkError(Exception):
	"""A problem with the table, the file, or the encryption step."""


@dataclass
class Table:
	"""One ``d/testhk`` table: sixteen strings, two ports, two header bits.

	Sixteen because 1.36 reads sixteen; the disc build reads the first twelve and ignores the rest,
	so one 16-record file serves both. See ``SLOT_COUNT``.
	"""

	hosts: list[str] = field(default_factory=lambda: [""] * SLOT_COUNT)
	gate_port: int = 15731
	stun_port: int = 3478
	flag_bit0: bool = False
	flag_bit1: bool = False

	@classmethod
	def stock(cls, region: str = "US") -> "Table":
		hosts, gate, stun = STOCK[region]
		hosts = list(hosts)
		# STOCK holds the twelve slots read off the DISC build's string resources. 1.36 adds four
		# more (commerce / PS Store / PSN update), and we have no stock values for them because
		# they live in the 1.36 patch's own scenerio.gcx, not on the disc.
		#
		# Pad with the loopback placeholder the binary itself carries as slot 14's default
		# (VA 0x00FE8718 in 1.36). Loopback is the safe filler: those subsystems are not served
		# here, and pointing them at the client's own machine makes them fail locally instead of
		# reaching out to the internet or at us.
		while len(hosts) < SLOT_COUNT:
			hosts.append(PLACEHOLDER_URL)
		return cls(hosts=hosts, gate_port=gate, stun_port=stun)

	def problems(self) -> list[str]:
		"""Every reason this table would not load, in file order."""
		found = []
		if len(self.hosts) != SLOT_COUNT:
			found.append(f"need exactly {SLOT_COUNT} slots, have {len(self.hosts)}")
		for index, text in enumerate(self.hosts[:SLOT_COUNT]):
			label = SLOTS[index][0] if index < len(SLOTS) else f"slot {index}"
			if len(text) > MAX_STRING:
				found.append(f"{label}: {len(text)} chars, max {MAX_STRING} "
					"(the loader would overrun its buffer)")
			try:
				text.encode("ascii")
			except UnicodeEncodeError:
				found.append(f"{label}: non-ASCII characters")
			if "\0" in text:
				found.append(f"{label}: contains a NUL, which would end the record early")
		for label, port in (("gate port", self.gate_port), ("STUN port", self.stun_port)):
			if not 0 <= port <= 0xFFFF:
				found.append(f"{label} {port} is not a u16")
		return found

	def point_at(self, host: str, include_commerce: bool = False) -> "Table":
		"""Return a copy with every host and every URL authority replaced by ``host``.

		Slots 0 and 1 are bare hostnames. The rest are URLs, so only the authority is
		swapped and the scheme and path are kept.

		**Slots 12-15 are left on loopback unless ``include_commerce`` is set.** Those four exist
		only in 1.36 and are the PS Store / PSN-update subsystem, which this server does not
		implement. Slot 13 in particular is fetched from about ten call sites with ``/query.html``
		appended, so answering it wrongly is a way to break a session that would otherwise work.
		Loopback makes them fail on the client's own machine instead.

		Set ``include_commerce=True`` deliberately when the goal is to *observe* what 1.36 asks
		for -- the requests then land in the probe logs and can be mapped. That is a useful
		experiment, but it is not the right default while merely getting a client connected.
		"""
		swapped = []
		for index, text in enumerate(self.hosts):
			if index >= DISC_SLOT_COUNT and not include_commerce:
				swapped.append(PLACEHOLDER_URL)
				continue
			if index < 2 or "://" not in text:
				swapped.append(host)
				continue
			scheme, _, rest = text.partition("://")
			_, slash, path = rest.partition("/")
			swapped.append(f"{scheme}://{host}{slash}{path}")
		return replace(self, hosts=swapped)

	def force_http(self) -> "Table":
		"""Return a copy with every ``https://`` downgraded to ``http://``.

		The scheme is part of the stored string -- there is no code path or flag bit that
		selects it -- so this is the whole of "turn HTTPS off" for these requests.
		"""
		return replace(self, hosts=[
			("http://" + t[len("https://"):]) if t.startswith("https://") else t
			for t in self.hosts])


def build(table: Table) -> bytes:
	"""Serialise a table to the plaintext ``d/testhk`` bytes."""
	problems = table.problems()
	if problems:
		raise TesthkError("; ".join(problems))

	header = bytearray(HEADER_BYTES)
	header[0] = (1 if table.flag_bit0 else 0) | (2 if table.flag_bit1 else 0)

	out = bytearray(header)
	for index, text in enumerate(table.hosts):
		out += text.encode("ascii") + b"\0"
		if index == 0:
			out += table.gate_port.to_bytes(2, "big")
		elif index == 1:
			out += table.stun_port.to_bytes(2, "big")
		else:
			# Read and discarded, but the loader always consumes two bytes here.
			out += b"\0\0"
	return bytes(out)


def parse(data: bytes) -> Table:
	"""Read plaintext ``d/testhk`` bytes back into a table, the way the loader would."""
	if len(data) < HEADER_BYTES:
		raise TesthkError(f"only {len(data)} bytes; the header alone needs {HEADER_BYTES}")

	table = Table(hosts=[], flag_bit0=bool(data[0] & 1), flag_bit1=bool(data[0] & 2))
	pos = HEADER_BYTES
	for index in range(SLOT_COUNT):
		end = data.find(b"\0", pos, pos + MAX_STRING + 1)
		if end < 0:
			raise TesthkError(f"slot {index}: no NUL within {MAX_STRING + 1} bytes at "
				f"offset {pos}; the loader would read past the record")
		try:
			text = data[pos:end].decode("ascii")
		except UnicodeDecodeError as exc:
			raise TesthkError(f"slot {index}: non-ASCII bytes") from exc
		pos = end + 1
		if pos + 2 > len(data):
			raise TesthkError(f"slot {index}: file ends before its 2 trailing bytes")
		trailer = data[pos:pos + 2]
		pos += 2
		table.hosts.append(text)
		if index == 0:
			table.gate_port = int.from_bytes(trailer, "big")
		elif index == 1:
			table.stun_port = int.from_bytes(trailer, "big")
	return table


# ---------------------------------------------------------------------------
# Encryption. Solideye is a Windows .exe; it takes Windows paths only.
# ---------------------------------------------------------------------------

DEFAULT_SOLIDEYE = Path(__file__).resolve().parent / "solideye" / "Solideye.exe"

#: The asset key is the DIRECTORY component of the path the game opens, so "d/testhk" keys
#: on "d" -- the same rule that makes "stage/lobby" open the lobby assets.
ASSET_KEY = "d"


def _win_path(path: Path) -> str:
	"""Windows form of a path, for the Solideye executable."""
	if sys.platform == "win32":
		return str(path)
	try:
		return subprocess.run(["wslpath", "-w", str(path)], capture_output=True, text=True,
			check=True).stdout.strip()
	except (OSError, subprocess.CalledProcessError) as exc:
		raise TesthkError(f"cannot convert {path} to a Windows path for Solideye: {exc}") from exc


def solideye_available(exe: Path = DEFAULT_SOLIDEYE) -> bool:
	return exe.is_file()


def _run_solideye(exe: Path, mode: str, source: Path, outdir: Path) -> Path:
	outdir.mkdir(parents=True, exist_ok=True)
	before = set(outdir.iterdir())
	result = subprocess.run(
		[str(exe), mode, _win_path(source), "-k", ASSET_KEY, "-o", _win_path(outdir)],
		capture_output=True, text=True)
	produced = sorted(set(outdir.iterdir()) - before)
	if not produced:
		raise TesthkError(f"Solideye {mode} produced no output.\n"
			f"stdout: {result.stdout.strip()}\nstderr: {result.stderr.strip()}")
	return produced[0]


def encrypt(plain: bytes, exe: Path = DEFAULT_SOLIDEYE, verify: bool = True) -> bytes:
	"""Encrypt plaintext for ``d/testhk``, optionally proving the round-trip first.

	``verify`` re-decrypts the result and checks it matches the input. Solideye's cipher is
	the same one that opens ``stage/lobby``, so a clean round-trip is good evidence the bytes
	are the shape the game expects -- but it is NOT proof the game accepts the file. Only
	running it is.
	"""
	if not exe.is_file():
		raise TesthkError(f"Solideye not found at {exe}. It is a Windows executable; on Linux "
			"or macOS run it under wine, or build the file with --plain and encrypt elsewhere.")

	with tempfile.TemporaryDirectory() as tmp:
		work = Path(tmp)
		source = work / "testhk"
		source.write_bytes(plain)
		encrypted = _run_solideye(exe, "-enc", source, work / "enc").read_bytes()

		if verify:
			check_src = work / "check"
			check_src.write_bytes(encrypted)
			back = _run_solideye(exe, "-dec", check_src, work / "dec").read_bytes()
			if back != plain:
				raise TesthkError(
					f"round-trip failed: encrypted {len(plain)} bytes, decrypted back "
					f"{len(back)} that differ. Do not install this file.")
	return encrypted


def install(encrypted: bytes, usrdir: Path, backup: bool = True) -> tuple[Path, Path | None]:
	"""Write the encrypted file to ``<usrdir>/o/d/testhk``. Returns (path, backup or None)."""
	if is_disc_usrdir(usrdir):
		raise TesthkError(
			f"{usrdir} looks like the DISC tree (it has o/di, which the HDD install does not). "
			"The game opens /dev_hdd0/game/<TITLEID>/USRDIR/o/d/testhk and never looks at the "
			"disc for this file. Point at the dev_hdd0 install instead.")
	target_dir = usrdir / "o" / "d"
	target = target_dir / "testhk"
	saved = None
	if target.exists() and backup:
		saved = target.with_suffix(".bak")
		shutil.copy2(target, saved)
	target_dir.mkdir(parents=True, exist_ok=True)
	temp = target.with_suffix(".tmp")
	temp.write_bytes(encrypted)
	os.replace(temp, target)
	return target, saved


def to_local_path(text: str) -> Path:
	"""Accept a Windows path even when running under WSL."""
	import re
	text = text.strip().strip('"')
	drive = re.match(r"^([A-Za-z]):[\\/](.*)$", text)
	if drive and sys.platform != "win32" and Path("/mnt").is_dir():
		return Path(f"/mnt/{drive.group(1).lower()}") / drive.group(2).replace("\\", "/")
	return Path(text)


def is_disc_usrdir(usrdir: Path) -> bool:
	"""True if this looks like the DISC tree rather than the HDD install.

	**The discriminator is the PATH, not the presence of a file.** An HDD install always lives
	under ``dev_hdd0/game/<TITLEID>/USRDIR``; the disc tree always lives under ``PS3_GAME/USRDIR``.
	Those are structural and cannot both be true.

	This used to test for ``o/di`` on the reasoning that it "ships on the disc and is absent from
	the HDD install". **That is false and it cost a debugging detour on 2026-08-02.** A 1.36 HDD
	install has ``o/di`` — hardlinked to the disc's copy, same inode, link count 2 — so the check
	classified the correct target as the disc and refused to write to it. File presence is a
	guess about how someone installed the game; the path is a fact about which tree you are in.
	"""
	if "dev_hdd0" in usrdir.parts:
		return False
	return "PS3_GAME" in usrdir.parts or (usrdir / "o" / "di").is_file()


def find_usrdir(hint: Path | None = None) -> Path | None:
	"""Locate the HDD install's USRDIR -- ``dev_hdd0/game/<TITLEID>/USRDIR``.

	This is deliberately NOT the disc directory. RPCS3's log shows the game opening
	``/dev_hdd0/game/BLUS30109/USRDIR/o/d/testhk``; the disc tree is never consulted for it.
	The VFS serves different files from different roots, so the two are not interchangeable.
	"""
	roots: list[Path] = []
	if hint:
		roots += [hint, *hint.parents]

	for base in roots:
		# An RPCS3 install root, or anything above one.
		for match in sorted((base / "dev_hdd0" / "game").glob("*/USRDIR")
				if (base / "dev_hdd0" / "game").is_dir() else []):
			if (match / "o").is_dir():
				return match
		# The USRDIR itself, or a game directory holding one.
		for candidate in (base, base / "USRDIR"):
			if (candidate / "o").is_dir() and not is_disc_usrdir(candidate):
				return candidate
	return None


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------

def run_gui(initial: Path | None) -> int:
	import tkinter as tk
	from tkinter import filedialog, messagebox, ttk

	root = tk.Tk()
	root.title("MGO2 d/testhk editor — server address override")
	root.minsize(900, 640)
	root.columnconfigure(0, weight=1)
	root.rowconfigure(2, weight=1)

	usrdir_var = tk.StringVar()
	status = tk.StringVar()
	bulk_var = tk.StringVar(value="192.168.1.200")
	gate_var = tk.StringVar(value="15731")
	stun_var = tk.StringVar(value="3478")
	bit0_var = tk.BooleanVar(value=False)
	bit1_var = tk.BooleanVar(value=False)
	host_vars = [tk.StringVar() for _ in range(SLOT_COUNT)]

	# --- target ------------------------------------------------------------
	top = ttk.Frame(root, padding=(10, 10, 10, 4))
	top.grid(row=0, column=0, sticky="ew")
	top.columnconfigure(1, weight=1)
	ttk.Label(top, text="Game USRDIR").grid(row=0, column=0, padx=(0, 6))
	ttk.Entry(top, textvariable=usrdir_var).grid(row=0, column=1, sticky="ew")

	def choose_dir() -> None:
		picked = filedialog.askdirectory(title="Pick the game's USRDIR (the folder holding o/)")
		if picked:
			found = find_usrdir(Path(picked)) or Path(picked)
			usrdir_var.set(str(found))

	ttk.Button(top, text="Browse…", command=choose_dir).grid(row=0, column=2, padx=(6, 0))

	note = ttk.Label(root, padding=(10, 0), justify="left", wraplength=860, text=(
		"Writes o/d/testhk. While that file loads, the game ignores the disc's address table "
		"entirely — delete it to go back to stock. Slots 0 and 1 are bare hostnames with ports; "
		"the rest are full URLs, and the scheme in slot 3 is what decides HTTPS vs HTTP."))
	note.grid(row=1, column=0, sticky="ew")

	# --- slots -------------------------------------------------------------
	body = ttk.Frame(root, padding=(10, 6))
	body.grid(row=2, column=0, sticky="nsew")
	body.columnconfigure(1, weight=1)
	for index, (label, hint) in enumerate(SLOTS):
		ttk.Label(body, text=f"{index}  {label}").grid(row=index, column=0, sticky="w", pady=2)
		ttk.Entry(body, textvariable=host_vars[index]).grid(row=index, column=1, sticky="ew",
			padx=6, pady=2)
		if index == 0:
			ttk.Label(body, text="port").grid(row=index, column=2)
			ttk.Entry(body, textvariable=gate_var, width=8).grid(row=index, column=3)
		elif index == 1:
			ttk.Label(body, text="port").grid(row=index, column=2)
			ttk.Entry(body, textvariable=stun_var, width=8).grid(row=index, column=3)
		else:
			ttk.Label(body, text=hint, foreground="#777").grid(row=index, column=2, columnspan=2,
				sticky="w", padx=(8, 0))

	# --- controls ----------------------------------------------------------
	def current_table() -> Table:
		try:
			gate = int(gate_var.get())
			stun = int(stun_var.get())
		except ValueError as exc:
			raise TesthkError("ports must be whole numbers") from exc
		return Table([v.get().strip() for v in host_vars], gate, stun,
			bit0_var.get(), bit1_var.get())

	def show(table: Table) -> None:
		for var, text in zip(host_vars, table.hosts):
			var.set(text)
		gate_var.set(str(table.gate_port))
		stun_var.set(str(table.stun_port))
		bit0_var.set(table.flag_bit0)
		bit1_var.set(table.flag_bit1)
		refresh()

	def refresh(*_args: object) -> None:
		try:
			table = current_table()
		except TesthkError as exc:
			status.set(str(exc))
			return
		problems = table.problems()
		if problems:
			status.set("; ".join(problems))
		else:
			status.set(f"{len(build(table))} bytes plaintext — valid. "
				f"Gate {table.gate_port} writes as {table.gate_port.to_bytes(2, 'big').hex(' ')} "
				"(big-endian, opposite to the disc).")

	for var in (*host_vars, gate_var, stun_var):
		var.trace_add("write", refresh)

	controls = ttk.Frame(root, padding=(10, 4))
	controls.grid(row=3, column=0, sticky="ew")
	ttk.Label(controls, text="Load stock:").pack(side="left")
	for region in ("US", "EU", "JP"):
		ttk.Button(controls, text=region, width=4,
			command=lambda r=region: show(Table.stock(r))).pack(side="left", padx=2)
	ttk.Separator(controls, orient="vertical").pack(side="left", fill="y", padx=8)
	ttk.Label(controls, text="Point everything at:").pack(side="left")
	ttk.Entry(controls, textvariable=bulk_var, width=18).pack(side="left", padx=4)

	def apply_bulk() -> None:
		try:
			show(current_table().point_at(bulk_var.get().strip()))
		except TesthkError as exc:
			messagebox.showerror("Cannot apply", str(exc))

	ttk.Button(controls, text="Apply", command=apply_bulk).pack(side="left")
	ttk.Button(controls, text="HTTPS → HTTP",
		command=lambda: show(current_table().force_http())).pack(side="left", padx=8)

	flags = ttk.Frame(root, padding=(10, 0))
	flags.grid(row=4, column=0, sticky="ew")
	ttk.Checkbutton(flags, text="header bit 0 (sets flag 1 — no reader found in the binary)",
		variable=bit0_var, command=refresh).pack(side="left")
	ttk.Checkbutton(flags, text="bit 1 (sets flag 2 — read by uaccount.cc and uupdate.cc; "
		"effect unknown)", variable=bit1_var, command=refresh).pack(side="left", padx=12)

	# --- actions -----------------------------------------------------------
	def save_plain() -> None:
		try:
			data = build(current_table())
		except TesthkError as exc:
			messagebox.showerror("Invalid table", str(exc))
			return
		picked = filedialog.asksaveasfilename(title="Save plaintext testhk",
			initialfile="testhk.plain")
		if picked:
			Path(picked).write_bytes(data)
			status.set(f"Wrote {len(data)} plaintext bytes to {picked} (NOT encrypted — the "
				"game cannot read this form).")

	def do_install() -> None:
		try:
			table = current_table()
			data = build(table)
		except TesthkError as exc:
			messagebox.showerror("Invalid table", str(exc))
			return
		usrdir = to_local_path(usrdir_var.get())
		if not (usrdir / "o").is_dir():
			messagebox.showerror("Wrong folder", f"{usrdir} has no o/ subdirectory.")
			return
		if not messagebox.askokcancel("Install", f"Write o/d/testhk under\n{usrdir}\n\n"
				"While this file loads the game ignores the disc address table. "
				"Delete it to revert."):
			return
		try:
			encrypted = encrypt(data)
			target, saved = install(encrypted, usrdir)
		except TesthkError as exc:
			messagebox.showerror("Failed", str(exc))
			return
		status.set(f"Installed {target} ({len(encrypted)} bytes encrypted, round-trip verified)"
			+ (f"; previous file backed up to {saved.name}" if saved else ""))

	actions = ttk.Frame(root, padding=(10, 8))
	actions.grid(row=5, column=0, sticky="ew")
	ttk.Button(actions, text="Install to game", command=do_install).pack(side="right")
	ttk.Button(actions, text="Save plaintext…", command=save_plain).pack(side="right", padx=6)

	ttk.Label(root, textvariable=status, padding=(10, 0, 10, 10), wraplength=860,
		justify="left").grid(row=6, column=0, sticky="ew")

	found = find_usrdir(initial) if initial else None
	usrdir_var.set(str(found or initial or ""))
	show(Table.stock("US").point_at("192.168.1.200"))
	if not solideye_available():
		status.set(f"Solideye not found at {DEFAULT_SOLIDEYE} — you can still build plaintext, "
			"but installing needs it to encrypt.")

	root.mainloop()
	return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def run_cli(args: argparse.Namespace) -> int:
	if args.read:
		table = parse(to_local_path(args.read).read_bytes())
	else:
		table = Table.stock(args.region)
	if args.point_at:
		table = table.point_at(args.point_at)
	if args.http:
		table = table.force_http()
	if args.gate_port is not None:
		table = replace(table, gate_port=args.gate_port)
	if args.stun_port is not None:
		table = replace(table, stun_port=args.stun_port)

	problems = table.problems()
	if problems:
		print("\n".join(problems), file=sys.stderr)
		return 2

	plain = build(table)
	for index, (label, _hint) in enumerate(SLOTS):
		extra = ""
		if index == 0:
			extra = f"   port {table.gate_port} -> {table.gate_port.to_bytes(2, 'big').hex(' ')}"
		elif index == 1:
			extra = f"   port {table.stun_port} -> {table.stun_port.to_bytes(2, 'big').hex(' ')}"
		print(f"  {index:2d} {label:18s} {table.hosts[index]}{extra}")
	print(f"  header byte 0 = 0x{plain[0]:02x};  {len(plain)} bytes plaintext")

	if args.plain:
		Path(args.plain).write_bytes(plain)
		print(f"Wrote plaintext {args.plain} — the game cannot read this form; encrypt it with "
			f"Solideye -enc -k {ASSET_KEY}")
	if args.install:
		usrdir = find_usrdir(to_local_path(args.install)) or to_local_path(args.install)
		if not (usrdir / "o").is_dir():
			print(f"{usrdir} has no o/ subdirectory", file=sys.stderr)
			return 2
		encrypted = encrypt(plain)
		target, saved = install(encrypted, usrdir)
		print(f"Installed {target} ({len(encrypted)} bytes, round-trip verified)"
			+ (f"; backup {saved.name}" if saved else ""))
	return 0


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(
		description="Build MGO2's d/testhk server-address override.",
		epilog="The override wins over the disc's address table while it exists; delete "
			"o/d/testhk to revert. Ports are written big-endian, which is the opposite of "
			"how the disc stores them.")
	parser.add_argument("usrdir", nargs="?", help="the game USRDIR, for the GUI's target field")
	parser.add_argument("--no-gui", action="store_true")
	parser.add_argument("--region", choices=sorted(STOCK), default="US",
		help="which stock table to start from (default US, which is what o/di byte 42 selects "
			"for BLUS30109)")
	parser.add_argument("--read", metavar="FILE", help="load a PLAINTEXT testhk instead of stock")
	parser.add_argument("--point-at", metavar="HOST", help="replace every host/authority")
	parser.add_argument("--http", action="store_true", help="downgrade every https:// to http://")
	parser.add_argument("--gate-port", type=int)
	parser.add_argument("--stun-port", type=int)
	parser.add_argument("--plain", metavar="FILE", help="write the plaintext here")
	parser.add_argument("--install", metavar="USRDIR", help="encrypt and write o/d/testhk there")
	args = parser.parse_args(argv)

	if args.no_gui or args.plain or args.install or args.read or args.point_at:
		return run_cli(args)
	try:
		import tkinter  # noqa: F401
	except ImportError:
		print("tkinter is not installed; showing the CLI instead.\n"
			"  Debian/Ubuntu: sudo apt install python3-tk\n", file=sys.stderr)
		return run_cli(args)
	return run_gui(to_local_path(args.usrdir) if args.usrdir else None)


if __name__ == "__main__":
	sys.exit(main())
