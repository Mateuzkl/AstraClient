#!/usr/bin/env python3
"""Serve a browser build with the isolation headers required by pthreads and HTTP Range support."""

import argparse
import functools
import http.server
import mimetypes
import os
import re
from pathlib import Path


mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".data")
mimetypes.add_type("application/octet-stream", ".spr")

RANGE_RE = re.compile(r"^bytes=(\d*)-(\d*)$")


class AstraHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def _parse_range(self, header: str, file_size: int):
        match = RANGE_RE.match(header.strip())
        if not match or file_size <= 0:
            return None
        start_s, end_s = match.groups()
        if not start_s and not end_s:
            return None
        if not start_s:
            suffix = int(end_s)
            if suffix <= 0:
                return None
            start = max(0, file_size - suffix)
            end = file_size - 1
        else:
            start = int(start_s)
            end = int(end_s) if end_s else file_size - 1
        if start < 0 or start >= file_size or end < start:
            return None
        end = min(end, file_size - 1)
        return start, end

    def send_head(self):
        range_header = self.headers.get("Range")
        if not range_header:
            return super().send_head()

        path = self.translate_path(self.path)
        if os.path.isdir(path) or not os.path.isfile(path):
            return super().send_head()

        try:
            stream = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None

        try:
            fs = os.fstat(stream.fileno())
            file_size = fs.st_size
            parsed = self._parse_range(range_header, file_size)
            if parsed is None:
                stream.close()
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{file_size}")
                self.end_headers()
                return None

            start, end = parsed
            length = end - start + 1
            ctype = self.guess_type(path)
            self.send_response(206)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
            self.send_header("Content-Length", str(length))
            self.send_header("Last-Modified", self.date_time_string(fs.st_mtime))
            self.end_headers()
            stream.seek(start)
            self._range_remaining = length
            return stream
        except Exception:
            stream.close()
            raise

    def copyfile(self, source, outputfile) -> None:
        remaining = getattr(self, "_range_remaining", None)
        if remaining is None:
            super().copyfile(source, outputfile)
            return
        self._range_remaining = None
        while remaining > 0:
            chunk = source.read(min(65536, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)


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
    print(f"Serving {directory} at http://{args.bind}:{args.port}/astraclient.html", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
