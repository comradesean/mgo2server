"""Logs every HTTP request the game makes, and answers so it keeps going.

MGO2 fetches a terms-of-use document over plain HTTP before it will let you log in. The exact
host and path vary by region and disc, so rather than guessing, this answers everything and
prints what was asked for.
"""
import os
import pathlib
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DOCROOT = pathlib.Path(__file__).parent / "www"

# Confirmed from a real client: MGO2 fetches
#   GET http://mgo2web.konami.com/us/mgo2/policy/policy.txt
# with User-Agent "PS3Application libhttp/4.9.3-000 (CellOS)". Files under www/ are served at
# their matching path; anything else still gets a stub so new endpoints show up in the log
# rather than failing.
TERMS = (b"nomad-ng test server.\r\n\r\n"
         b"This is a private server for development testing.\r\n")


# Paths the application server owns. Everything else is answered by this harness.
PROXY_PREFIXES = ("/us/mgo2/kid/",)

WEB_SERVER = os.environ.get("NOMAD_WEB_URL", "http://web:8080")


def forward(path, body, content_type):
    """Proxies a request to the real web server, or returns None if it does not own the path."""
    clean = path.replace("//", "/")
    if not any(clean.startswith(prefix) for prefix in PROXY_PREFIXES):
        return None

    request = urllib.request.Request(
        WEB_SERVER + clean,
        data=body,
        headers={"Content-Type": content_type or "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.read()
    except urllib.error.URLError as e:
        print(f"      !! proxy to {WEB_SERVER} failed: {e}", flush=True)
        return None


def default_body(path):
    """Reply for a path with no file behind it.

    The .html endpoints are not documents: the client posts a form and expects a bare status
    code back, "0" meaning success. Confirmed shapes so far:
      /patch/checkver.html   p=<flags>,<titleid>,<version>   -> version check
      chgpswd / deluser / reguser                            -> account operations
    Anything else falls back to the terms stub so new endpoints are obvious in the log.
    """
    # Confirmed against MiguelRipoll23/mgo2-server: the .html endpoints answer with a single
    # 0x00 byte, not the ASCII "0" (0x30) the MGO1 project's notes suggested. For checkver that
    # means "up to date".
    if path.endswith(".html"):
        return b"\x00"
    return TERMS


def from_docroot(path):
    """Serves a real file if one exists for this path, else None."""
    clean = path.split("?")[0].replace("//", "/").lstrip("/")
    candidate = (DOCROOT / clean).resolve()
    try:
        candidate.relative_to(DOCROOT.resolve())
    except ValueError:
        return None  # refuse traversal outside the docroot
    return candidate.read_bytes() if candidate.is_file() else None

class Probe(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _log(self):
        host = self.headers.get("Host", "?")
        print(f"  {self.command} http://{host}{self.path}", flush=True)
        for k in ("User-Agent", "Accept"):
            if self.headers.get(k):
                print(f"      {k}: {self.headers[k]}", flush=True)

    def _respond(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._log()
        # Endpoints the MGO1 emulator documents expect a bare "0" as success.
        body = from_docroot(self.path)
        if body is not None:
            self._respond(body)
        else:
            self._respond(default_body(self.path))

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        self._log()
        if body:
            # Credentials pass through here; log the field names but not the values.
            fields = ",".join(f.split(b"=")[0].decode("latin-1") for f in body.split(b"&"))
            print(f"      body fields: {fields}", flush=True)

        # Anything the real web server implements is proxied to it, so the harness stays a
        # TLS terminator and the actual logic lives in the application.
        forwarded = forward(self.path, body, self.headers.get("Content-Type"))
        if forwarded is not None:
            print(f"      -> proxied to web server, {len(forwarded)} bytes", flush=True)
            self._respond(forwarded)
            return

        self._respond(default_body(self.path))

    def log_message(self, *args):
        pass  # replaced by _log

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    # The client does the policy fetch over plain HTTP but authenticates over TLS, so the probe
    # has to be able to run as either. The certificate is self-signed; whether the client accepts
    # it is the open question — the PS3 may pin or require a Konami-issued chain.
    use_tls = len(sys.argv) > 2 and sys.argv[2] == "tls"
    server = ThreadingHTTPServer(("0.0.0.0", port), Probe)
    if use_tls:
        import ssl
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(str(DOCROOT / "cert.pem"), str(DOCROOT / "key.pem"))
        # The PS3's TLS stack is from 2008; allow the old ciphers and versions it offers.
        ctx.minimum_version = ssl.TLSVersion.TLSv1
        ctx.set_ciphers("ALL:@SECLEVEL=0")
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
    print(f"probe listening on 0.0.0.0:{port} ({'https' if use_tls else 'http'})", flush=True)
    server.serve_forever()
