"""Loopback-only regression fixture for the production native HTTP/WS transport."""

import argparse
import base64
import contextlib
import hashlib
import http.server
import pathlib
import ssl
import struct
import subprocess
import tempfile
import threading
import time


def read_exact(stream, size):
    value = stream.read(size)
    if len(value) != size:
        raise EOFError("WebSocket closed")
    return value


def receive_frame(stream):
    first, second = read_exact(stream, 2)
    size = second & 127
    if size == 126:
        size = struct.unpack("!H", read_exact(stream, 2))[0]
    elif size == 127:
        size = struct.unpack("!Q", read_exact(stream, 8))[0]
    if size > 1024 * 1024 or not second & 128:
        raise ValueError("Invalid client frame")
    mask = read_exact(stream, 4)
    data = read_exact(stream, size)
    return first, bytes(c ^ mask[i % 4] for i, c in enumerate(data))


def frame(opcode, payload, final=True):
    size = len(payload)
    if size < 126:
        header = bytes([opcode | (128 if final else 0), size])
    elif size < 65536:
        header = bytes([opcode | (128 if final else 0), 126]) + struct.pack("!H", size)
    else:
        header = bytes([opcode | (128 if final else 0), 127]) + struct.pack("!Q", size)
    return header + payload


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def handle(self):
        try:
            super().handle()
        except ConnectionError:
            pass  # A canceled HTTP request may also abort the keep-alive read.

    def reply(self, status, body=b"Astra HTTP test", **headers):
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        data = read_exact(self.rfile, int(self.headers.get("Content-Length", "0")))
        if self.path == "/post-redirect":
            self.reply(307, b"redirect body must be discarded", Location="/echo")
        else:
            self.reply(200, data)

    def do_GET(self):
        try:
            if self.headers.get("Upgrade", "").lower() == "websocket":
                return self.websocket()
            if self.path == "/test.crl":
                return self.reply(200, self.server.crl_data, **{"Content-Type": "application/pkix-crl"})
            if self.path == "/redirect":
                return self.reply(302, b"discard this redirect body", Location="/ok")
            if self.path == "/loop":
                return self.reply(302, b"", Location="/loop")
            if self.path == "/missing":
                return self.reply(404)
            if self.path == "/empty":
                return self.reply(204, b"")
            if self.path == "/chunked":
                self.send_response(200)
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                for part in (b"Astra ", b"HTTP ", b"test"):
                    self.wfile.write(f"{len(part):x}\r\n".encode() + part + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
                return
            if self.path == "/slow":
                self.send_response(200)
                self.send_header("Content-Length", "65536")
                self.end_headers()
                for _ in range(16):
                    self.wfile.write(b"x" * 4096)
                    self.wfile.flush()
                    time.sleep(0.02)
                return
            self.reply(200)
        except (ConnectionError, EOFError):
            pass  # Cancellation/disconnect is intentional in these tests.

    def websocket(self):
        key = self.headers["Sec-WebSocket-Key"]
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept.decode())
        self.end_headers()
        self.connection.settimeout(5)
        opcode, payload = receive_frame(self.rfile)
        if opcode != 0x81:
            raise ValueError("Expected a complete text message")
        if self.path == "/fragmented":
            half = len(payload) // 2
            self.wfile.write(frame(1, payload[:half], final=False))
            self.wfile.write(frame(9, b"ping"))
            self.wfile.write(frame(0, payload[half:]))
        else:
            # Binary frames also carry the unchanged byte payload to Lua.
            self.wfile.write(frame(2, payload))
        self.wfile.flush()
        while True:
            opcode, _ = receive_frame(self.rfile)
            if opcode & 15 == 8:
                self.wfile.write(frame(8, b"\x03\xe8"))
                break
        self.close_connection = True


def start_server(context=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    if context:
        server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


@contextlib.contextmanager
def serving(context=None):
    server = start_server(context)
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()


def run(executable, mode, url, expected, *extra):
    subprocess.run([str(executable), mode, url, expected, *map(str, extra)], check=True, timeout=20)


def tls_cases(executable, directory):
    # Optional local TLS suite: never import generated roots into the OS store.
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID
    import datetime

    now = datetime.datetime.now(datetime.timezone.utc)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Astra regression test CA")])
    root = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=2))
            .not_valid_after(now + datetime.timedelta(days=2))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .sign(key, hashes.SHA256()))
    ca = directory / "ca.pem"
    ca.write_bytes(root.public_bytes(serialization.Encoding.PEM))
    with serving() as publisher:
        # Supply a real test CRL instead of disabling Schannel revocation checks.
        crl = (x509.CertificateRevocationListBuilder().issuer_name(name)
               .last_update(now - datetime.timedelta(days=1)).next_update(now + datetime.timedelta(days=1))
               .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(key.public_key()), critical=False)
               .sign(key, hashes.SHA256()))
        publisher.crl_data = crl.public_bytes(serialization.Encoding.DER)
        distribution = x509.DistributionPoint(
            full_name=[x509.UniformResourceIdentifier(f"http://127.0.0.1:{publisher.server_port}/test.crl")],
            relative_name=None, reasons=None, crl_issuer=None)
        for hostname, expired, expected in (("localhost", False, "success"),
                                            ("other.invalid", False, "failure"),
                                            ("localhost", True, "failure")):
            subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, hostname)])
            cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(name).public_key(key.public_key())
                    .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=2))
                    .not_valid_after(now + datetime.timedelta(days=-1 if expired else 1))
                    .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]), critical=False)
                    .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
                    .add_extension(x509.CRLDistributionPoints([distribution]), critical=False)
                    .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(key.public_key()), critical=False)
                    .sign(key, hashes.SHA256()))
            cert_path, key_path = directory / "server.pem", directory / "key.pem"
            cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
            key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                   serialization.NoEncryption()))
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(cert_path, key_path)
            with serving(context) as server:
                url = f"https://localhost:{server.server_port}/ok"
                run(executable, "tls", url, expected, ca)
                if hostname == "localhost" and not expired:
                    run(executable, "tls", url, "failure")  # Same server, untrusted CA.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=pathlib.Path)
    parser.add_argument("--tls", action="store_true", help="Also run local TLS tests (requires cryptography)")
    parser.add_argument("--temp-root", type=pathlib.Path)
    args = parser.parse_args()
    server = start_server()
    try:
        base = f"127.0.0.1:{server.server_port}"
        for path in ("ok", "redirect", "chunked", "empty"):
            run(args.executable, "get", f"http://{base}/{path}", "success")
        for path in ("missing", "loop"):
            run(args.executable, "get", f"http://{base}/{path}", "failure")
        for path in ("echo", "post-redirect"):
            run(args.executable, "post", f"http://{base}/{path}", "success")
        for mode in ("cancel", "cancel-progress", "bad-header"):
            run(args.executable, mode, f"http://{base}/slow", "failure")
        for mode, path in (("ws", "echo"), ("ws", "fragmented"), ("ws-large", "echo")):
            run(args.executable, mode, f"ws://{base}/{path}", "success")
        run(args.executable, "ws", f"http://{base}/ok", "failure")
    finally:
        server.shutdown()
        server.server_close()
    if args.tls:
        with tempfile.TemporaryDirectory(prefix="astra-tls-", dir=args.temp_root) as directory:
            tls_cases(args.executable, pathlib.Path(directory))
    print("Native HTTP/WebSocket/TLS fixture: PASS")


if __name__ == "__main__":
    main()
