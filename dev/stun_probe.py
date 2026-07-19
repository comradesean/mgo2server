"""A minimal STUN responder, enough for a console to discover its public address.

MGO2 is peer-to-peer for actual matches, so the client performs NAT discovery before it will
enter a lobby. With no STUN server reachable it retries UPnP and then gives up, which looks like
a lobby problem but is not one.

This implements just the classic STUN Binding Request/Response (RFC 3489, which is what a 2008
console speaks) plus the RFC 5389 XOR-MAPPED-ADDRESS attribute, and reports the source address of
whatever asked. It is a development aid, not a general STUN implementation: no authentication, no
CHANGE-REQUEST handling, no RFC 5780 behaviour discovery.
"""
import socket
import struct
import sys

BIND_REQUEST = 0x0001
BIND_RESPONSE = 0x0101

ATTR_MAPPED_ADDRESS = 0x0001
ATTR_XOR_MAPPED_ADDRESS = 0x0020
ATTR_SOURCE_ADDRESS = 0x0004

MAGIC_COOKIE = 0x2112A442
FAMILY_IPV4 = 0x01


def attribute(kind: int, value: bytes) -> bytes:
    padding = (4 - len(value) % 4) % 4
    return struct.pack("!HH", kind, len(value)) + value + b"\x00" * padding


def address_value(ip: str, port: int) -> bytes:
    return struct.pack("!BBH", 0, FAMILY_IPV4, port) + socket.inet_aton(ip)


def xor_address_value(ip: str, port: int) -> bytes:
    xor_port = port ^ (MAGIC_COOKIE >> 16)
    raw = struct.unpack("!I", socket.inet_aton(ip))[0] ^ MAGIC_COOKIE
    return struct.pack("!BBH", 0, FAMILY_IPV4, xor_port) + struct.pack("!I", raw)


def serve(port: int, advertised_ip: str) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", port))
    print(f"STUN responder listening on 0.0.0.0:{port}", flush=True)

    while True:
        try:
            data, peer = sock.recvfrom(2048)
        except OSError as e:
            print(f"  recv failed: {e}", flush=True)
            continue

        if len(data) < 20:
            continue

        kind, length, transaction = struct.unpack("!HH16s", data[:20])
        print(f"  {peer[0]}:{peer[1]} type=0x{kind:04x} len={length}", flush=True)

        if kind != BIND_REQUEST:
            continue

        # Report where the request appeared to come from; that is the whole point of STUN.
        body = (
            attribute(ATTR_MAPPED_ADDRESS, address_value(peer[0], peer[1]))
            + attribute(ATTR_XOR_MAPPED_ADDRESS, xor_address_value(peer[0], peer[1]))
            + attribute(ATTR_SOURCE_ADDRESS, address_value(advertised_ip, port))
        )
        response = struct.pack("!HH16s", BIND_RESPONSE, len(body), transaction) + body

        sock.sendto(response, peer)
        print(f"      -> mapped {peer[0]}:{peer[1]}", flush=True)


if __name__ == "__main__":
    serve(
        int(sys.argv[1]) if len(sys.argv) > 1 else 3478,
        sys.argv[2] if len(sys.argv) > 2 else "0.0.0.0",
    )
