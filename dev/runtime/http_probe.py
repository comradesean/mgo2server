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

# TLS material is deliberately NOT under DOCROOT: www/ is a document root that gets copied into the
# container and served, and private keys have no business inside it. Overridable because the
# container mounts the two directories separately.
TLSDIR = pathlib.Path(os.environ.get("MGO2SERVER_TLS_DIR") or pathlib.Path(__file__).parent / "tls")

# Confirmed from a real client: MGO2 fetches
#   GET http://mgo2web.konami.com/us/mgo2/policy/policy.txt
# with User-Agent "PS3Application libhttp/4.9.3-000 (CellOS)". Files under www/ are served at
# their matching path; anything else still gets a stub so new endpoints show up in the log
# rather than failing.
# The fallback body, served whenever a path has no file behind it.
#
# Formatted as a HELP DOCUMENT on purpose. This stub's most likely audience is a player looking at
# the TIPS panel for a topic we have not written yet, and that panel parses <title> and
# <page-break> (see HELP.md). Written as flat prose it renders as one untitled page; written this
# way it gets a title, a 1/3 counter and working L1/R1. Everywhere else the tags are simply text.
#
# Lines are hand-wrapped at <= 42 characters to match the documents in www/us/mgo2/help/, and the
# line endings are LF for the same reason -- every file in the docroot is LF. This used to send
# CRLF, which disagreed with every file it was standing in for.
TERMS = (b"<title>UNEXPECTED SCREEN</title>\n"
         b"You should not be seeing this message.\n"
         b"\n"
         b"The server was asked for a document it\n"
         b"does not have, and this is the fallback.\n"
         b"<page-break>\n"
         b"Please report it through GitHub Issues.\n"
         b"Include the screen you were on, what you\n"
         b"did to get here, and any error code.\n"
         b"<page-break>\n"
         b"Steps to reproduce are the most useful\n"
         b"part. The time it happened helps too --\n"
         b"the server log records every address\n"
         b"that was requested.\n"
         b"\n"
         b"Thank you for your support.\n")


# Paths the application server owns. Everything else is answered by this harness.
#
# /rank/ is the Rankings screen: mgogetrank.html and mgogetrank_clan.html, both POSTs with a
# form-urlencoded body. Their replies are binary and XOR-obfuscated, so they must come from the
# application rather than from the stub below — default_body() would answer a single 0x00 byte,
# which the client reads as a zero-record board with a garbage total.
PROXY_PREFIXES = ("/us/mgo2/kid/", "/us/mgo2/rank/")

WEB_SERVER = os.environ.get("MGO2SERVER_WEB_URL", "http://web:8080")


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
            content_type = response.headers.get("Content-Type", "text/plain")
            return response.read(), content_type
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


# THE CLIENT DOES NOT CHECK WHETHER IT IS ALREADY UP TO DATE. THE SERVER HAS TO.
#
# uupdate.cc's version gate (0xBB75A8/0xBB76CC) tests only that the client's current version is
# **at least** the record's FROM version. Nothing anywhere compares it against the TO version. So a
# 1.36 client handed a "1.0.0 -> 1.36.0" reply passes the gate and is offered the upgrade it
# already has -- observed live 2026-08-03, an endless re-patch loop.
#
# The real server obviously answered this from the POSTed version, and so must we. The client
# sends `%d,%s,%u` (format at 0xE200C8) = packed version, disc id, nonce, where packed is
# `major<<24 | minor<<16 | revision` -- the same packing the staging directory name uses via
# `%x_%x` (0xE20110), which is why that directory is called `1000000_1240000` for 1.0.0 -> 1.36.0.
#
# The TO version is read back out of the reply we are about to send (its own T+3 field, see
# dev/docs/PATCH_FORMAT.md Sec 8) rather than configured separately, so the gate cannot drift out
# of step with what the reply actually offers.

def parse_reply_to_version(reply):
    """The packed TO version out of a checkver reply, or None if it is not an offer."""
    if len(reply) < 6 or reply[0] != 0x01:
        return None                       # 0x00 = "no update"; nothing to compare against
    try:
        index = 5                         # status byte + the opaque u32
        for _ in range(2):                # string A, string B
            index = reply.index(b"\x00", index) + 1
        while True:                        # records, terminated by an empty one
            end = reply.index(b"\x00", index)
            if end == index:
                index = end + 1
                break
            index = end + 1
        index += 2                        # the opaque u16
        return int.from_bytes(reply[index:index + 4], "big")
    except (ValueError, IndexError):
        return None


def parse_client_version(body):
    """The packed version the client POSTed, or None. First integer in `%d,%s,%u`."""
    digits = b""
    for ch in body:
        if 0x30 <= ch <= 0x39:
            digits += bytes([ch])
        elif digits:
            break
    return int(digits) if digits else None


def version_text(packed):
    return f"{packed >> 24}.{(packed >> 16) & 0xFF}.{packed & 0xFFFF}"


