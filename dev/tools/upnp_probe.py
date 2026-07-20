"""Listens for the game's own UPnP discovery, and optionally answers it.

MGO2 does not rely on the console for port forwarding. It carries its own IGD client — the binary
contains the string `mrdUPnP / Ver[0.0.1.00]` alongside `uupnp.cc` — and drives it directly:

    M-SEARCH -> 239.255.255.250:1900   ssdp:discover for InternetGatewayDevice
    GET <LOCATION>                     device description
    SOAP GetExternalIPAddress          on the WANIPConnection service
    SOAP AddPortMapping / DeletePortMapping

The screen that reads "Adjusting port settings" is this sequence. With no IGD answering, the
client has nothing to talk to.

Run it in listen-only mode first, to establish whether the M-SEARCH even reaches this host:

    sudo python3 dev/tools/upnp_probe.py --listen

Multicast has to cross from RPCS3 (on Windows) into WSL, which is not guaranteed. If nothing
arrives, that is the finding, and no amount of responder is going to help.

If M-SEARCH does arrive, answer it:

    sudo python3 dev/tools/upnp_probe.py --respond --ip 192.168.1.100

which replies to the discovery, serves a minimal InternetGatewayDevice description over HTTP, and
implements just enough of WANIPConnection to satisfy the calls above. Port mappings are recorded
and logged, not actually created — nothing here touches a real router.
"""
import argparse
import http.server
import re
import socket
import struct
import sys
import threading

SSDP_ADDR = "239.255.255.250"
SSDP_PORT = 1900

IGD_URN = "urn:schemas-upnp-org:device:InternetGatewayDevice:1"
WAN_URN = "urn:schemas-upnp-org:service:WANIPConnection:1"

# What MGO2 actually searches for, observed in one burst from a single source port:
#
#   urn:schemas-upnp-org:service:WANIPConnection:1
#   urn:schemas-upnp-org:service:WANPPPConnection:1
#   urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1
#   urn:schemas-upnp-org:service:InternetGatewayDevice:1
#
# Note the last one: UPnP defines InternetGatewayDevice as a *device* type, and the client asks
# for it as a *service*. A responder that matches only the spec-correct URN answers none of these
# and the client waits forever. Echo back whichever target was asked for.
SEARCH_TARGETS = {
    "urn:schemas-upnp-org:service:WANIPConnection:1",
    "urn:schemas-upnp-org:service:WANPPPConnection:1",
    "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1",
    "urn:schemas-upnp-org:service:InternetGatewayDevice:1",
    IGD_URN,
    "upnp:rootdevice",
    "ssdp:all",
}


def log(message):
    print(message, flush=True)


DESCRIPTION = """<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
 <specVersion><major>1</major><minor>0</minor></specVersion>
 <device>
  <deviceType>{igd}</deviceType>
  <friendlyName>nomad-ng test gateway</friendlyName>
  <manufacturer>nomad-ng</manufacturer>
  <modelName>probe</modelName>
  <UDN>uuid:{uuid}</UDN>
  <deviceList>
   <device>
    <deviceType>urn:schemas-upnp-org:device:WANDevice:1</deviceType>
    <friendlyName>WANDevice</friendlyName>
    <UDN>uuid:{uuid}-wan</UDN>
    <serviceList>
     <service>
      <serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
      <serviceId>urn:upnp-org:serviceId:WANCommonIFC1</serviceId>
      <controlURL>/ctl</controlURL>
      <eventSubURL>/evt</eventSubURL>
      <SCPDURL>/scpd.xml</SCPDURL>
     </service>
    </serviceList>
    <deviceList>
     <device>
      <deviceType>urn:schemas-upnp-org:device:WANConnectionDevice:1</deviceType>
      <friendlyName>WANConnectionDevice</friendlyName>
      <UDN>uuid:{uuid}-con</UDN>
      <serviceList>
       <service>
        <serviceType>{wan}</serviceType>
        <serviceId>urn:upnp-org:serviceId:WANIPConn1</serviceId>
        <controlURL>/ctl</controlURL>
        <eventSubURL>/evt</eventSubURL>
        <SCPDURL>/scpd.xml</SCPDURL>
       </service>
       <service>
        <serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:WANPPPConn1</serviceId>
        <controlURL>/ctl</controlURL>
        <eventSubURL>/evt</eventSubURL>
        <SCPDURL>/scpd.xml</SCPDURL>
       </service>
      </serviceList>
     </device>
    </deviceList>
   </device>
  </deviceList>
 </device>
</root>
"""

