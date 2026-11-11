#!/usr/bin/env python3
"""Exercise LAN auth through the bundled engine using a real non-loopback peer."""
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
    protocol_version = "HTTP/1.1"
    hits = 0

    def do_GET(self):
        type(self).hits += 1
        assert "Proxy-Authorization" not in self.headers
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


def main():
    # Routing lookup only; UDP connect sends no packet. Bind clients to this IP
    # so the engine sees the LAN path, rather than its loopback exemption.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.connect(("192.0.2.1", 9))
        lan_ip = sock.getsockname()[0]
    assert not lan_ip.startswith("127."), "A non-loopback interface is required"
    with tempfile.TemporaryDirectory(prefix="reqnivo-lan-auth-") as temp:
        root = Path(temp)
        token = secrets.token_hex(32)
        legacy_proxy_header = "Basic bGVnYWN5OnRlc3Q="
        proxy, control = free_port(), free_port()
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                        "-keyout", str(root / "server.key"), "-out", str(root / "server.pem")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        origin = ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        secure = ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(root / "server.pem", root / "server.key")
        secure.socket = context.wrap_socket(secure.socket, server_side=True)
        for server in [origin, secure]:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        env = dict(os.environ, REQNIVO_TOKEN=token, REQNIVO_API_PORT=str(control),
                   REQNIVO_CAPTURE_DIR=str(root / "captures"), REQNIVO_HTTPS_HOSTS="[]",
                   REQNIVO_PARENT_PID=str(os.getpid()), REQNIVO_UPSTREAM_CA=str(root / "server.pem"),
                   PYTHONDONTWRITEBYTECODE="1")

        def api(path, hosts=None, authorized=True, expected=200):
            conn = http.client.HTTPConnection("127.0.0.1", control, timeout=5)
            conn.request("GET" if hosts is None else "POST", path,
                         None if hosts is None else json.dumps(hosts), {"Authorization": "Bearer " + token} if authorized else {})
            response = conn.getresponse()
            assert response.status == expected, (path, response.status)
            payload = json.loads(response.read())
            conn.close()
            return payload

        def request(method="GET"):
            conn = http.client.HTTPConnection(lan_ip, proxy, timeout=5, source_address=(lan_ip, 0))
            conn.request(method, f"localhost:{secure.server_port}" if method == "CONNECT" else
                         f"http://127.0.0.1:{origin.server_port}/")
            response = conn.getresponse()
            status = response.status
            if method != "CONNECT":
                response.read()
            conn.close()
            return status

        def https(cafile, decrypted=False, keep_open=False):
            conn = http.client.HTTPSConnection(lan_ip, proxy, timeout=5, source_address=(lan_ip, 0),
                context=ssl.create_default_context(cafile=str(cafile)))
            conn.set_tunnel("localhost", secure.server_port)
            # Confirm stale client credentials are stripped from decrypted traffic.
            conn.request("GET", "/", headers={"Proxy-Authorization": legacy_proxy_header} if decrypted else {})
            response = conn.getresponse()
            assert response.status == 200 and response.read() == b"ok"
            if keep_open:
                return conn
            conn.close()

        command = [str(ROOT / "vendor/mitmproxy.app/Contents/MacOS/mitmdump"),
                   "-q", "-s", str(ROOT / "Sources/Reqnivo/Resources/bridge.py"),
                   "--listen-host", "0.0.0.0", "-p", str(proxy), "--set", f"confdir={root / 'ca'}",
                   "--set", "connection_strategy=lazy", "--set", "block_global=true"]
        with open(root / "engine.log", "w") as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise AssertionError("Engine exited during LAN device approval test")
                    try:
                        if api("/health")["ready"]:
                            break
                    except OSError:
                        pass
                    time.sleep(0.1)
                else:
                    raise AssertionError("Engine startup timed out")
                assert api("/lan-devices") == []
                api("/lan-devices", authorized=False, expected=401)

                def blocked(method="GET"):
                    before = Origin.hits
                    try:
                        status = request(method)
                    except (OSError, http.client.HTTPException):
                        pass
                    else:
                        assert status == 403, (method, status)
                    assert Origin.hits == before, "Unapproved traffic reached the origin"

                for method in ["GET", "POST", "CONNECT"]:
                    blocked(method)
                assert api("/events?after=0")["events"] == []
                assert api("/lan-devices") == [{"ip": lan_ip, "approved": False}]
                approval = {"ip": lan_ip, "approved": True}
                api("/lan-devices", approval, authorized=False, expected=401)
                api("/lan-devices", {"ip": "192.0.2.10", "approved": True}, expected=400)
                api("/lan-devices", {"ip": lan_ip, "approved": "yes"}, expected=400)
                assert api("/lan-devices", approval) == [{"ip": lan_ip, "approved": True}]
                assert request() == 200  # No username/password header.
                local = http.client.HTTPConnection("127.0.0.1", proxy, timeout=3)
                local.request("GET", f"http://127.0.0.1:{origin.server_port}/")
                response = local.getresponse()
                assert response.status == 200 and response.read() == b"ok"
                plain = http.client.HTTPConnection(lan_ip, proxy, timeout=3, source_address=(lan_ip, 0))
                plain.request("GET", f"http://127.0.0.1:{origin.server_port}/")
                response = plain.getresponse()
                assert response.status == 200 and response.read() == b"ok"
                passthrough = https(root / "server.pem", keep_open=True)
                api("/https-decryption", ["localhost"])
                decrypted = https(root / "ca/mitmproxy-ca-cert.pem", decrypted=True, keep_open=True)
                for event in api("/events?after=0")["events"]:
                    detail = json.dumps(api("/flow/" + event["flow"]["id"]))
                    assert legacy_proxy_header not in detail and "proxy-authorization" not in detail.lower()
                api("/lan-devices", {"ip": lan_ip, "approved": False})
                for connection in [plain, passthrough, decrypted]:
                    connection.sock.settimeout(3)
                    try:
                        assert connection.sock.recv(1) == b"", "Revoked connection is still open"
                    except (ConnectionResetError, BrokenPipeError, ssl.SSLEOFError):
                        pass
                    finally:
                        connection.close()
                for method in ["GET", "CONNECT"]:
                    blocked(method)
                # Revoking LAN clients must not disconnect loopback capture.
                local.request("GET", f"http://127.0.0.1:{origin.server_port}/")
                response = local.getresponse()
                assert response.status == 200 and response.read() == b"ok"
                local.close()
                api("/lan-devices", approval)
                assert request() == 200
                process.terminate()
                process.wait(timeout=10)
                # Restart with the same directories: approvals are session-only.
                process = subprocess.Popen(command, env=env, stdout=log, stderr=log)
                for _ in range(100):
                    try:
                        if api("/health")["ready"]:
                            break
                    except OSError:
                        pass
                    time.sleep(0.1)
                else:
                    raise AssertionError("Engine restart timed out")
                assert api("/lan-devices") == []
                blocked()
                assert api("/lan-devices") == [{"ip": lan_ip, "approved": False}]
                print("PASS: device discovery, deny before approval, authenticated API, password-free HTTP/TLS, revoke closes HTTP and both TLS modes, loopback stays connected, restart expires approvals.")
            finally:
                process.terminate()
                process.wait(timeout=10)
                for server in [origin, secure]:
                    server.shutdown()
                    server.server_close()


if __name__ == "__main__":
    main()