def docroot_file(path):
    """The real file backing this request path, or None. Does NOT read it."""
    clean = path.split("?")[0].replace("//", "/").lstrip("/")
    candidate = (DOCROOT / clean).resolve()
    try:
        candidate.relative_to(DOCROOT.resolve())
    except ValueError:
        return None  # refuse traversal outside the docroot
    return candidate if candidate.is_file() else None


def from_docroot(path):
    """Serves a real file if one exists for this path, else None.

    Whole-file read, so it is only for the small documents (checkver.html, help pages, the
    .infs). Auto-patch PAYLOADS go through Probe._serve_file instead -- the generic 1.36 archive
    is ~1.9 GB and reading that into a python:alpine container would take the probe down.
    """
    candidate = docroot_file(path)
    return candidate.read_bytes() if candidate is not None else None

class Probe(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _log(self):
        host = self.headers.get("Host", "?")
        print(f"  {self.command} http://{host}{self.path}", flush=True)
        for k in ("User-Agent", "Accept", "Range"):
            if self.headers.get(k):
                print(f"      {k}: {self.headers[k]}", flush=True)

    # Bodies are written in chunks and the delivered byte count is logged, so that "the client
    # fetched it" and "the client took only the headers and hung up" stop looking identical in
    # this log. Added 2026-08-03: a live run showed both auto-patch payloads requested and
    # nothing whatsoever written to the client's staging directory, and the old single
    # wfile.write() could not distinguish a completed 19.6 MB transfer from an abandoned one.
    # Same class of blind spot as the do_HEAD gap below and the 462-byte fallback body -- each
    # cost an investigation round because the server side looked fine.
    CHUNK = 64 * 1024

    def _respond(self, body, content_type="text/html"):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        sent = 0
        try:
            for offset in range(0, len(body), self.CHUNK):
                self.wfile.write(body[offset:offset + self.CHUNK])
                sent += len(body[offset:offset + self.CHUNK])
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError) as exc:
            print(f"      !! client disconnected after {sent:,} of {len(body):,} bytes "
                  f"({type(exc).__name__})", flush=True)
            return
        if len(body) >= self.CHUNK:
            print(f"      delivered {sent:,} of {len(body):,} bytes", flush=True)

    # THE AUTO-PATCH PAYLOADS ARE TOO BIG TO HOLD, AND THE CLIENT ASKS FOR RANGES.
    #
    # Two separate reasons this cannot go through _respond. (1) Size: the generic 1.36 archive is
    # ~1.9 GB, and `candidate.read_bytes()` in a python:3.12-alpine container is not survivable.
    # (2) Resume: MGO2.elf's downloader sends `Range: bytes=%d-` (TOC string, format at 0xBB90B0)
    # and accepts 206, gated by the flag bits at obj+1036. The old code LOGGED the Range header
    # and then ignored it, answering 200 with the whole body -- so a resumed download would
    # silently receive the file from byte 0 and write it at the resume offset, corrupting the
    # staged archive in a way that only shows up as a failed MAC much later.
    def _serve_file(self, candidate):
        size = candidate.stat().st_size
        start, end = 0, size - 1
        header = self.headers.get("Range")
        partial = False
        if header and header.strip().lower().startswith("bytes="):
            spec = header.split("=", 1)[1].strip()
            first, _, last = spec.partition("-")
            try:
                if first:
                    start, partial = int(first), True
                    if last:
                        end = min(int(last), end)
                elif last:                      # suffix form: the final N bytes
                    start, partial = max(0, size - int(last)), True
            except ValueError:
                partial = False                 # unparseable -- fall back to the whole file
            if start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                print(f"      !! range {header} unsatisfiable for {size:,} bytes", flush=True)
                return
        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(length))
        self.end_headers()
        sent = 0
        try:
            with open(candidate, "rb") as handle:
                handle.seek(start)
                while sent < length:
                    block = handle.read(min(self.CHUNK, length - sent))
                    if not block:
                        break
                    self.wfile.write(block)
                    sent += len(block)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError) as exc:
            print(f"      !! client disconnected after {sent:,} of {length:,} bytes "
                  f"({type(exc).__name__})", flush=True)
            return
        print(f"      delivered {sent:,} of {length:,} bytes"
              + (f" (range {start}-{end} of {size:,})" if partial else f" of {size:,}"), flush=True)

    # Anything at or above this is streamed off disk rather than read whole. Well under the
    # smallest auto-patch payload and well above every static document in the docroot.
    STREAM_ABOVE = 1 << 20

    def do_GET(self):
        self._log()
        candidate = docroot_file(self.path)
        if candidate is not None and (candidate.stat().st_size >= self.STREAM_ABOVE
                                      or self.headers.get("Range")):
            self._serve_file(candidate)
            return
        # Endpoints the MGO1 emulator documents expect a bare "0" as success.
        body = from_docroot(self.path)
        if body is not None:
            self._respond(body)
        else:
            self._respond(default_body(self.path))

    def do_HEAD(self):
        # BaseHTTPRequestHandler answers any verb without a do_* method with a bare "501
        # Unsupported method" -- and that path never calls _log(), since logging only happens
        # inside the do_* methods we wrote. So a HEAD request (a plausible pre-download
        # size/existence check) would fail with a non-200 status AND leave zero trace in this
        # log. Found 2026-07-31 while chasing why the client won't advance past the .inf fetch
        # despite the .inf itself being byte-verified: MGO2.elf's sendRequest (0xBB2B70) treats
        # any non-200 status as failure (0xBB7E2C), so an invisible HEAD 501 fits the symptom
        # exactly. Answered the same as GET, just without a body, per HTTP semantics.
        self._log()
        candidate = docroot_file(self.path)
        if candidate is not None:
            # Size without reading -- a HEAD of the 1.9 GB archive must not allocate it.
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(candidate.stat().st_size))
            self.end_headers()
            return
        body = default_body(self.path)
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()

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
            payload, upstream_type = forwarded
            print(f"      -> proxied, {len(payload)} bytes, {upstream_type}", flush=True)
            # Pass the application's content type through rather than relabelling everything as
            # HTML. The console's HTTP stack sees whatever this says.
            self._respond(payload, upstream_type)
            return

        # checkver.html is POSTed, not GETted (the client sends its version in the body), but
        # it's still a static reply out of the docroot -- do_GET already knows how to serve one.
        # The one thing it cannot do statically is decide whether THIS client needs the update.
        if self.path.endswith("checkver.html"):
            served = from_docroot(self.path)
            if served is not None:
                # Logged in full, unlike other POST bodies: this one carries a version, a disc id
                # and a nonce -- no credentials -- and not being able to see it cost an
                # investigation round.
                print(f"      checkver body: {body!r}", flush=True)
                client = parse_client_version(body)
                target = parse_reply_to_version(served)
                if client is not None and target is not None and client >= target:
                    print(f"      client is {version_text(client)}, offer is "
                          f"{version_text(target)} -- answering 0x00, already up to date",
                          flush=True)
                    self._respond(b"\x00")
                    return
                if client is not None and target is not None:
                    print(f"      client is {version_text(client)}, offering "
                          f"{version_text(target)}", flush=True)
                elif client is None:
                    print("      !! could not parse a version from the body -- serving the "
                          "reply unconditionally", flush=True)
                self._respond(served)
                return
        # Without this, a hand-authored checkver.html sits on disk and is never actually served,
        # because every .html POST used to fall straight through to the "up to date" stub below.
        served = from_docroot(self.path)
        if served is not None:
            self._respond(served)
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

    tls_ctx = None
    if use_tls:
        import ssl
        # Which chain to present. Set MGO2SERVER_TLS_CERT=cert-expired.pem to serve a certificate that
        # is identical to the normal one — same CA, same key, same common name — except that its
        # validity window is in the past. The client distinguishes that case: a certificate that
        # fails only on its dates is reported as 070B, anything else as 090B:00000001. See
        # OBSERVED.md, "The certificate branch".
        chain = os.environ.get("MGO2SERVER_TLS_CERT", "cert.pem")
        tls_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls_ctx.load_cert_chain(str(TLSDIR / chain), str(TLSDIR / "key.pem"))
        # The PS3's TLS stack is from 2008; allow the old ciphers and versions it offers.
        tls_ctx.minimum_version = ssl.TLSVersion.TLSv1
        tls_ctx.set_ciphers("ALL:@SECLEVEL=0")
        print(f"probe serving TLS chain {chain}", flush=True)

    class LoggingServer(ThreadingHTTPServer):
        """Reports every connection, and every handshake that fails.

        The usual arrangement — wrapping the listening socket — hides exactly what we most need
        to see. socketserver calls get_request() inside a bare `except OSError: return`, and
        ssl.SSLError is an OSError, so a client that connects and then rejects our certificate
        looks identical to a client that never connected at all. Wrapping per-connection instead
        keeps the peer address in hand and lets the failure be reported.
        """

        def get_request(self):
            conn, addr = self.socket.accept()
            if tls_ctx is None:
                print(f"connect from {addr[0]}:{addr[1]}", flush=True)
                return conn, addr
            try:
                conn = tls_ctx.wrap_socket(conn, server_side=True)
            except OSError as exc:
                print(f"TLS handshake FAILED from {addr[0]}:{addr[1]}: {exc}", flush=True)
                conn.close()
                raise
            print(f"TLS handshake ok from {addr[0]}:{addr[1]} "
                  f"({conn.version()}, {conn.cipher()[0]})", flush=True)
            return conn, addr

    server = LoggingServer(("0.0.0.0", port), Probe)
    print(f"probe listening on 0.0.0.0:{port} ({'https' if use_tls else 'http'})", flush=True)
    server.serve_forever()
