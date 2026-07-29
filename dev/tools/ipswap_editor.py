#!/usr/bin/env python3
"""Editor for RPCS3's ``IP swap list`` — the host -> IP redirect map.

The MGO2 host redirects are NOT in ``MGO2.SELF``. They are a plain RPCS3 setting:

    Net:
      IP swap list: "mgo2web.konami.com=192.168.1.200&&info.service.konamionline.com=..."

living in ``config/config.yml`` (global) and ``config/custom_configs/config_<TITLEID>.yml``
(per title, which wins when present). Nothing is encrypted, so nothing needs decrypting —
see the module docstring note in ``main()`` and dev/docs/SETUP.md.

Pure stdlib, so it runs anywhere Python does. With tkinter available it opens a GUI;
without it, the same operations are on the command line (``--help``).

The writer is line-level on purpose: it replaces exactly the ``IP swap list:`` line and
leaves every other byte of the file — key order, comments, line endings — untouched. A
YAML round-trip would reformat the whole file, and RPCS3 rewrites configs it parses.
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

KEY = "IP swap list"

#: The five hosts a stock BLUS30109 dials. Handy as a starting point; the IP is yours.
MGO2_HOSTS = (
	"mgo2web.konami.com",
	"info.service.konamionline.com",
	"mgo2gateus.konamionline.com",
	"mgo2stunna.konamionline.com",
	"mgo2auth.konami.com",
)

_LINE = re.compile(rf"^(?P<indent>\s*){re.escape(KEY)}\s*:\s*(?P<value>.*?)\s*$")


# ---------------------------------------------------------------------------
# Core: parsing, formatting, file IO. No UI, no globals — all of it testable.
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Entry:
	"""One ``hostname=ip`` redirect."""

	host: str
	ip: str

	def problem(self) -> str | None:
		"""Why this entry is unusable, or None. Non-IPv4 targets are a warning, not this."""
		if not self.host:
			return "empty hostname"
		if not self.ip:
			return "empty target"
		for field, text in (("hostname", self.host), ("target", self.ip)):
			for bad in ("=", "&", '"'):
				if bad in text:
					return f"{bad!r} is not allowed in a {field}"
		return None

	def is_ipv4(self) -> bool:
		try:
			ipaddress.IPv4Address(self.ip)
			return True
		except ValueError:
			return False


def parse_value(raw: str) -> list[Entry]:
	"""Parse the setting's value (with or without surrounding quotes) into entries."""
	raw = raw.strip()
	if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
		raw = raw[1:-1]
	entries = []
	for chunk in raw.split("&&"):
		chunk = chunk.strip()
		if not chunk:
			continue
		host, sep, ip = chunk.partition("=")
		# A chunk with no '=' is malformed; keep it visible as a host with no target
		# rather than dropping it silently.
		entries.append(Entry(host.strip(), ip.strip() if sep else ""))
	return entries


def format_value(entries: list[Entry]) -> str:
	"""Render entries back into the ``a=1&&b=2`` value, unquoted."""
	return "&&".join(f"{e.host}={e.ip}" for e in entries)


def read_config(path: Path) -> tuple[list[str], int, list[Entry]]:
	"""Return (lines with their original endings, index of the setting line, entries).

	Raises LookupError if the file has no ``IP swap list`` line.
	"""
	with path.open("r", encoding="utf-8", newline="") as handle:
		lines = handle.read().splitlines(keepends=True)
	for index, line in enumerate(lines):
		match = _LINE.match(line.rstrip("\r\n"))
		if match:
			return lines, index, parse_value(match.group("value"))
	raise LookupError(f"no {KEY!r} line in {path}")


def write_config(path: Path, entries: list[Entry], backup: bool = True) -> Path | None:
	"""Rewrite just the setting line. Returns the backup path, or None if not taken."""
	lines, index, _ = read_config(path)
	match = _LINE.match(lines[index].rstrip("\r\n"))
	assert match is not None  # read_config only returns an index that matched
	ending = lines[index][len(lines[index].rstrip("\r\n")):] or os.linesep
	lines[index] = f'{match.group("indent")}{KEY}: "{format_value(entries)}"{ending}'

	backup_path = path.with_suffix(path.suffix + ".bak")
	if backup:
		shutil.copy2(path, backup_path)

	# Same-directory temp + replace, so a crash mid-write cannot truncate the config.
	temp = path.with_suffix(path.suffix + ".tmp")
	with temp.open("w", encoding="utf-8", newline="") as handle:
		handle.write("".join(lines))
	os.replace(temp, path)
	return backup_path if backup else None


