"""A STUN responder with enough RFC 3489 behaviour for a console to classify its NAT.

MGO2 is peer-to-peer for matches, so the client runs NAT discovery before it will enter a lobby.
That is not a single binding request: the client sends CHANGE-REQUEST attributes asking the server
to reply from a different address or port, and infers its NAT type from which replies arrive.

NAT classification fundamentally needs two IP addresses: the client asks the server to reply from
a different address and infers its NAT type from whether that reply arrives. SaveMGO ran its STUN
server on a different address from its gate for this reason.

Pass a second address to serve the four-socket layout properly. With one address it falls back to
answering change-IP from the alternate port, which lets the client conclude something rather than
hang, but cannot distinguish a full-cone NAT from a symmetric one.

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
# The real MGO2 STUN server (captured from mgo2pc) tags this attribute 0x8020, not the
# RFC-5389 0x0020, and XORs against the request's transaction id rather than a magic cookie.
ATTR_XOR_MAPPED_ADDRESS = 0x8020

CHANGE_IP = 0x04
CHANGE_PORT = 0x02

MAGIC_COOKIE = 0x2112A442
FAMILY_IPV4 = 0x01


def attribute(kind, value):
    padding = (4 - len(value) % 4) % 4
    return struct.pack("!HH", kind, len(value)) + value + b"\x00" * padding


def address_value(ip, port):
    return struct.pack("!BBH", 0, FAMILY_IPV4, port) + socket.inet_aton(ip)


def xor_address_value(ip, port, transaction):
    # Decoded from the real server's capture: key is the request transaction id, not the
    # RFC-5389 magic cookie. port ^ txid[0:2], ip ^ txid[0:4], both big-endian.
    key32 = struct.unpack("!I", transaction[:4])[0]
    key16 = struct.unpack("!H", transaction[:2])[0]
    xor_port = port ^ key16
    raw = struct.unpack("!I", socket.inet_aton(ip))[0] ^ key32
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


def serve(primary_port, advertised_ip, secondary_ip=None,
          include_changed=True, include_xor=False, echo_vendor=False):
    alternate_port = primary_port + 1
    two_addresses = secondary_ip is not None and secondary_ip != advertised_ip

    # (ip, port) -> socket. With one address only the two ports differ.
    addresses = [advertised_ip] if not two_addresses else [advertised_ip, secondary_ip]

    sockets = {}
    for ip in addresses:
        for port in (primary_port, alternate_port):
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((ip if two_addresses else "0.0.0.0", port))
            sockets[(ip, port)] = s

    selector = selectors.DefaultSelector()
    for key, s in sockets.items():
        selector.register(s, selectors.EVENT_READ, key)

    if two_addresses:
        print(f"STUN responder on {advertised_ip} and {secondary_ip}, "
              f"ports {primary_port} and {alternate_port}", flush=True)
    else:
        print(f"STUN responder on {advertised_ip}, ports {primary_port} and {alternate_port} "
              f"(single address: change-IP answered from the alternate port)", flush=True)

    while True:
        for key, _ in selector.select():
            received_ip, received_on = key.data
            try:
                data, peer = sockets[(received_ip, received_on)].recvfrom(2048)
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
            vendor = []
            for attr_type, value in parse_attributes(data, length):
                names.append(describe(attr_type))
                if attr_type == ATTR_CHANGE_REQUEST and len(value) >= 4:
                    change_flags = struct.unpack("!I", value[:4])[0]
                elif attr_type >= 0x8000 or attr_type == 0xf000:
                    # Konami sends 0xf000 on the game's own probes but not on the plain ones.
                    # Recorded only; echoing it back is off by default and must stay that way.
                    # See echo_vendor below for why.
                    vendor.append((attr_type, value))
                    print(f"      vendor 0x{attr_type:04x} = {value.hex()}", flush=True)

            wants_ip = bool(change_flags & CHANGE_IP)
            wants_port = bool(change_flags & CHANGE_PORT)
            print(f"  {received_ip}:{received_on} <- {peer[0]}:{peer[1]} len={length} "
                  f"attrs=[{', '.join(names) or 'none'}] "
                  f"change_ip={wants_ip} change_port={wants_port}", flush=True)

            reply_port = alternate_port if wants_port else received_on
            if two_addresses:
                # The real thing: reply from the other address when asked to.
                reply_ip = secondary_ip if wants_ip and received_ip == advertised_ip else (
                    advertised_ip if wants_ip else received_ip)
            else:
                # One address only. Answer change-IP from the alternate port so the client can
                # conclude rather than retry until it fails.
                reply_ip = received_ip
                if wants_ip:
                    reply_port = alternate_port

            other_ip = secondary_ip if (two_addresses and reply_ip == advertised_ip) else advertised_ip
            other_port = alternate_port if reply_port == primary_port else primary_port

            # A capture of the real MGO2 server (mgo2pc, BLUS30109 client) settles the reply
            # shape: a Binding Response carries FOUR attributes, in this order, and the client
            # accepts all of them and passes NAT classification:
            #
            #   0x0001 MAPPED-ADDRESS      the client's public ip:port  (port PRESERVED)
            #   0x0004 SOURCE-ADDRESS      the responding server's own ip:port
            #   0x0005 CHANGED-ADDRESS     the *other* server's ip:port
            #   0x8020 XOR-MAPPED-ADDRESS  the mapped ip:port, obfuscated
            #
            # The earlier belief that the decoder is template-driven and rejects more than two
            # attributes was wrong — the working server sends four. The decisive field is
            # MAPPED-ADDRESS: its port must equal the port the client sent from (5730). Both
            # server addresses must report the *same* mapped ip:port; that consistency across two
            # addresses is what the client reads as a full-cone NAT and passes.
            #
            # The XOR-MAPPED (0x8020) key is now reproduced from the capture: the request's
            # transaction id. Sent by default so the reply matches the real server byte-for-byte.
            body = (
                attribute(ATTR_MAPPED_ADDRESS, address_value(peer[0], peer[1]))
                + attribute(ATTR_SOURCE_ADDRESS, address_value(reply_ip, reply_port))
            )
            if include_changed:
                body += attribute(ATTR_CHANGED_ADDRESS, address_value(other_ip, other_port))
            if include_xor:
                body += attribute(ATTR_XOR_MAPPED_ADDRESS,
                                  xor_address_value(peer[0], peer[1], transaction))
            if echo_vendor:
                body += b"".join(attribute(kind, value) for kind, value in vendor)
            response = struct.pack("!HH16s", BIND_RESPONSE, len(body), transaction) + body

            sockets[(reply_ip, reply_port)].sendto(response, peer)
            print(f"      -> {reply_ip}:{reply_port} mapped {peer[0]}:{peer[1]}", flush=True)


if __name__ == "__main__":
    # Flags exist so the reply shape can be bisected against a real client without edits.
    #
    # echo_vendor defaults OFF, and that default is load-bearing rather than cosmetic. The
    # client's own DecodePacket dispatches on the 0xf000 vendor attribute's sub-type: 1 and 3
    # have handlers, and anything else falls through to a logging stub followed by an infinite
    # branch. The client sends sub-types the server must not parrot -- an observed first probe
    # carried 0xf000 = 0573000000000002 -- so echoing its own attribute back hands the decoder
    # the value that spins it forever. That is what left the game sitting on "Adjusting port
    # settings" with no error and no timeout.
    #
    # With no vendor attribute in the reply the client runs the full NAT classification,
    # including the change-request leg answered from the alternate address, and the port check
    # passes. This also matches coturn, which the one reference server that works online uses
    # and which has no notion of Konami vendor attributes. --echo-vendor exists only to
    # reproduce the hang deliberately.
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    positional = [a for a in sys.argv[1:] if not a.startswith("--")]
    serve(
        int(positional[0]) if len(positional) > 0 else 3478,
        positional[1] if len(positional) > 1 else "0.0.0.0",
        positional[2] if len(positional) > 2 else None,
        include_changed="--no-changed" not in flags,
        include_xor="--no-xor" not in flags,
        echo_vendor="--echo-vendor" in flags,
    )
