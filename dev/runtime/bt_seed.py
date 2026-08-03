"""BitTorrent tracker + seeding peer for the auto-patch P2P path.

Stub-test harness, same spirit as http_probe.py -- proves the .torrent/tracker/peer-wire protocol
paths a real client exercises actually work end to end, seeding the same placeholder payload
bytes build_inf_stub.py already wrote (not real Konami patch content). See
dev/docs/PATCH_INVESTIGATION.md Sec 0 for how this fits into the rest of the stub.

The client statically links real Transmission (ADDRESSES.md Sec 12), so this has to speak
genuine BEP3 -- a stub reply doesn't work here the way `\\x00` worked for checkver.html.

Two independent servers in one process:
  - HTTP tracker on TRACKER_PORT: GET /announce -> bencoded compact peer list (just us, the one
    seed this stub has).
  - Raw TCP BitTorrent peer-wire protocol on PEER_PORT: handshake, bitfield (we have everything),
    unchoke on interest, serve whatever piece/block is requested.

No third-party dependencies: build_torrent.py (imported for the bencode encoder and the
info dict/info_hash/piece-data computation, so this seed is provably describing the exact same
torrent build_torrent.py wrote to disk) needs none, and neither does this.
"""
import pathlib
import socket
import struct
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "tools"))
import build_torrent as torrentlib  # noqa: E402
import build_checkver as checkver  # noqa: E402

ADVERTISE_IP = checkver.HOST.split("://", 1)[1].split(":")[0]