# ---------------------------------------------------------------------------
# Finding the config
# ---------------------------------------------------------------------------

def to_local_path(text: str) -> Path:
	"""Accept a Windows path even when running under WSL, and vice versa."""
	text = text.strip().strip('"')
	drive = re.match(r"^([A-Za-z]):[\\/](.*)$", text)
	if drive and sys.platform != "win32" and Path("/mnt").is_dir():
		return Path(f"/mnt/{drive.group(1).lower()}") / drive.group(2).replace("\\", "/")
	return Path(text)


def candidate_configs(hint: Path | None = None) -> list[Path]:
	"""Configs that carry the setting, per-title first (they override the global one)."""
	roots: list[Path] = []
	if hint:
		# Accept the RPCS3 root, its config dir, or anything inside the install.
		for base in (hint, *hint.parents):
			if (base / "config").is_dir() or base.name == "config":
				roots.append(base if base.name != "config" else base.parent)
				break
		else:
			roots.append(hint)
	roots += [
		Path.home() / ".config/rpcs3",
		Path.home() / "Library/Application Support/rpcs3",
		Path(os.environ.get("LOCALAPPDATA", "")) / "rpcs3" if os.environ.get("LOCALAPPDATA") else Path(),
	]

	found: list[Path] = []
	for root in roots:
		if not root or not root.is_dir():
			continue
		config_dir = root / "config" if (root / "config").is_dir() else root
		found += sorted(config_dir.glob("custom_configs/config_*.yml"))
		if (config_dir / "config.yml").is_file():
			found.append(config_dir / "config.yml")

	seen, unique = set(), []
	for path in found:
		resolved = path.resolve()
		if resolved in seen:
			continue
		seen.add(resolved)
		try:
			read_config(path)
		except (LookupError, OSError, UnicodeDecodeError):
			continue
		unique.append(path)
	return unique


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------

