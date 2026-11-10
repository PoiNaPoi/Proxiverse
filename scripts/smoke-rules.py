#!/usr/bin/env python3
"""Real engine Map Local / breakpoint integration. Uses isolated data and ports."""
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import gzip
import http.client
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent


def port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Origin(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    seen = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        self.seen.append((self.path, body, self.headers.get("x-edit")))
        if self.path in ("/large", "/chunked-large"):
            data = b"x" * 1_200_000
        elif self.path == "/chunked-preview-limit":
            data = b"x" * 300_000
        elif self.path == "/gzip":
            data = gzip.compress(b'{"original":true}')
        else:
            data = json.dumps({"path": self.path, "received": body.decode()}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if self.path.startswith("/chunked"):
            self.send_header("Transfer-Encoding", "chunked")
        else:
            self.send_header("Content-Length", str(len(data)))
        if self.path == "/gzip":
            self.send_header("Content-Encoding", "gzip")
        self.end_headers()
        if self.path.startswith("/chunked"):
            for chunk in (data[:10], data[10:]):
                self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        else:
            self.wfile.write(data)

    def log_message(self, *args):
        pass


def main():
    with tempfile.TemporaryDirectory(prefix="proxiverse-rules-") as temp:
        root = Path(temp)
        (root / "mock-files").mkdir()
        (root / "mock-files/first.mock").write_text('{"local":1}')
        (root / "mock-files/second.mock").write_text('{"local":2}')
        proxy, control = port(), port()
        token = secrets.token_hex(32)
        origin = ThreadingHTTPServer(("127.0.0.1", 0), Origin)
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{origin.server_port}"
        env = dict(os.environ, PROXIVERSE_TOKEN=token, PROXIVERSE_API_PORT=str(control),
                   PROXIVERSE_CAPTURE_DIR=str(root / "captures"), PROXIVERSE_RULES_FILE=str(root / "rules.json"),
                   PROXIVERSE_PARENT_PID=str(os.getpid()), PYTHONDONTWRITEBYTECODE="1")
        command = [str(ROOT / "vendor/mitmproxy.app/Contents/MacOS/mitmdump"), "-q", "-s",
                   str(ROOT / "Sources/Proxiverse/Resources/bridge.py"), "-p", str(proxy),
                   "--listen-host", "127.0.0.1", "--set", f"confdir={root / 'ca'}",
                   "--set", "stream_large_bodies=1m", "--set", "connection_strategy=lazy"]
        log = open(root / "engine.log", "w")
        process = subprocess.Popen(command, env=env, stdout=log, stderr=log)

        def api(path, data=None, expected=200):
            connection = http.client.HTTPConnection("127.0.0.1", control, timeout=5)
            connection.request("POST" if data is not None else "GET", path,
                               json.dumps(data) if data is not None else None,
                               {"Authorization": "Bearer " + token, "Content-Type": "application/json"})
            response = connection.getresponse()
            result = json.loads(response.read())
            connection.close()
            assert response.status == expected, (response.status, result)
            return result

        def send(path, body='{"original":true}', timeout=15, headers_received=None):
            connection = http.client.HTTPConnection("127.0.0.1", proxy, timeout=timeout)
            connection.request("POST", url + path, body, {"Content-Type": "application/json"})
            response = connection.getresponse()
            if headers_received is not None:
                headers_received.set()
            result = response.status, response.read(), response.getheader("x-mock"), response.getheader("content-encoding")
            connection.close()
            return result

        def waiting(phase):
            for _ in range(100):
                rows = api("/paused")
                match = next((r for r in rows if r["state"] == "paused-" + phase), None)
                if match:
                    return api("/paused/" + match["id"])
                time.sleep(.03)
            raise AssertionError("No paused " + phase)

        def latest_flow(path):
            events = api("/events?after=0")["events"]
            return next(event["flow"] for event in reversed(events) if event["flow"]["url"] == url + path)

        def breakpoint(path="/*", request=True, response=True):
            return dict(id=secrets.token_hex(8), name="pause", kind="breakpoint", enabled=True,
                        host="127.0.0.1", path=path, method="POST", request=request, response=response)

        try:
            for _ in range(100):
                try:
                    if api("/health")["ready"]:
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise AssertionError("Engine startup failed")
            first = dict(id="first", name="mock", enabled=True, kind="mapLocal", host="127.0.0.1", path="/mock?*",
                         method="POST", file="first.mock", status=201, headers="Content-Type: application/json\nX-Mock: yes", delayMilliseconds=120)
            second = dict(first, id="second", file="second.mock")
            inline_body = '{"message":"สวัสดี","value":123456789012345678901}'
            (root / "mock-files/inline.mock").write_bytes(inline_body.encode("utf-8"))
            inline = dict(first, id="inline", path="/inline", file="inline.mock", bodySource="text", delayMilliseconds=0)
            api("/rules", [inline])
            assert send("/inline")[1] == inline_body.encode("utf-8")
            saved_inline = json.loads((root / "rules.json").read_text())
            assert saved_inline[0]["bodySource"] == "text"
            assert "message" not in json.dumps(saved_inline)
            print("PASS inline UTF-8 body via managed file; source metadata persisted without body payload")
            imported = dict(inline, urlPattern=url + "/imported?x=1", includeSubpaths=False)
            api("/rules", [imported])
            assert send("/imported?x=1")[1] == inline_body.encode("utf-8")
            assert send("/imported?x=2")[0] == 200
            api("/rules", [dict(imported, urlPattern="https" + url[4:] + "/imported?x=1")])
            assert send("/imported?x=1")[0] == 200, "Imported HTTPS rule matched HTTP"
            api("/rules", [dict(imported, urlPattern=url + "/nested/", includeSubpaths=True)])
            assert send("/nested/child")[1] == inline_body.encode("utf-8")
            api("/rules", [dict(imported, urlPattern="")], expected=400)
            Origin.seen.clear()
            print("PASS imported URL patterns: protocol, port, query and included subpaths")
            api("/rules", [first, second])
            began = time.monotonic()
            result = send("/mock?a=1")
            assert result[:3] == (201, b'{"local":1}', "yes"), result
            assert time.monotonic() - began >= .10
            assert not Origin.seen, "Map Local reached origin"
            mapped = latest_flow("/mock?a=1")
            assert mapped["mapLocal"] is True, mapped
            detail = api("/flow/" + mapped["id"])
            assert detail["summary"]["mapLocal"] is True, detail
            try:
                send("/mock?a=large", "x" * 1_200_000, timeout=2)
                raise AssertionError("Streaming Map Local request was not rejected")
            except (http.client.RemoteDisconnected, ConnectionResetError, BrokenPipeError, socket.timeout):
                pass
            assert not Origin.seen, "Streaming Map Local request reached origin"
            rejected = api("/events?after=0")["events"][-1]["flow"]
            assert rejected["state"] == "error" and "streaming upload cancelled" in rejected["error"]
            assert rejected["mapLocal"] is False, rejected
            api("/rules", [dict(first, enabled=False), second])
            assert send("/mock?a=1")[1] == b'{"local":2}'
            assert send("/unmatched")[0] == 200 and Origin.seen[-1][0] == "/unmatched"
            assert latest_flow("/unmatched")["mapLocal"] is False
            api("/rules", [dict(first, file="../escape")], expected=400)
            api("/rules", [dict(first, headers="invalid")], expected=400)
            (root / "mock-files/second.mock").unlink()
            assert send("/mock?a=1")[0] == 502
            assert latest_flow("/mock?a=1")["mapLocal"] is False
            print("PASS Map Local: order, disabled, match/query, delay, headers, missing file, validation")

            with ThreadPoolExecutor(max_workers=3) as pool:
                api("/rules", [breakpoint()])
                before = len(Origin.seen)
                future = pool.submit(send, "/before")
                edit = waiting("request")
                assert not future.done() and len(Origin.seen) == before
                stale = dict(edit)
                edit.update(url=url + "/after", headers=edit["headers"] + "\nX-Edit: edited", body='{"edited":true}')
                api("/resume", edit)
                response = waiting("response")
                assert not future.done()
                assert Origin.seen[-1] == ("/after", b'{"edited":true}', "edited"), Origin.seen[-1]
                api("/resume", stale, expected=400)
                response.update(status=202, body='{"response":"edited"}', headers=response["headers"] + "\nX-Mock: edited")
                api("/resume", response)
                assert future.result()[:3] == (202, b'{"response":"edited"}', "edited")
                print("PASS request and response: pause, URL/headers/body/status edits, framing, stale resume")

                api("/rules", [breakpoint(request=False)])
                headers_received = threading.Event()
                future = pool.submit(send, "/chunked", headers_received=headers_received)
                edit = waiting("response")
                try:
                    assert edit["body"] is not None, "Chunked JSON response body must be editable"
                    assert json.loads(edit["body"])["path"] == "/chunked"
                    assert not headers_received.is_set(), "Chunked response headers forwarded before Continue"
                    edit["body"] = '{"chunked":"edited"}'
                finally:
                    api("/resume", edit)
                assert future.result()[1] == b'{"chunked":"edited"}'
                print("PASS chunked JSON response body editable and changed bytes reach client")

                # Larger chunked bodies must still pause before any headers or
                # bytes reach the client, including the dynamic streaming switch.
                for path, size in (("/chunked-preview-limit", 300_000), ("/chunked-large", 1_200_000)):
                    headers_received = threading.Event()
                    future = pool.submit(send, path, headers_received=headers_received)
                    edit = waiting("response")
                    assert edit["body"] is None
                    assert not headers_received.is_set(), "Oversized chunked response bypassed breakpoint"
                    api("/resume", dict(edit, body="invalid replacement"), expected=400)
                    edit["headers"] += "\nX-Mock: chunked"
                    api("/resume", edit)
                    result = future.result()
                    assert result[1] == b"x" * size and result[2] == "chunked"

                headers_received = threading.Event()
                future = pool.submit(send, "/chunked-large", headers_received=headers_received)
                edit = waiting("response")
                assert not headers_received.is_set()
                api("/resume", dict(edit, cancel=True))
                try:
                    future.result()
                    raise AssertionError("Cancelled oversized chunked response reached client")
                except (http.client.RemoteDisconnected, ConnectionResetError):
                    pass
                assert not headers_received.is_set()
                print("PASS oversized chunked JSON: bounded buffering, pause before headers, preserve bytes, cancel")

                for path in ("/gzip", "/large"):
                    future = pool.submit(send, path)
                    edit = waiting("response")
                    assert edit["body"] is None
                    api("/resume", edit)
                    result = future.result()
                    if path == "/gzip":
                        assert gzip.decompress(result[1]) == b'{"original":true}' and result[3] == "gzip"
                    else:
                        assert len(result[1]) == 1_200_000
                print("PASS encoded/streamed bodies preserved; large response pauses before forwarding")

                api("/rules", [breakpoint(response=False)])
                future = pool.submit(send, "/cancel")
                edit = waiting("request")
                edit["cancel"] = True
                api("/resume", edit)
                try:
                    future.result()
                    raise AssertionError("Cancelled request reached client normally")
                except (http.client.RemoteDisconnected, ConnectionResetError):
                    pass
                assert not any(p == "/cancel" for p, _, _ in Origin.seen)
                print("PASS cancel blocks upstream")

                # A rejected edit must leave the flow paused and recoverable.
                future = pool.submit(send, "/invalid")
                edit = waiting("request")
                bad = dict(edit, headers="not a header")
                api("/resume", bad, expected=400)
                assert api("/paused/" + edit["id"])["phase"] == "request"
                edit["cancel"] = True
                api("/resume", edit)
                try:
                    future.result()
                    raise AssertionError("Cancelled invalid-edit flow completed")
                except (http.client.RemoteDisconnected, ConnectionResetError):
                    pass

                # Map Local still participates in response breakpoints.
                api("/rules", [first, breakpoint(path="/mock?*", request=False)])
                future = pool.submit(send, "/mock?a=2")
                edit = waiting("response")
                assert edit["body"] == '{"local":1}'
                api("/resume", edit)
                assert future.result()[1] == b'{"local":1}'
                print("PASS invalid edit stays paused and Map Local response can pause")

                # Large uploads must stop before the origin receives headers/body.
                api("/rules", [breakpoint(response=False)])
                before = len(Origin.seen)
                future = pool.submit(send, "/upload", "x" * 1_200_000)
                edit = waiting("request")
                assert edit["body"] is None and len(Origin.seen) == before
                api("/resume", edit)
                assert future.result()[0] == 200
                assert len(Origin.seen[-1][1]) == 1_200_000
                print("PASS large upload pauses before forwarding and preserves bytes")

                # Concurrent pauses remain independently editable and bounded.
                with ThreadPoolExecutor(max_workers=33) as clients:
                    futures = [clients.submit(send, "/bound") for _ in range(33)]
                    for _ in range(200):
                        pending = api("/paused")
                        if len(pending) == 32 and any(f.done() for f in futures):
                            break
                        time.sleep(.03)
                    else:
                        raise AssertionError("32-flow pause bound was not enforced")
                    for row in pending:
                        edit = api("/paused/" + row["id"])
                        edit["cancel"] = True
                        api("/resume", edit)
                    for future in futures:
                        try:
                            future.result()
                            raise AssertionError("Bound/cancel forwarded request")
                        except (http.client.RemoteDisconnected, ConnectionResetError):
                            pass
                assert not api("/paused")
                assert not any(p == "/bound" for p, _, _ in Origin.seen)
                print("PASS 32 independent paused flows; overflow and cancellation never forward")

                # Persisted rules apply after engine restart.
                api("/rules", [first])
                api("/shutdown", {})
                process.wait(timeout=8)
                process = subprocess.Popen(command, env=env, stdout=log, stderr=log)
                for _ in range(100):
                    try:
                        api("/health")
                        break
                    except OSError:
                        time.sleep(.05)
                assert send("/mock?a=1")[1] == b'{"local":1}'
                api("/rules", [breakpoint(response=False)])
                future = pool.submit(send, "/shutdown")
                waiting("request")
                api("/shutdown", {})
                try:
                    future.result()
                    raise AssertionError("Shutdown forwarded paused request")
                except (http.client.RemoteDisconnected, ConnectionResetError):
                    pass
                assert not any(p == "/shutdown" for p, _, _ in Origin.seen)
                process.wait(timeout=8)
                print("PASS persisted rules after restart and shutdown cancels paused requests")
        except BaseException:
            log.flush()
            print(api("/events?after=0"))
            print((root / "engine.log").read_text())
            raise
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=8)
            origin.shutdown()
            origin.server_close()
            log.close()


if __name__ == "__main__":
    main()