FILES = torrentlib.stub_files()
INFO, INFO_HASH, PIECE_DATA = torrentlib.build_torrent_info(FILES)
PIECE_LENGTH = torrentlib.PIECE_LENGTH
TOTAL_LEN = len(PIECE_DATA)
NUM_PIECES = max(1, (TOTAL_LEN + PIECE_LENGTH - 1) // PIECE_LENGTH)

PEER_ID = b"-MG0200-stubseedpeer"[:20].ljust(20, b"0")
assert len(PEER_ID) == 20

print(f"seeding info_hash {INFO_HASH.hex()}, {TOTAL_LEN} bytes across {NUM_PIECES} piece(s), "
      f"files: {[n for n, _ in FILES]}", flush=True)


# ---- Tracker: BEP3 HTTP announce ----

class Tracker(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        # Log every request, not just ones that match /announce -- a silent 404 here would be
        # the exact same blind spot http_probe.py's missing do_HEAD was (see its docstring):
        # if the real client requests something other than what we expect, this print is the
        # only way to ever find out.
        print(f"  GET {self.path} from {self.client_address[0]} "
              f"(User-Agent: {self.headers.get('User-Agent', '?')})", flush=True)
        if parsed.path != "/announce":
            self.send_response(404)
            self.end_headers()
            return

        # info_hash's 20 raw bytes are not valid UTF-8 in general, and parse_qs defaults to a
        # UTF-8 decode that would silently mangle them (replacement chars, merged bytes).
        # latin-1 is a lossless byte<->codepoint mapping, so decoding with it here and
        # re-encoding below exactly recovers the original bytes.
        params = parse_qs(parsed.query, encoding="latin-1")
        raw_hash = params.get("info_hash", [""])[0]
        info_hash = raw_hash.encode("latin-1") if raw_hash else b""
        peer_id = params.get("peer_id", [""])[0]
        event = params.get("event", [""])[0]
        print(f"  announce from {self.client_address[0]}: "
              f"info_hash={info_hash.hex() if info_hash else '?'} "
              f"peer_id={peer_id!r} event={event!r}", flush=True)

        if info_hash != INFO_HASH:
            body = torrentlib.bencode({"failure reason": "unknown torrent"})
        else:
            # Compact peer list (BEP23): 4-byte IP + 2-byte port, network byte order, per peer.
            # We are the only seed this stub has.
            peer_bytes = socket.inet_aton(ADVERTISE_IP) + struct.pack(">H", torrentlib.PEER_PORT)
            body = torrentlib.bencode({"interval": 60, "peers": peer_bytes})

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_HEAD(self):
        print(f"  HEAD {self.path} from {self.client_address[0]}", flush=True)
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        print(f"  POST {self.path} from {self.client_address[0]}", flush=True)
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass  # replaced by the explicit print() above


# ---- Peer-wire protocol (BEP3), seed-only: we never request, only serve ----

PROTOCOL_NAME = b"BitTorrent protocol"
MSG_CHOKE, MSG_UNCHOKE, MSG_INTERESTED, MSG_NOT_INTERESTED = 0, 1, 2, 3
MSG_HAVE, MSG_BITFIELD, MSG_REQUEST, MSG_PIECE, MSG_CANCEL = 4, 5, 6, 7, 8


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def send_message(conn, msg_id, payload=b""):
    conn.sendall(struct.pack(">IB", len(payload) + 1, msg_id) + payload)


def read_message(conn):
    """Returns (msg_id, payload), msg_id=-1 for a keep-alive, or None on disconnect."""
    header = recv_exact(conn, 4)
    if header is None:
        return None
    length = struct.unpack(">I", header)[0]
    if length == 0:
        return (-1, b"")
    body = recv_exact(conn, length)
    if body is None:
        return None
    return (body[0], body[1:])


def handle_peer(conn, addr):
    print(f"peer connected: {addr}", flush=True)
    try:
        handshake = recv_exact(conn, 68)
        if handshake is None or handshake[0] != 19 or handshake[1:20] != PROTOCOL_NAME:
            print(f"  bad handshake from {addr}", flush=True)
            return
        their_info_hash = handshake[28:48]
        if their_info_hash != INFO_HASH:
            print(f"  info_hash mismatch from {addr}: {their_info_hash.hex()}", flush=True)
            return

        # Reserved bytes all zero: no extension protocol, no DHT, no fast extension -- the
        # simplest baseline, least likely to trigger a code path we haven't implemented.
        conn.sendall(bytes([19]) + PROTOCOL_NAME + b"\x00" * 8 + INFO_HASH + PEER_ID)

        bitfield_len = (NUM_PIECES + 7) // 8
        bitfield = bytearray(bitfield_len)
        for i in range(NUM_PIECES):
            bitfield[i // 8] |= 0x80 >> (i % 8)
        send_message(conn, MSG_BITFIELD, bytes(bitfield))

        choked = True
        while True:
            msg = read_message(conn)
            if msg is None:
                break
            msg_id, payload = msg
            if msg_id == MSG_INTERESTED:
                choked = False
                send_message(conn, MSG_UNCHOKE)
            elif msg_id == MSG_NOT_INTERESTED:
                choked = True
            elif msg_id == MSG_REQUEST and not choked and len(payload) >= 12:
                index, begin, length = struct.unpack(">III", payload[:12])
                start = index * PIECE_LENGTH + begin
                block = PIECE_DATA[start:start + length]
                send_message(conn, MSG_PIECE, struct.pack(">II", index, begin) + block)
                print(f"  served piece {index} offset {begin} len {len(block)} to {addr}",
                      flush=True)
            # keep-alives, CANCEL, and anything else: no action needed for a seed-only stub
    except (ConnectionResetError, BrokenPipeError, OSError) as exc:
        print(f"  peer {addr} error: {exc}", flush=True)
    finally:
        conn.close()
        print(f"peer disconnected: {addr}", flush=True)


def run_peer_server():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", torrentlib.PEER_PORT))
    srv.listen(8)
    print(f"peer-wire server listening on 0.0.0.0:{torrentlib.PEER_PORT}", flush=True)
    while True:
        conn, addr = srv.accept()
        threading.Thread(target=handle_peer, args=(conn, addr), daemon=True).start()


class LoggingTrackerServer(ThreadingHTTPServer):
    """Logs every accepted TCP connection before any HTTP parsing happens. Without this, a
    connection that's accepted but never sends a valid HTTP request line (or is closed before
    one arrives) is invisible -- do_GET only runs after BaseHTTPRequestHandler successfully
    parses a request, same blind spot http_probe.py's missing do_HEAD used to be."""

    def get_request(self):
        conn, addr = super().get_request()
        print(f"accepted connection from {addr[0]}:{addr[1]}", flush=True)
        return conn, addr


def main():
    threading.Thread(target=run_peer_server, daemon=True).start()
    tracker = LoggingTrackerServer(("0.0.0.0", torrentlib.TRACKER_PORT), Tracker)
    print(f"tracker listening on 0.0.0.0:{torrentlib.TRACKER_PORT}", flush=True)
    tracker.serve_forever()


if __name__ == "__main__":
    main()