def run_gui(initial: Path | None) -> int:
	import tkinter as tk
	from tkinter import filedialog, messagebox, ttk

	root = tk.Tk()
	root.title("RPCS3 IP swap list editor")
	root.minsize(760, 460)
	root.columnconfigure(0, weight=1)
	root.rowconfigure(1, weight=1)

	state: dict[str, object] = {"path": None, "dirty": False}

	# --- file row ----------------------------------------------------------
	top = ttk.Frame(root, padding=(10, 10, 10, 4))
	top.grid(row=0, column=0, sticky="ew")
	top.columnconfigure(1, weight=1)
	ttk.Label(top, text="Config").grid(row=0, column=0, padx=(0, 6))
	path_var = tk.StringVar()
	path_box = ttk.Combobox(top, textvariable=path_var, values=[])
	path_box.grid(row=0, column=1, sticky="ew")

	# --- table -------------------------------------------------------------
	middle = ttk.Frame(root, padding=(10, 4))
	middle.grid(row=1, column=0, sticky="nsew")
	middle.columnconfigure(0, weight=1)
	middle.rowconfigure(0, weight=1)
	table = ttk.Treeview(middle, columns=("host", "ip"), show="headings", selectmode="extended")
	table.heading("host", text="Hostname the game dials")
	table.heading("ip", text="Redirect to")
	table.column("host", width=430, anchor="w")
	table.column("ip", width=180, anchor="w")
	table.grid(row=0, column=0, sticky="nsew")
	bar = ttk.Scrollbar(middle, orient="vertical", command=table.yview)
	bar.grid(row=0, column=1, sticky="ns")
	table.configure(yscrollcommand=bar.set)
	table.tag_configure("bad", foreground="#b00020")
	table.tag_configure("warn", foreground="#8a6d00")

	status = tk.StringVar(value="")
	preview = tk.StringVar(value="")

	def entries_now() -> list[Entry]:
		return [Entry(*table.item(row, "values")) for row in table.get_children()]

	def mark_dirty(dirty: bool = True) -> None:
		state["dirty"] = dirty
		refresh_status()

	def refresh_status() -> None:
		items = entries_now()
		value = format_value(items)
		preview.set(value or "(empty — RPCS3 will do no redirecting)")
		problems = [f"row {i + 1}: {p}" for i, e in enumerate(items) if (p := e.problem())]
		non_ip = [e.host for e in items if not e.problem() and not e.is_ipv4()]
		bits = [f"{len(items)} entr{'y' if len(items) == 1 else 'ies'}"]
		if state["dirty"]:
			bits.append("unsaved changes")
		if problems:
			bits.append("; ".join(problems))
		elif non_ip:
			bits.append(f"not an IPv4 address: {', '.join(non_ip)}")
		status.set(" — ".join(bits))
		for index, row in enumerate(table.get_children()):
			entry = items[index]
			tag = "bad" if entry.problem() else ("warn" if not entry.is_ipv4() else "")
			table.item(row, tags=(tag,) if tag else ())

	def load(path: Path) -> None:
		try:
			_, _, items = read_config(path)
		except LookupError:
			messagebox.showerror("No setting", f"{path}\n\nhas no '{KEY}:' line.\n\n"
				"Launch the game once in RPCS3 so it writes a full config, or pick another file.")
			return
		except OSError as exc:
			messagebox.showerror("Cannot read", str(exc))
			return
		state["path"] = path
		path_var.set(str(path))
		table.delete(*table.get_children())
		for entry in items:
			table.insert("", "end", values=(entry.host, entry.ip))
		mark_dirty(False)

	def choose() -> None:
		picked = filedialog.askopenfilename(
			title="Pick an RPCS3 config.yml",
			filetypes=[("RPCS3 config", "*.yml"), ("All files", "*.*")],
			initialdir=str(state["path"].parent) if state["path"] else str(Path.home()),
		)
		if picked:
			load(Path(picked))

	ttk.Button(top, text="Browse…", command=choose).grid(row=0, column=2, padx=(6, 0))
	path_box.bind("<<ComboboxSelected>>", lambda _e: load(to_local_path(path_var.get())))

	# --- inline cell editing ----------------------------------------------
	def edit_cell(event: object) -> None:
		row = table.identify_row(event.y)
		column = table.identify_column(event.x)
		if not row or column not in ("#1", "#2"):
			return
		x, y, width, height = table.bbox(row, column)
		index = 0 if column == "#1" else 1
		editor = ttk.Entry(table)
		editor.insert(0, table.item(row, "values")[index])
		editor.select_range(0, "end")
		editor.place(x=x, y=y, width=width, height=height)
		editor.focus_set()

		def commit(_event: object = None) -> None:
			values = list(table.item(row, "values"))
			if values[index] != editor.get().strip():
				values[index] = editor.get().strip()
				table.item(row, values=values)
				mark_dirty()
			editor.destroy()

		editor.bind("<Return>", commit)
		editor.bind("<FocusOut>", commit)
		editor.bind("<Escape>", lambda _e: editor.destroy())

	table.bind("<Double-1>", edit_cell)

	# --- buttons -----------------------------------------------------------
	def add_row() -> None:
		row = table.insert("", "end", values=("hostname.example.com", "192.168.1.200"))
		table.selection_set(row)
		table.see(row)
		mark_dirty()

	def remove_rows() -> None:
		for row in table.selection():
			table.delete(row)
		mark_dirty()

	def add_mgo2() -> None:
		known = {e.host for e in entries_now()}
		target = bulk_var.get().strip() or "192.168.1.200"
		for host in MGO2_HOSTS:
			if host not in known:
				table.insert("", "end", values=(host, target))
		mark_dirty()

	def apply_bulk() -> None:
		target = bulk_var.get().strip()
		if not target:
			return
		rows = table.selection() or table.get_children()
		for row in rows:
			table.item(row, values=(table.item(row, "values")[0], target))
		mark_dirty()

	def save() -> None:
		path = state["path"]
		if not path:
			messagebox.showinfo("Nothing loaded", "Open a config file first.")
			return
		items = entries_now()
		problems = [p for e in items if (p := e.problem())]
		if problems:
			messagebox.showerror("Fix these first", "\n".join(problems))
			return
		try:
			backup = write_config(Path(path), items)
		except OSError as exc:
			messagebox.showerror("Cannot write", str(exc))
			return
		mark_dirty(False)
		status.set(f"Saved {path} — backup at {backup.name}. "
			"Close RPCS3 before saving, or it will overwrite this on exit.")

	buttons = ttk.Frame(root, padding=(10, 4))
	buttons.grid(row=2, column=0, sticky="ew")
	ttk.Button(buttons, text="Add", command=add_row).pack(side="left")
	ttk.Button(buttons, text="Remove", command=remove_rows).pack(side="left", padx=4)
	ttk.Button(buttons, text="Add MGO2 hosts", command=add_mgo2).pack(side="left", padx=(4, 12))
	ttk.Label(buttons, text="Set IP:").pack(side="left")
	bulk_var = tk.StringVar(value="192.168.1.200")
	ttk.Entry(buttons, textvariable=bulk_var, width=18).pack(side="left", padx=4)
	ttk.Button(buttons, text="Apply to selected/all", command=apply_bulk).pack(side="left")
	ttk.Button(buttons, text="Save", command=save).pack(side="right")
	ttk.Button(buttons, text="Reload", command=lambda: state["path"] and load(Path(state["path"]))
		).pack(side="right", padx=6)

	bottom = ttk.Frame(root, padding=(10, 0, 10, 10))
	bottom.grid(row=3, column=0, sticky="ew")
	bottom.columnconfigure(0, weight=1)
	ttk.Label(bottom, textvariable=status, wraplength=720, justify="left").grid(
		row=0, column=0, sticky="w")
	value_box = ttk.Entry(bottom, textvariable=preview, state="readonly")
	value_box.grid(row=1, column=0, sticky="ew", pady=(6, 0))

	found = candidate_configs(initial)
	path_box.configure(values=[str(p) for p in found])
	if initial and initial.is_file():
		load(initial)
	elif found:
		load(found[0])
	else:
		status.set("No RPCS3 config found — use Browse… to pick one.")

	def on_close() -> None:
		if state["dirty"] and not messagebox.askokcancel("Unsaved changes", "Discard them?"):
			return
		root.destroy()

	root.protocol("WM_DELETE_WINDOW", on_close)
	root.mainloop()
	return 0


