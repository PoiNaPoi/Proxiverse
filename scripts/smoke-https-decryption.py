#!/usr/bin/env python3
"""Selective TLS interception against an isolated HTTPS origin; no system trust/proxy changes."""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Origin(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"secret-response-body"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    with tempfile.TemporaryDirectory(prefix="reqnivo-https-scope-") as temp:
        root = Path(temp)
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                        "-keyout", str(root / "server.key"), "-out", str(root / "server.pem")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        origin = ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(root / "server.pem", root / "server.key")
        origin.socket = context.wrap_socket(origin.socket, server_side=True)
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        proxy, control = free_port(), free_port()
        token = secrets.token_hex(32)
        env = dict(os.environ, REQNIVO_TOKEN=token, REQNIVO_API_PORT=str(control),
                   REQNIVO_CAPTURE_DIR=str(root / "captures"), REQNIVO_HTTPS_HOSTS="[]",
                   REQNIVO_PARENT_PID=str(os.getpid()), REQNIVO_UPSTREAM_CA=str(root / "server.pem"),
                   PYTHONDONTWRITEBYTECODE="1")

        def api(path, hosts=None, authorized=True):
            connection = http.client.HTTPConnection("127.0.0.1", control, timeout=5)
            connection.request("GET" if hosts is None else "POST", path,
                               None if hosts is None else json.dumps(hosts),
                               {"Authorization": "Bearer " + token} if authorized else {})
            response = connection.getresponse()
            payload = json.loads(response.read())
            connection.close()
            return response.status, payload

        def get(certificate):
            connection = http.client.HTTPSConnection("127.0.0.1", proxy,
                context=ssl.create_default_context(cafile=str(certificate)), timeout=5)
            connection.set_tunnel("localhost", origin.server_port)
            connection.request("GET", "/private-path?secret=query", headers={"Authorization": "secret-token"})
            response = connection.getresponse()
            assert response.status == 200
            assert response.read() == b"secret-response-body"
            connection.close()

        with open(root / "engine.log", "w") as log:
            process = subprocess.Popen([
                str(ROOT / "vendor/mitmproxy.app/Contents/MacOS/mitmdump"), "-q", "-s",
                str(ROOT / "Sources/Reqnivo/Resources/bridge.py"), "--listen-host", "127.0.0.1", "-p", str(proxy),
                "--set", f"confdir={root / 'ca'}", "--set", "connection_strategy=lazy"], env=env, stdout=log, stderr=log)
            try:
                for _ in range(150):
                    if process.poll() is not None:
                        raise AssertionError((root / "engine.log").read_text())
                    try:
                        if api("/health")[0] == 200:
                            break
                    except OSError:
                        pass
                    time.sleep(0.1)
                else:
                    raise AssertionError("Engine startup timed out")
                # Trusting only the origin proves the proxy leaves TLS intact when disabled.
                get(root / "server.pem")
                time.sleep(0.1)
                flows = api("/events?after=0")[1]["events"]
                assert len(flows) == 1, flows
                flow = flows[0]["flow"]
                assert flow["tlsPassthrough"] and flow["state"] == "tls-passthrough", flow
                detail = api("/flow/" + flow["id"])[1]
                captured = json.dumps(detail)
                assert all(secret not in captured for secret in ["private-path", "secret=query", "secret-token", "secret-response-body"]), detail
                assert detail["request"]["headers"] == [] and detail["response"] is None
                assert api("/https-decryption", ["localhost"], authorized=False)[0] == 401
                assert api("/https-decryption", ["*.localhost"])[0] == 400
                assert api("/https-decryption", ["sub.localhost"])[0] == 200
                get(root / "server.pem")  # Exact match: enabling a different domain does not intercept localhost.
                assert api("/https-decryption", ["LOCALHOST."])[0] == 200
                get(root / "ca/mitmproxy-ca-cert.pem")
                time.sleep(0.1)
                decrypted = [event["flow"] for event in api("/events?after=0")[1]["events"]
                             if event["flow"]["state"] == "complete"]
                assert decrypted and not decrypted[-1]["tlsPassthrough"], decrypted
                detail = api("/flow/" + decrypted[-1]["id"])[1]
                assert detail["response"]["body"] == "secret-response-body", detail
                assert api("/https-decryption", ["https://localhost"])[0] == 400
                get(root / "ca/mitmproxy-ca-cert.pem")  # Invalid updates leave the active selection intact.
                assert api("/https-decryption", [])[0] == 200
                get(root / "server.pem")
                print("PASS: encrypted passthrough, no secret capture, exact hosts, authenticated live enable/disable, invalid updates rejected.")
            finally:
                process.terminate()
                process.wait(timeout=10)
                origin.shutdown()
                origin.server_close()


if __name__ == "__main__":
    main()
