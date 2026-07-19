"""A STUN responder with enough RFC 3489 behaviour for a console to classify its NAT.

MGO2 is peer-to-peer for matches, so the client runs NAT discovery before it will enter a lobby.
That is not a single binding request: the client sends CHANGE-REQUEST attributes asking the server
to reply from a different address or port, and infers its NAT type from which replies arrive.

A textbook implementation needs two IP addresses. This has one, so it serves two ports and answers
the change-port case honestly and the change-IP case not at all — which is what a real server with
a single interface would do. Enough for the client to reach a conclusion rather than hang.

Development aid only: no authentication, no RFC 5780 behaviour discovery, no fingerprinting.
"""
import selectors
import socket
import struct
import sys

BIND_REQUEST = 0x0001
BIND_RESPONSE = 0x0101

ATTR_MAPPED_ADDRESS = 0x0001
ATTR_RESPONSE_ADDRESS = 0x0002
ATTR_CHANGE_REQUEST = 0x0003
ATTR_SOURCE_ADDRESS = 0x0004
ATTR_CHANGED_ADDRESS = 0x0005
ATTR_XOR_MAPPED_ADDRESS = 0x0020

CHANGE_IP = 0x04
CHANGE_PORT = 0x02

MAGIC_COOKIE = 0x2112A442
FAMILY_IPV4 = 0x01


def attribute(kind, value):
    padding = (4 - len(value) % 4) % 4
    return struct.pack("!HH", kind, len(value)) + value + b"\x00" * padding


def address_value(ip, port):
    return struct.pack("!BBH", 0, FAMILY_IPV4, port) + socket.inet_aton(ip)


def xor_address_value(ip, port):
    xor_port = port ^ (MAGIC_COOKIE >> 16)
    raw = struct.unpack("!I", socket.inet_aton(ip))[0] ^ MAGIC_COOKIE
    return struct.pack("!BBH", 0, FAMILY_IPV4, xor_port) + struct.pack("!I", raw)


def parse_attributes(data, length):
    """Yields (type, value) from the attribute section."""
    offset, end = 20, 20 + length
    while offset + 4 <= end and offset + 4 <= len(data):
        kind, size = struct.unpack("!HH", data[offset:offset + 4])
        value = data[offset + 4:offset + 4 + size]
        yield kind, value
        offset += 4 + size + ((4 - size % 4) % 4)


def describe(kind):
    return {
        ATTR_MAPPED_ADDRESS: "MAPPED-ADDRESS",
        ATTR_RESPONSE_ADDRESS: "RESPONSE-ADDRESS",
        ATTR_CHANGE_REQUEST: "CHANGE-REQUEST",
        ATTR_SOURCE_ADDRESS: "SOURCE-ADDRESS",
        ATTR_CHANGED_ADDRESS: "CHANGED-ADDRESS",
        ATTR_XOR_MAPPED_ADDRESS: "XOR-MAPPED-ADDRESS",
    }.get(kind, f"0x{kind:04x}")


def serve(primary_port, advertised_ip):
    alternate_port = primary_port + 1

    sockets = {}
    for port in (primary_port, alternate_port):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("0.0.0.0", port))
        sockets[port] = s

    selector = selectors.DefaultSelector()
    for port, s in sockets.items():
        selector.register(s, selectors.EVENT_READ, port)

    print(f"STUN responder on {primary_port} and {alternate_port} (advertising {advertised_ip})",
          flush=True)

    while True:
        for key, _ in selector.select():
            received_on = key.data
            try:
                data, peer = sockets[received_on].recvfrom(2048)
            except OSError as e:
                print(f"  recv failed: {e}", flush=True)
                continue

            if len(data) < 20:
                continue

            kind, length, transaction = struct.unpack("!HH16s", data[:20])
            if kind != BIND_REQUEST:
                continue

            change_flags = 0
            names = []
            for attr_type, value in parse_attributes(data, length):
                names.append(describe(attr_type))
                if attr_type == ATTR_CHANGE_REQUEST and len(value) >= 4:
                    change_flags = struct.unpack("!I", value[:4])[0]

            wants_ip = bool(change_flags & CHANGE_IP)
            wants_port = bool(change_flags & CHANGE_PORT)
            print(f"  :{received_on} <- {peer[0]}:{peer[1]} len={length} "
                  f"attrs=[{', '.join(names) or 'none'}] "
                  f"change_ip={wants_ip} change_port={wants_port}", flush=True)

            # Only one address is available, so a request to change IP cannot be honoured. Staying
            # silent is what a single-homed server does, and the client treats it as a result.
            if wants_ip:
                print("      no second address; not answering", flush=True)
                continue

            reply_from = alternate_port if wants_port else received_on
            other_port = alternate_port if reply_from == primary_port else primary_port

            body = (
                attribute(ATTR_MAPPED_ADDRESS, address_value(peer[0], peer[1]))
                + attribute(ATTR_SOURCE_ADDRESS, address_value(advertised_ip, reply_from))
                + attribute(ATTR_CHANGED_ADDRESS, address_value(advertised_ip, other_port))
                + attribute(ATTR_XOR_MAPPED_ADDRESS, xor_address_value(peer[0], peer[1]))
            )
            response = struct.pack("!HH16s", BIND_RESPONSE, len(body), transaction) + body

            sockets[reply_from].sendto(response, peer)
            print(f"      -> :{reply_from} mapped {peer[0]}:{peer[1]}", flush=True)


if __name__ == "__main__":
    serve(
        int(sys.argv[1]) if len(sys.argv) > 1 else 3478,
        sys.argv[2] if len(sys.argv) > 2 else "0.0.0.0",
    )