UUID = "6a7b8c9d-0e1f-2a3b-4c5d-6e7f8a9b0c1d"


def soap_envelope(action, body):
    return (
        '<?xml version="1.0"?>\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        f'<s:Body><u:{action}Response xmlns:u="{WAN_URN}">{body}'
        f'</u:{action}Response></s:Body></s:Envelope>'
    ).encode()


def soap_fault(code, description):
    """A real gateway answers some queries with a fault, and clients depend on it.

    Asking for a port mapping that does not exist must produce 714 NoSuchEntryInArray, not an
    empty success — that is how a control point learns the port is free before claiming it. A
    responder that returns 200 with no body leaves it unable to tell.
    """
    return (
        '<?xml version="1.0"?>\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><s:Fault><faultcode>s:Client</faultcode>'
        '<faultstring>UPnPError</faultstring><detail>'
        '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
        f'<errorCode>{code}</errorCode>'
        f'<errorDescription>{description}</errorDescription>'
        '</UPnPError></detail></s:Fault></s:Body></s:Envelope>'
    ).encode()


class Gateway(http.server.BaseHTTPRequestHandler):
    """The device description and control endpoint the SSDP reply points at."""

    external_ip = "192.168.1.100"

    def _send(self, body, content_type="text/xml; charset=\"utf-8\"", status=200):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        log(f"  UPnP GET {self.path} from {self.client_address[0]}")
        if self.path.startswith("/desc.xml"):
            self._send(DESCRIPTION.format(igd=IGD_URN, wan=WAN_URN, uuid=UUID).encode())
        else:
            self._send(b"<scpd/>")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")
        action = self.headers.get("SOAPAction", "").strip('"').rsplit("#", 1)[-1]
        log(f"  UPnP SOAP {action} from {self.client_address[0]}")
        for field in ("NewExternalPort", "NewInternalPort", "NewProtocol", "NewInternalClient"):
            found = re.search(rf"<{field}>([^<]*)</{field}>", body)
            if found:
                log(f"      {field} = {found.group(1)}")

        if action == "GetExternalIPAddress":
            self._send(soap_envelope(
                action, f"<NewExternalIPAddress>{self.external_ip}</NewExternalIPAddress>"))
        elif action in ("AddPortMapping", "DeletePortMapping"):
            self._send(soap_envelope(action, ""))
        elif action == "GetStatusInfo":
            self._send(soap_envelope(
                action,
                "<NewConnectionStatus>Connected</NewConnectionStatus>"
                "<NewLastConnectionError>ERROR_NONE</NewLastConnectionError>"
                "<NewUptime>1000</NewUptime>"))
        elif action == "GetSpecificPortMappingEntry":
            # Nothing is mapped here, and saying so is the point: this is how the client
            # establishes the port is free.
            self._send(soap_fault(714, "NoSuchEntryInArray"), status=500)
        elif action == "GetGenericPortMappingEntry":
            self._send(soap_fault(713, "SpecifiedArrayIndexInvalid"), status=500)
        elif action == "GetNATRSIPStatus":
            self._send(soap_envelope(
                action, "<NewRSIPAvailable>0</NewRSIPAvailable><NewNATEnabled>1</NewNATEnabled>"))
        else:
            # Loudly, because an unhandled action is the most likely reason the client stalls.
            log(f"      !! unhandled SOAP action {action!r} -- answering InvalidAction")
            log(f"      !! body: {body[:400]}")
            self._send(soap_fault(401, "InvalidAction"), status=500)

    def log_message(self, *args):
        pass  # replaced by log()


