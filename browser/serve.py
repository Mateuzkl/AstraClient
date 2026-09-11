#!/usr/bin/env python3
"""Serve a browser build with the isolation headers required by pthreads."""

import argparse
import functools
import http.server
import mimetypes
from pathlib import Path


mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".data")


class AstraHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", nargs="?", default="build-wasm-release/dist")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    directory = Path(args.directory).resolve()
    if not (directory / "astraclient.html").is_file():
        parser.error(f"astraclient.html not found in {directory}")

    handler = functools.partial(AstraHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer((args.bind, args.port), handler)
    print(f"Serving {directory} at http://{args.bind}:{args.port}/astraclient.html")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
