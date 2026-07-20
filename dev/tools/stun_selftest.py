"""Checks a running stun_probe.py against the reply format dev/docs/STUN.md documents.

Run it with the responder up:  python3 dev/tools/stun_selftest.py

Every assertion here corresponds to a claim in dev/docs/STUN.md, so if the responder is changed in a
way that breaks the client, this says which claim broke rather than leaving a game hanging on
"Adjusting port settings" as the only symptom.

Known limitation: the CHANGE-REQUEST leg cannot be verified from inside WSL. The responder does
answer it -- its log shows the send, and the real client both receives it and passes the port
check -- but WSL's mirrored networking does not loop a packet from the secondary address back to a
WSL-local socket, so this script would time out waiting for a reply that reached the emulator
fine. That leg is checked by reading the responder log instead, which this script prints a hint
for. Run from a genuinely separate host to cover it properly.
"""
import socket, struct, os

PRIMARY, SECONDARY = "192.168.1.100", "192.168.1.201"
P1, P2 = 3478, 3479
BIND_REQUEST, BIND_RESPONSE = 0x0001, 0x0101

def parse(data):
    kind, length, txid = struct.unpack("!HH16s", data[:20])
    attrs, off, end = [], 20, 20 + length
    while off + 4 <= end:
        t, sz = struct.unpack("!HH", data[off:off+4])
        attrs.append((t, data[off+4:off+4+sz]))
        off += 4 + sz + ((4 - sz % 4) % 4)
    return kind, txid, attrs

def addr_of(v):
    port = struct.unpack("!H", v[2:4])[0]
    return socket.inet_ntoa(v[4:8]), port

def xor_addr_of(v, txid):
    k32 = struct.unpack("!I", txid[:4])[0]
    k16 = struct.unpack("!H", txid[:2])[0]
    port = struct.unpack("!H", v[2:4])[0] ^ k16
    raw = struct.unpack("!I", v[4:8])[0] ^ k32
    return socket.inet_ntoa(struct.pack("!I", raw)), port

def probe(dst_ip, dst_port, change=None, timeout=3):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout); s.bind(("0.0.0.0", 0))
    txid = os.urandom(16)
    body = b""
    if change is not None:
        body = struct.pack("!HH", 0x0003, 4) + struct.pack("!I", change)
    s.sendto(struct.pack("!HH16s", BIND_REQUEST, len(body), txid) + body, (dst_ip, dst_port))
    data, peer = s.recvfrom(2048)
    s.close()
    return txid, data, peer

ok = fail = 0
def check(label, cond, detail=""):
    global ok, fail
    print(f"  [{'PASS' if cond else 'FAIL'}] {label}{(' — ' + detail) if detail else ''}")
    if cond: ok += 1
    else: fail += 1

print("=== Test I: basic binding request to primary ===")
txid, data, peer = probe(PRIMARY, P1)
kind, rtx, attrs = parse(data)
types = [t for t, _ in attrs]
check("reply is a Binding Response", kind == BIND_RESPONSE, hex(kind))
check("transaction id echoed", rtx == txid)
check("answered from the address asked", peer == (PRIMARY, P1), str(peer))
check("four attributes", len(attrs) == 4, f"got {len(attrs)}: {[hex(t) for t in types]}")
check("MAPPED-ADDRESS 0x0001 present", 0x0001 in types)
check("SOURCE-ADDRESS 0x0004 present", 0x0004 in types)
check("CHANGED-ADDRESS 0x0005 present", 0x0005 in types)
check("XOR-MAPPED tagged 0x8020 (not 0x0020)", 0x8020 in types and 0x0020 not in types)
check("no 0xf000 vendor echoed back", 0xf000 not in types)

amap = dict(attrs)
mapped = addr_of(amap[0x0001])
src = addr_of(amap[0x0004])
chg = addr_of(amap[0x0005])
xm = xor_addr_of(amap[0x8020], txid)
print(f"     mapped={mapped} source={src} changed={chg} xor-mapped={xm}")
check("XOR-MAPPED decodes to MAPPED using transaction id", xm == mapped, f"{xm} vs {mapped}")
check("SOURCE-ADDRESS is where it replied from", src == (PRIMARY, P1), str(src))
check("CHANGED-ADDRESS points at the other ip:port", chg == (SECONDARY, P2), str(chg))

print("=== Test II: CHANGE-REQUEST change-ip+port (0x06), as the client sends ===")
try:
    txid2, data2, peer2 = probe(PRIMARY, P1, change=0x06)
    kind2, rtx2, attrs2 = parse(data2)
    a2 = dict(attrs2)
    check("answered from the OTHER ip and port", peer2 == (SECONDARY, P2), str(peer2))
    check("transaction id echoed", rtx2 == txid2)
    check("SOURCE-ADDRESS matches who actually replied",
          addr_of(a2[0x0004]) == (SECONDARY, P2), str(addr_of(a2[0x0004])))
    check("mapped port preserved across both tests",
          addr_of(a2[0x0001])[1] == mapped[1], f"{addr_of(a2[0x0001])[1]} vs {mapped[1]}")
except socket.timeout:
    print("  [SKIP] no reply seen — expected when running inside WSL; see the module docstring.")
    print("         Verify by hand instead:")
    print("           docker logs nomad-ng-probe-stun-1 | grep -A1 CHANGE-REQUEST")
    print("         The line after the request must read '-> 192.168.1.201:3479'.")

print("=== keepalive: zero-length request ===")
try:
    txid3, data3, peer3 = probe(PRIMARY, P1)
    k3, _, _ = parse(data3)
    check("empty request still answered", k3 == BIND_RESPONSE)
except socket.timeout:
    check("empty request still answered", False, "timed out")

print(f"\n{ok} passed, {fail} failed")
