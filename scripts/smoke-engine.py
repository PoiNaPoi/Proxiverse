#!/usr/bin/env python3
"""Real standalone-engine integration test. Never changes system proxy/Keychain.

Use /usr/bin/python3 scripts/smoke-engine.py --count 10000 for a burst baseline.
Optional --app dist/Reqnivo.app also launches the real native UI in benchmark mode.
"""
import argparse
import base64
import hashlib
from concurrent.futures import ThreadPoolExecutor
import gzip
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


ThreadingHTTPServer.request_queue_size = 128


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    payload = b'{"ok":true,"payload":"' + b'x' * 10_200 + b'"}'

    def do_GET(self):
        if self.headers.get("Upgrade", "").lower() == "websocket":
            key = self.headers["Sec-WebSocket-Key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", base64.b64encode(hashlib.sha1(key.encode()).digest()).decode())
            self.end_headers()
            for _ in range(20):
                header = self.rfile.read(2)
                if len(header) != 2:
                    return
                length = header[1] & 127
                if length > 125:
                    raise ValueError("Fixture supports small frames only")
                mask = self.rfile.read(4) if header[1] & 128 else None
                body = self.rfile.read(length)
                if mask:
                    body = bytes(value ^ mask[index % 4] for index, value in enumerate(body))
                self.wfile.write(bytes([0x81, len(body)]) + body)
                self.wfile.flush()
            return
        if self.path == "/large":
            body = b"x" * 1_200_000
        elif self.path == "/gzip":
            body = gzip.compress(self.payload)
        else:
            body = self.payload
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if self.path == "/gzip":
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--rate", type=float, default=0, help="Aggregate requests/second; 0 means burst")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--insecure", action="store_true", help="Test upstream verification bypass (standalone engine only)")
    parser.add_argument("--output", type=Path, default=ROOT / ".cache/engine-baseline.json")
    args = parser.parse_args()
    if args.app and args.insecure:
        parser.error("--insecure tests the standalone engine only")
    directory = Path(tempfile.mkdtemp(prefix="reqnivo-smoke-"))
    os.chmod(directory, 0o700)
    # Always ephemeral ports so automated runs never collide with a user's running Reqnivo (9090/9091).
    proxy_port = free_port()
    api_port = free_port()
    token = secrets.token_hex(32)
    env = dict(os.environ, REQNIVO_TOKEN=token, REQNIVO_API_PORT=str(api_port), REQNIVO_PROXY_PORT=str(proxy_port),
               REQNIVO_HTTPS_HOSTS=json.dumps(["localhost", "127.0.0.1"]),
               REQNIVO_CAPTURE_DIR=str(directory / "captures"), REQNIVO_PARENT_PID=str(os.getpid()),
               REQNIVO_UPSTREAM_CA=str(directory / "server.crt"))
    log = open(directory / "engine.log", "w")
    process = None
    server = None
    report = {}
    try:
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                        "-keyout", str(directory / "server.key"), "-out", str(directory / "server.crt")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(directory / "server.crt", directory / "server.key")
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        server_port = server.server_address[1]
        if args.app:
            # Exercise the same managed CA path as Capture Settings, without global trust changes.
            app_data = directory / "app-data"
            app_data.mkdir(mode=0o700)
            shutil.copyfile(directory / "server.crt", app_data / "upstream-ca.pem")
            (app_data / "settings.json").write_text(json.dumps({
                "proxyPort": proxy_port, "apiPort": api_port, "allowLAN": False, "setMacProxy": False,
                "service": "", "skipUpstreamVerification": False, "pinnedHosts": [],
                "inspectorOnRight": False, "messagesStacked": False,
                "httpsDecryptionHosts": {"localhost": True, "127.0.0.1": True},
            }))
            env["REQNIVO_DATA_DIR"] = str(app_data)
            process = subprocess.Popen([str(args.app.resolve() / "Contents/MacOS/Reqnivo"), "--benchmark",
                                        "--benchmark-output", str(directory / "ui-metrics.json"),
                                        "--benchmark-expected-flows", str(args.count + 4)], env=env, stdout=log, stderr=log)
            ca = directory / "app-data/ca/mitmproxy-ca-cert.pem"
        else:
            process = subprocess.Popen([
                str(ROOT / "vendor/mitmproxy.app/Contents/MacOS/mitmdump"), "-q", "-s",
                str(ROOT / "Sources/Reqnivo/Resources/bridge.py"), "--listen-host", "127.0.0.1", "-p", str(proxy_port),
                "--set", "confdir=" + str(directory / "ca"), "--set", "stream_large_bodies=1m",
                "--set", "connection_strategy=lazy", "--set", "ssl_insecure=" + str(args.insecure).lower()
            ], env=env, stdout=log, stderr=log)
            ca = directory / "ca/mitmproxy-ca-cert.pem"
        for _ in range(200):
            if process.poll() is not None:
                raise RuntimeError((directory / "engine.log").read_text())
            try:
                with socket.create_connection(("127.0.0.1", proxy_port), timeout=0.1):
                    if ca.exists():
                        break
            except OSError:
                pass
            time.sleep(0.1)
        else:
            raise RuntimeError("Engine did not start")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def api(path, authorized=True, origin=None, method="GET"):
            headers = {"Authorization": "Bearer " + token} if authorized else {}
            if origin:
                headers["Origin"] = origin
            request = urllib.request.Request(f"http://127.0.0.1:{api_port}{path}", headers=headers, method=method)
            with opener.open(request, timeout=5) as response:
                return json.load(response)

        if not args.app:
            assert api("/health")["ready"]
            assert api("/health")["apiVersion"] == 1
            for authorized, origin, expected in [(False, None, 401), (True, "https://outside.test", 403)]:
                try:
                    api("/health", authorized, origin)
                    raise AssertionError("API accepted an unauthorized request")
                except urllib.error.HTTPError as error:
                    assert error.code == expected
        context = ssl.create_default_context(cafile=str(ca))
        lock = threading.Lock()
        stop_sampling = threading.Event()
        samples = []

        def sample():
            while not stop_sampling.wait(0.5):
                output = subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid=,rss=,%cpu="], text=True)
                rows = [line.split() for line in output.splitlines()]
                included = {process.pid}
                for _ in range(10):
                    previous = len(included)
                    included.update(int(row[0]) for row in rows if int(row[1]) in included)
                    if previous == len(included):
                        break
                tree = [row for row in rows if int(row[0]) in included]
                with lock:
                    samples.append({"rssMB": sum(float(row[2]) for row in tree) / 1024,
                                    "sampledCPUPercent": sum(float(row[3]) for row in tree)})
        thread = threading.Thread(target=sample, daemon=True)
        thread.start()

        def get(path):
            connection = http.client.HTTPSConnection("127.0.0.1", proxy_port, context=context, timeout=20)
            connection.set_tunnel("localhost", server_port)
            connection.request("GET", path)
            response = connection.getresponse()
            body = response.read()
            assert response.status == 200, (response.status, body[:1000], (directory / "engine.log").read_text()[-3000:])
            expected = b"x" * 1_200_000 if path == "/large" else (gzip.compress(Handler.payload) if path == "/gzip" else Handler.payload)
            if path == "/gzip":
                assert gzip.decompress(body) == Handler.payload
            else:
                assert body == expected
            connection.close()

        http_server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=http_server.serve_forever, daemon=True).start()
        get("/json")
        get("/large")
        get("/gzip")
        # Exercise pass-through across multiple WebSocket messages, including
        # the bridge's bounded history hook. No third-party websocket client.
        with socket.create_connection(("127.0.0.1", proxy_port), timeout=5) as ws:
            key = base64.b64encode(secrets.token_bytes(16)).decode()
            endpoint = f"127.0.0.1:{http_server.server_address[1]}"
            ws.sendall((f"GET http://{endpoint}/ws HTTP/1.1\r\nHost: {endpoint}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
            head = b""
            while not head.endswith(b"\r\n\r\n"):
                byte = ws.recv(1)
                assert byte, "WebSocket handshake closed"
                head += byte
            assert head.startswith(b"HTTP/1.1 101"), head
            for index in range(20):
                payload = f"message-{index}".encode()
                mask = secrets.token_bytes(4)
                ws.sendall(bytes([0x81, 128 | len(payload)]) + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))
                header = ws.recv(2)
                assert len(header) == 2 and header[0] == 0x81, header
                echoed = b""
                while len(echoed) < (header[1] & 127):
                    chunk = ws.recv((header[1] & 127) - len(echoed))
                    assert chunk
                    echoed += chunk
                assert echoed == payload
        if not args.app:
            batch = api("/events?after=0")
            assert batch["total"] == 4
            numbers = {}
            for event in batch["events"]:
                flow = event["flow"]
                assert flow["number"] in range(1, 5)
                assert numbers.setdefault(flow["id"], flow["number"]) == flow["number"]
            assert sorted(numbers.values()) == [1, 2, 3, 4]
            assert all(event["flow"]["contentType"] is None
                       for event in batch["events"] if event["flow"]["state"] == "pending")
            completed = {event["flow"]["url"].split("/")[-1]: event["flow"] for event in batch["events"] if event["flow"]["state"] == "complete"}
            assert all(completed[name]["contentType"] == "application/json" for name in ("json", "large", "gzip"))
            detail = api("/flow/" + completed["json"]["id"])
            assert detail["summary"]["number"] == completed["json"]["number"]
            assert detail["summary"]["contentType"] == completed["json"]["contentType"]
            assert json.loads(detail["response"]["body"])["ok"]
            assert detail["response"]["captureState"] == "complete"
            assert api("/flow/" + completed["large"]["id"])["response"]["streamed"]
            assert api("/flow/" + completed["large"]["id"])["response"]["captureState"] == "streamed"
            assert "Encoded body" in api("/flow/" + completed["gzip"]["id"])["response"]["body"]
            assert api("/flow/" + completed["gzip"]["id"])["response"]["captureState"] == "encoded"
        began = time.perf_counter()
        def request(index):
            if args.rate:
                delay = began + index / args.rate - time.perf_counter()
                if delay > 0:
                    time.sleep(delay)
            get("/json?request=" + str(index))
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(request, range(args.count)))
        elapsed = time.perf_counter() - began
        time.sleep(2)
        report = {"count": args.count, "payloadBytes": len(Handler.payload), "elapsedSeconds": elapsed,
                  "requestsPerSecond": args.count / elapsed, "configuredRate": args.rate,
                  "os": subprocess.check_output(["/usr/bin/sw_vers", "-productVersion"], text=True).strip(),
                  "scope": "native UI + engine; custom CA HTTPS fixture" if args.app else "engine only; verified HTTPS local fixture",
                  "notes": "RSS is process-tree sum. CPU is the ps decaying average, not interval CPU. Not a frame/scroll benchmark."}
        if not args.app:
            health = api("/health")
            assert health["total"] == args.count + 4
            assert health["retained"] == min(10_000, args.count + 4)
            report["health"] = health
            files = list((directory / "captures").glob("*.json"))
            assert len(files) == health["retained"]
            report["previewDiskMB"] = sum(file.stat().st_size for file in files) / 1024**2
        else:
            # The app drives real filters and real row selections once capture is idle, then sets
            # benchmarkComplete. Wait for that instead of assuming detail time from an unselected row.
            deadline = time.monotonic() + 10 + args.count * 0.02 + 90
            while time.monotonic() < deadline:
                try:
                    report["ui"] = json.loads((directory / "ui-metrics.json").read_text())
                except (OSError, ValueError):
                    time.sleep(0.1)
                    continue
                if report["ui"].get("benchmarkComplete"):
                    break
                if process.poll() is not None:
                    raise RuntimeError((directory / "engine.log").read_text()[-4000:])
                time.sleep(0.2)
            diagnostics = {"ui": report.get("ui"), "expected": args.count + 4,
                           "log": (directory / "engine.log").read_text()[-4000:]}
            assert report["ui"]["totalFlows"] == args.count + 4, diagnostics
            assert report["ui"].get("benchmarkComplete"), diagnostics
            assert report["ui"]["selectionRender"]["count"] >= 20, diagnostics
            assert report["ui"]["selectionRender"]["lastMilliseconds"] > 0, diagnostics
            assert report["ui"]["filterEndToEnd"]["count"] >= 20, diagnostics
            assert report["ui"].get("benchmarkTimeouts", 0) == 0, diagnostics
            if args.count >= 10_000:
                assert report["ui"]["visibleRows"] == 10_000, diagnostics
                assert report["ui"]["filterEndToEnd"]["p95Milliseconds"] <= 100, diagnostics
            report["resources"] = {"ui": report["ui"]["ui"], "engine": report["ui"]["engine"],
                                   "storage": report["ui"]["storage"]}
            report["latency"] = {key: report["ui"][key] for key in ("selectionRender", "selectionToDetailReady", "detailReadyToRender", "filterEndToEnd", "filterModelOnly")}
        stop_sampling.set()
        thread.join(timeout=3)
        report["peakRSSMB"] = max((s["rssMB"] for s in samples), default=0)
        report["lastSample"] = samples[-1] if samples else None
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        if not args.app:
            # The bypass must work even when a custom CA is also configured.
            connection = http.client.HTTPSConnection("127.0.0.1", proxy_port, context=context, timeout=10)
            connection.set_tunnel("127.0.0.1", server_port)
            connection.request("GET", "/hostname-mismatch")
            response = connection.getresponse()
            body = response.read()
            assert (response.status == 200 and body == Handler.payload) if args.insecure else (response.status == 502 and b"certificate" in body.lower()), (response.status, body[:500])
            connection.close()
            subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
                            "-keyout", str(directory / "other.key"), "-out", str(directory / "other.crt")],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            other = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            other_tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            other_tls.load_cert_chain(directory / "other.crt", directory / "other.key")
            other.socket = other_tls.wrap_socket(other.socket, server_side=True)
            threading.Thread(target=other.serve_forever, daemon=True).start()
            try:
                connection = http.client.HTTPSConnection("127.0.0.1", proxy_port, context=context, timeout=10)
                connection.set_tunnel("localhost", other.server_address[1])
                connection.request("GET", "/untrusted-ca")
                response = connection.getresponse()
                body = response.read()
                assert (response.status == 200 and body == Handler.payload) if args.insecure else (response.status == 502 and b"certificate" in body.lower()), (response.status, body[:500])
                connection.close()
            finally:
                other.shutdown()
                other.server_close()
            print("Bypass accepted hostname mismatch and untrusted CA." if args.insecure
                  else "Custom CA accepted; hostname mismatch and untrusted CA rejected.")
        http_server.shutdown()
    finally:
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if server:
            server.shutdown()
        log.close()
        # Allow the app-parent watchdog to stop the engine before cleanup.
        time.sleep(1.2)
        shutil.rmtree(directory, ignore_errors=True)


if __name__ == "__main__":
    main()