def serve_ssdp(bind_ip, http_port, respond):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # Bind the multicast group address, not INADDR_ANY.
    #
    # This matters more than it looks. The game binds 192.168.1.100:1900 itself, to hear NOTIFY
    # announcements, and under WSL's mirrored networking that is the same address space this
    # process sits in. A probe on 0.0.0.0:1900 takes the port out from under it:
    #
    #   sys_net: [Native] Trying to bind 192.168.1.100:1900
    #   sys_net: Socket error EADDRINUSE
    #
    # after which the client falls back to an ephemeral port and behaves differently from a
    # normal console. Binding the group address still receives everything sent to
    # 239.255.255.250:1900 while leaving the unicast address free.
    try:
        sock.bind((SSDP_ADDR, SSDP_PORT))
    except OSError:
        # Not every stack allows binding a multicast address; fall back, but say so, because it
        # means the client's own bind will fail.
        log("WARNING: cannot bind the group address; falling back to 0.0.0.0, which will make "
            "the client's own bind of port 1900 fail with EADDRINUSE")
        sock.bind(("", SSDP_PORT))
    # Join the group on every interface we were given, and on the default one.
    membership = struct.pack("4s4s", socket.inet_aton(SSDP_ADDR), socket.inet_aton(bind_ip))
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
    except OSError as exc:
        log(f"could not join {SSDP_ADDR} on {bind_ip}: {exc}")

    location = f"http://{bind_ip}:{http_port}/desc.xml"
    log(f"SSDP listening on {SSDP_ADDR}:{SSDP_PORT} (joined via {bind_ip})")
    log(f"{'responding' if respond else 'listen-only'}; description at {location}")

    while True:
        data, addr = sock.recvfrom(2048)
        text = data.decode("utf-8", "replace")
        first = text.splitlines()[0] if text.splitlines() else ""
        target = re.search(r"^ST:\s*(.+)$", text, re.MULTILINE | re.IGNORECASE)
        log(f"SSDP {addr[0]}:{addr[1]} {first}"
            + (f"  ST={target.group(1).strip()}" if target else ""))

        if not respond or not first.upper().startswith("M-SEARCH"):
            continue
        wanted = target.group(1).strip() if target else "ssdp:all"
        if wanted not in SEARCH_TARGETS:
            log(f"      not us ({wanted}), ignoring")
            continue

        # Echo the requested target back. The client is looking for the exact string it asked
        # for, including its non-standard service:InternetGatewayDevice:1 form.
        answered = IGD_URN if wanted in ("ssdp:all", "upnp:rootdevice") else wanted
        reply = (
            "HTTP/1.1 200 OK\r\n"
            "CACHE-CONTROL: max-age=1800\r\n"
            "EXT:\r\n"
            f"LOCATION: {location}\r\n"
            "SERVER: nomad-ng/1.0 UPnP/1.0 probe/1.0\r\n"
            f"ST: {answered}\r\n"
            f"USN: uuid:{UUID}::{answered}\r\n"
            "\r\n"
        ).encode()
        sock.sendto(reply, addr)
        log(f"      -> answered {addr[0]}:{addr[1]} as {answered}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ip", default="192.168.1.100",
                        help="address to advertise and join the multicast group on")
    parser.add_argument("--http-port", type=int, default=1901,
                        help="port for the device description and control endpoint")
    parser.add_argument("--respond", action="store_true", help="answer discovery")
    parser.add_argument("--listen", action="store_true", help="log only (the default)")
    args = parser.parse_args()

    Gateway.external_ip = args.ip
    if args.respond:
        server = http.server.ThreadingHTTPServer((args.ip, args.http_port), Gateway)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        log(f"gateway HTTP on {args.ip}:{args.http_port}")

    try:
        serve_ssdp(args.ip, args.http_port, args.respond)
    except PermissionError:
        sys.exit("binding port 1900 needs root: rerun with sudo")
    except KeyboardInterrupt:
        pass