# ---------------------------------------------------------------------------
# CLI (also the fallback when tkinter is missing)
# ---------------------------------------------------------------------------

def run_cli(args: argparse.Namespace) -> int:
	hint = to_local_path(args.config) if args.config else None
	if hint and hint.is_file():
		path = hint
	else:
		found = candidate_configs(hint)
		if not found:
			print("No RPCS3 config with an 'IP swap list' line found. Pass one with --config.",
				file=sys.stderr)
			return 2
		if args.find:
			for candidate in found:
				print(candidate)
			return 0
		path = found[0]

	try:
		_, _, entries = read_config(path)
	except LookupError:
		print(f"{path} has no '{KEY}:' line. Launch the game once in RPCS3 so it writes a full "
			"config, or point at another file.", file=sys.stderr)
		return 2
	if args.find:
		print(path)
		return 0

	if args.set_ip:
		hosts = args.host or [e.host for e in entries] or list(MGO2_HOSTS)
		by_host = {e.host: e for e in entries}
		for host in hosts:
			by_host[host] = Entry(host, args.set_ip)
		entries = list(by_host.values())
		problems = [p for e in entries if (p := e.problem())]
		if problems:
			print("\n".join(problems), file=sys.stderr)
			return 2
		if args.dry_run:
			print(format_value(entries))
			return 0
		backup = write_config(path, entries)
		print(f"Wrote {path} (backup {backup.name})")

	_, _, entries = read_config(path)
	print(f"{path}")
	for entry in entries:
		note = "" if entry.is_ipv4() else "   <- not an IPv4 address"
		print(f"  {entry.host} = {entry.ip}{note}")
	return 0


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(
		description="Edit RPCS3's 'IP swap list' (the MGO2 host redirects).",
		epilog="These redirects are an RPCS3 setting in plain YAML, not data inside MGO2.SELF, "
			"so no decryption is involved. Close RPCS3 before saving: it rewrites its config "
			"on exit and will clobber your edit.")
	parser.add_argument("config", nargs="?",
		help="a config.yml, or an RPCS3 install directory (Windows paths work under WSL)")
	parser.add_argument("--no-gui", action="store_true", help="stay on the command line")
	parser.add_argument("--find", action="store_true", help="list configs carrying the setting")
	parser.add_argument("--set-ip", metavar="IP", help="point hosts at this address")
	parser.add_argument("--host", action="append", metavar="HOST",
		help="host to set (repeatable; default: every host already listed)")
	parser.add_argument("--dry-run", action="store_true", help="print the new value, write nothing")
	args = parser.parse_args(argv)

	if args.no_gui or args.find or args.set_ip:
		return run_cli(args)
	try:
		import tkinter  # noqa: F401
	except ImportError:
		print("tkinter is not installed, falling back to the command line.\n"
			"  Debian/Ubuntu: sudo apt install python3-tk\n"
			"  Windows/macOS: bundled with python.org builds\n", file=sys.stderr)
		return run_cli(args)
	return run_gui(to_local_path(args.config) if args.config else None)


if __name__ == "__main__":
	sys.exit(main())
