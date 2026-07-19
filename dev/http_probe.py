"""Logs every HTTP request the game makes, and answers so it keeps going.

MGO2 fetches a terms-of-use document over plain HTTP before it will let you log in. The exact
host and path vary by region and disc, so rather than guessing, this answers everything and
prints what was asked for.
"""
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TERMS = (b"nomad-ng test server.\r\n\r\n"
         b"This is a private server for development testing.\r\n")

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
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._log()
        # Endpoints the MGO1 emulator documents expect a bare "0" as success.
        if any(p in self.path for p in ("chgpswd", "deluser", "reguser")):
            self._respond(b"0")
        else:
            self._respond(TERMS)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        self._log()
        if body:
            print(f"      body: {body[:200]!r}", flush=True)
        self._respond(b"0")

    def log_message(self, *args):
        pass  # replaced by _log

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    print(f"HTTP probe listening on 0.0.0.0:{port} — every request will be printed", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Probe).serve_forever()
