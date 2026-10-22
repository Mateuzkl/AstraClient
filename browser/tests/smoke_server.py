"""Local-only harness for the built client's real mobile/desktop startup.

Serve /mobile.html to select -mobile without modifying production artifacts.
No credentials or production game server are needed for this startup check.
"""
import functools
import http.server
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from serve import AstraHandler


class SmokeHandler(AstraHandler):
    def do_GET(self):
        if self.path.split('?', 1)[0] == '/mobile.html':
            source = (Path(self.directory) / 'astraclient.html').read_bytes()
            source = source.replace(b'</body>', b'<script src="smoke-mobile.js"></script></body>')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(source)))
            self.end_headers()
            self.wfile.write(source)
        elif self.path == '/smoke-mobile.js':
            source = b"Module.arguments = ['-mobile'];"
            self.send_response(200)
            self.send_header('Content-Type', 'text/javascript; charset=utf-8')
            self.send_header('Content-Length', str(len(source)))
            self.end_headers()
            self.wfile.write(source)
        else:
            super().do_GET()


if __name__ == '__main__':
    root = Path(sys.argv[1]).resolve()
    if not (root / 'astraclient.html').is_file():
        raise SystemExit('Expected a built Web dist directory')
    http.server.ThreadingHTTPServer(('127.0.0.1', 8014),
        functools.partial(SmokeHandler, directory=str(root))).serve_forever()
