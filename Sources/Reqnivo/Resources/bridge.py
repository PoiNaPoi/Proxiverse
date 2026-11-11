"""Authenticated, loopback-only API for the Reqnivo native baseline.

Live Flow references are retained only while a breakpoint is paused. Bounded event metadata stays in RAM;
body previews are persisted in the private capture directory, fetched on demand.
"""
import certifi
import asyncio
from collections import deque
import json
import fnmatch
import ipaddress
import os
from pathlib import Path
import re
import secrets
import time
from urllib.parse import parse_qs, urlsplit

from mitmproxy import ctx, http
from mitmproxy.proxy.layers.http import HttpStream, HttpResponseHeadersHook

PREVIEW_BYTES = 256 * 1024
MAX_FLOWS = 10_000
MAX_EVENTS = 30_000
MAX_PREVIEW_DISK_BYTES = 128 * 1024 * 1024


class Bridge:
    def __init__(self):
        self.token = os.environ["REQNIVO_TOKEN"]
        self.lan_devices = {}
        self.https_hosts = self.validate_https_hosts(json.loads(os.environ.get("REQNIVO_HTTPS_HOSTS", "[]")))
        self.directory = Path(os.environ["REQNIVO_CAPTURE_DIR"])
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.rules_file = Path(os.environ.get("REQNIVO_RULES_FILE", str(self.directory.parent / "rules.json")))
        self.assets = self.rules_file.parent / "mock-files"
        self.rules = json.loads(self.rules_file.read_text()) if self.rules_file.exists() else []
        self.paused = {}
        self.events = deque(maxlen=MAX_EVENTS)
        self.flow_ids = deque()
        self.retained_ids = set()
        self.preview_sizes = {}
        self.preview_bytes = 0
        self.sequence = 0
        self.total = 0
        self.started = time.time()
        self.server = None
        self.watchdog = None
        self.parent_pid = int(os.environ.get("REQNIVO_PARENT_PID", "0"))

    def load(self, loader):
        # mitmproxy 12.2.3 has no addon hook before a buffered response switches
        # to streaming. Pause there so oversized chunked JSON cannot bypass a
        # breakpoint when stream_large_bodies is reached.
        self.original_response_stream = HttpStream.start_response_stream

        def start_response_stream(stream):
            if stream.flow.metadata.get("reqnivo_buffer_response"):
                yield HttpResponseHeadersHook(stream.flow)
                if (yield from stream.check_killed(True)):
                    return
            yield from self.original_response_stream(stream)

        self.response_stream_hook = start_response_stream
        HttpStream.start_response_stream = start_response_stream
        custom_ca = os.environ.get("REQNIVO_UPSTREAM_CA")
        if custom_ca:
            # A custom CA file replaces mitmproxy's defaults; retain the public roots.
            bundle = self.directory / "upstream-trust.pem"
            bundle.write_bytes(Path(certifi.where()).read_bytes() + b"\n" + Path(custom_ca).read_bytes())
            bundle.chmod(0o600)
            ctx.options.update(ssl_verify_upstream_trusted_ca=str(bundle))

    async def running(self):
        self.server = await asyncio.start_server(
            self.handle, "127.0.0.1", int(os.environ["REQNIVO_API_PORT"]), limit=16_384
        )
        self.watchdog = asyncio.create_task(self.watch_parent())

    async def watch_parent(self):
        while self.parent_pid:
            await asyncio.sleep(1)
            if os.getppid() != self.parent_pid:
                ctx.master.shutdown()
                return

    def done(self):
        if HttpStream.start_response_stream is self.response_stream_hook:
            HttpStream.start_response_stream = self.original_response_stream
        if self.server:
            self.server.close()
        if self.watchdog:
            self.watchdog.cancel()
        self.cancel_paused()

    def summary(self, flow):
        response = flow.response
        peer = getattr(getattr(flow, "client_conn", None), "peername", None)
        client = peer[0] if isinstance(peer, tuple) and peer and peer[0] else None
        return {
            "id": flow.id,
            "number": flow.metadata.get("reqnivo_number"),
            "client": client,
            "mapLocal": flow.metadata.get("reqnivo_map_local", False),
            "tlsPassthrough": flow.metadata.get("reqnivo_tls_passthrough", False),
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "host": flow.request.pretty_host,
            "status": response.status_code if response else None,
            "contentType": response.headers.get("content-type") if response else None,
            "state": "tls-passthrough" if flow.metadata.get("reqnivo_tls_passthrough") else ("error" if flow.error else ("paused-" + flow.metadata["reqnivo_phase"] if "reqnivo_phase" in flow.metadata else ("complete" if response else "pending"))),
            "started": flow.request.timestamp_start,
            "duration": max(0, (response.timestamp_end if response and response.timestamp_end else time.time()) - flow.request.timestamp_start),
            "size": len(response.raw_content) if response and response.raw_content is not None else None,
            "error": flow.metadata.get("reqnivo_error", str(flow.error)) if flow.error else None,
        }

    def emit(self, flow):
        self.sequence += 1
        self.events.append({"sequence": self.sequence, "flow": self.summary(flow)})

    @staticmethod
    def message(message):
        if message is None:
            return None
        raw = message.raw_content
        streamed = raw is None
        text = ""
        truncated = False
        capture_state = "streamed" if streamed else "complete"
        if not streamed:
            # Avoid decompressing arbitrarily large compressed bodies in the UI bridge.
            if message.headers.get("content-encoding", "identity").lower() not in ("", "identity"):
                text = "[Encoded body; preview omitted in baseline]"
                capture_state = "encoded"
            else:
                truncated = len(raw) > PREVIEW_BYTES
                capture_state = "truncated" if truncated else "complete"
                preview = raw[:PREVIEW_BYTES]
                content_type = message.headers.get("content-type", "")
                textual = any(value in content_type.lower() for value in ("text", "json", "xml", "javascript", "form-urlencoded"))
                if textual or not preview:
                    text = preview.decode("utf-8", errors="replace")
                else:
                    text = "[Binary body; preview omitted]"
                    capture_state = "binary"
        return {
            "headers": [list(pair) for pair in message.headers.items(multi=True)],
            "body": text,
            "truncated": truncated,
            "streamed": streamed,
            "httpVersion": message.http_version,
            "captureState": capture_state,
        }

    def persist(self, flow):
        detail = {
            "summary": self.summary(flow),
            "request": self.message(flow.request),
            "response": self.message(flow.response),
        }
        target = self.directory / (flow.id + ".json")
        temporary = target.with_suffix(".tmp")
        temporary.write_text(json.dumps(detail, ensure_ascii=True), encoding="utf-8")
        temporary.replace(target)
        self.preview_bytes -= self.preview_sizes.pop(flow.id, 0)
        self.preview_sizes[flow.id] = target.stat().st_size
        self.preview_bytes += self.preview_sizes[flow.id]
        while self.preview_bytes > MAX_PREVIEW_DISK_BYTES and self.preview_sizes:
            oldest = next(iter(self.preview_sizes))
            self.preview_bytes -= self.preview_sizes.pop(oldest)
            (self.directory / (oldest + ".json")).unlink(missing_ok=True)

    @staticmethod
    def validate_https_hosts(hosts):
        if not isinstance(hosts, list) or len(hosts) > 1000:
            raise ValueError("Maximum 1000 HTTPS hosts")
        result = set()
        for host in hosts:
            if not isinstance(host, str) or not host or len(host) > 253:
                raise ValueError("Invalid HTTPS host")
            host = host.lower().removesuffix(".")
            try:
                ipaddress.ip_address(host)
            except ValueError:
                if not all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) for label in host.split(".")):
                    raise ValueError("Use exact HTTPS hostnames without ports, paths, or wildcards")
            result.add(host)
        return result

    def tls_clienthello(self, data):
        address = data.context.server.address
        host = (data.client_hello.sni or (address[0] if address else "")).lower().rstrip(".")
        if host in self.https_hosts:
            return
        data.ignore_connection = True
        # A connection summary only: encrypted headers, paths, and bodies are never captured.
        flow = http.HTTPFlow(data.context.client, data.context.server)
        authority = "[" + host + "]" if ":" in host else host
        port = address[1] if address else 443
        flow.request = http.Request.make("CONNECT", f"https://{authority}:{port}/")
        flow.request.headers.clear()
        flow.metadata["reqnivo_tls_passthrough"] = True
        self.retain(flow)

    def retain(self, flow):
        self.total += 1
        flow.metadata["reqnivo_number"] = self.total
        self.flow_ids.append(flow.id)
        self.retained_ids.add(flow.id)
        while len(self.flow_ids) > MAX_FLOWS:
            old_id = self.flow_ids.popleft()
            self.retained_ids.discard(old_id)
            self.preview_bytes -= self.preview_sizes.pop(old_id, 0)
            (self.directory / (old_id + ".json")).unlink(missing_ok=True)
        self.persist(flow)
        self.emit(flow)

    @staticmethod
    def client_ip(client):
        address = ipaddress.ip_address(client.peername[0].split("%", 1)[0])
        if isinstance(address, ipaddress.IPv6Address):
            address = address.ipv4_mapped or address
        return str(address)

    def client_connected(self, client):
        if client.error:
            return
        ip = self.client_ip(client)
        if ipaddress.ip_address(ip).is_loopback or self.lan_devices.get(ip):
            return
        if ip not in self.lan_devices:
            # Bound pending discovery without evicting approved devices.
            if len(self.lan_devices) >= 64:
                pending = next((key for key, approved in self.lan_devices.items() if not approved), None)
                if pending:
                    del self.lan_devices[pending]
            if len(self.lan_devices) < 64:
                self.lan_devices[ip] = False
        client.error = "Approve this device in Reqnivo before connecting"

    def device_list(self):
        return [{"ip": ip, "approved": approved} for ip, approved in
                sorted(self.lan_devices.items(), key=lambda item: (item[1], item[0]))]

    def set_device_approval(self, payload):
        ip, approved = payload["ip"], payload["approved"]
        if not isinstance(ip, str) or ip not in self.lan_devices or not isinstance(approved, bool):
            raise ValueError("Choose a device that has requested access")
        self.lan_devices[ip] = approved
        if not approved:
            # Pinned mitmproxy 12.2.3: close both sides, including opaque CONNECT
            # tunnels and WebSockets which no longer pass through HTTP hooks.
            proxy = ctx.master.addons.get("proxyserver")
            for handler in list(proxy.connections.values()):
                if self.client_ip(handler.client) == ip:
                    handler.client.error = "LAN device approval revoked"
                    for io in list(handler.transports.values()):
                        if io.writer:
                            io.writer.close()
                        if io.handler:
                            io.handler.cancel("LAN device approval revoked")
            for flow in list(self.paused.values()):
                if self.client_ip(flow.client_conn) == ip:
                    self.paused.pop(flow.id, None)
                    flow.resume()
                    if flow.killable:
                        flow.kill()
        return self.device_list()

    def authorize_proxy(self, flow):
        # Discard any credentials cached by a client from an older app version.
        flow.request.headers.pop("Proxy-Authorization", None)
        ip = self.client_ip(flow.client_conn)
        if not ipaddress.ip_address(ip).is_loopback and not self.lan_devices.get(ip, False):
            flow.metadata["reqnivo_device_blocked"] = True
            flow.response = http.Response.make(403, b"Approve this device in Reqnivo")
            return False
        return True

    def http_connect(self, flow):
        self.authorize_proxy(flow)

    async def requestheaders(self, flow):
        if not self.authorize_proxy(flow):
            return
        self.retain(flow)
        flow.metadata["reqnivo_break_request"] = self.matches_breakpoint(flow, "request")
        if flow.metadata["reqnivo_break_request"] and self.will_stream(flow.request):
            flow.metadata["reqnivo_break_request"] = False
            await self.pause(flow, "request", headers_only=True)
        if not flow.error and self.will_stream(flow.request):
            # mitmproxy cannot synthesize a response for a streaming upload.
            # Reject these matches before any upstream connection is made.
            may_have_body = (flow.request.stream or "transfer-encoding" in flow.request.headers or
                             flow.request.method not in ("GET", "HEAD", "OPTIONS", "DELETE"))
            if may_have_body and any(r["kind"] == "mapLocal" and self.matches(r, flow) for r in self.rules):
                flow.kill()
                flow.metadata["reqnivo_error"] = "Map Local requires a request body with known size up to 1 MiB; streaming upload cancelled"
                self.update(flow)

    async def request(self, flow):
        if flow.metadata.get("reqnivo_device_blocked"):
            return
        self.update(flow)
        if flow.metadata.get("reqnivo_break_request"):
            await self.pause(flow, "request")
        if flow.error:
            return
        if not flow.response:
            await self.apply_map_local(flow)

    async def apply_map_local(self, flow):
        for rule in self.rules:
            if rule["kind"] == "mapLocal" and self.matches(rule, flow):
                try:
                    body = (self.assets / rule["file"]).read_bytes()
                    await asyncio.sleep(rule["delayMilliseconds"] / 1000)
                    headers = self.header_pairs(rule["headers"])
                    flow.response = http.Response.make(rule["status"], body, headers)
                    self.normalize_body(flow.response)
                    flow.metadata["reqnivo_map_local"] = True
                except OSError:
                    flow.response = http.Response.make(502, b"Reqnivo: Map Local file unavailable", {"content-type": "text/plain"})
                break

    async def responseheaders(self, flow):
        if flow.metadata.get("reqnivo_device_blocked"):
            return
        if flow.metadata.pop("reqnivo_buffer_response", False):
            flow.metadata["reqnivo_break_response"] = False
            await self.pause(flow, "response", headers_only=True)
            return
        flow.metadata["reqnivo_break_response"] = self.matches_breakpoint(flow, "response")
        if flow.metadata["reqnivo_break_response"] and self.will_stream(flow.response):
            headers = flow.response.headers
            if (not flow.response.stream and
                    headers.get("transfer-encoding", "").lower() == "chunked" and
                    "json" in headers.get("content-type", "").lower() and
                    headers.get("content-encoding", "identity").lower() in ("", "identity")):
                # Finite chunked JSON is not necessarily a streaming response.
                # Let the engine buffer it, retaining its existing 1 MiB bound.
                flow.metadata["reqnivo_buffer_response"] = True
                return
            flow.metadata["reqnivo_break_response"] = False
            await self.pause(flow, "response", headers_only=True)

    async def response(self, flow):
        if flow.metadata.get("reqnivo_device_blocked"):
            return
        flow.metadata.pop("reqnivo_buffer_response", None)
        # Synthetic Map Local responses may skip responseheaders.
        if flow.metadata.get("reqnivo_break_response", self.matches_breakpoint(flow, "response")):
            await self.pause(flow, "response")
        self.update(flow)

    def update(self, flow):
        # An unusually long-running flow may have aged out of the capture window.
        if flow.id not in self.retained_ids:
            return
        self.persist(flow)
        self.emit(flow)

    def error(self, flow):
        self.update(flow)

    @staticmethod
    def matches(rule, flow):
        if rule.get("urlPattern") is not None:
            pattern = rule["urlPattern"]
            if rule.get("includeSubpaths"):
                pattern += "*"
            return (rule["enabled"] and
                    (rule["method"] == "*" or rule["method"] == flow.request.method.upper()) and
                    fnmatch.fnmatchcase(flow.request.pretty_url, pattern))
        return (rule["enabled"] and
                (rule["method"] == "*" or rule["method"] == flow.request.method.upper()) and
                fnmatch.fnmatchcase(flow.request.host.lower(), rule["host"].lower()) and
                fnmatch.fnmatchcase(flow.request.path, rule["path"]))

    def matches_breakpoint(self, flow, phase):
        return any(rule["kind"] == "breakpoint" and rule[phase] and self.matches(rule, flow) for rule in self.rules)

    @staticmethod
    def will_stream(message):
        length = message.headers.get("content-length")
        # Unknown-length messages (including HTTP/2 uploads) may stream.
        # Stop at headers so no bytes can pass before the user continues.
        return int(length) > 1_000_000 if length and length.isdigit() else True

    async def pause(self, flow, phase, headers_only=False):
        # Bound retained live bodies; excess matches are rejected rather than silently forwarded.
        if len(self.paused) >= 32:
            flow.kill()
            self.update(flow)
            return
        flow.intercept()
        flow.metadata["reqnivo_phase"] = phase
        flow.metadata["reqnivo_headers_only"] = headers_only
        self.paused[flow.id] = flow
        self.update(flow)
        try:
            await flow.wait_for_resume()
        finally:
            self.paused.pop(flow.id, None)
            flow.metadata.pop("reqnivo_phase", None)
            flow.metadata.pop("reqnivo_headers_only", None)
            self.update(flow)

    @staticmethod
    def editable_body(message):
        raw = message.raw_content
        if raw is None or len(raw) > PREVIEW_BYTES or message.headers.get("content-encoding", "identity").lower() not in ("", "identity"):
            return None
        content_type = message.headers.get("content-type", "").lower()
        if raw and not any(part in content_type for part in ("text", "json", "xml", "javascript", "form-urlencoded")):
            return None
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return None

    def paused_detail(self, flow):
        phase = flow.metadata["reqnivo_phase"]
        message = flow.request if phase == "request" else flow.response
        return {"id": flow.id, "phase": phase, "url": flow.request.url,
                "method": flow.request.method, "status": flow.response.status_code if flow.response else 200,
                "headers": "\n".join(f"{k}: {v}" for k, v in message.headers.items(multi=True)),
                "body": None if flow.metadata.get("reqnivo_headers_only") else self.editable_body(message), "cancel": False}

    @staticmethod
    def header_pairs(text):
        pairs = []
        for line in text.splitlines():
            if not line.strip():
                continue
            key, sep, value = line.partition(":")
            if not sep or not re.fullmatch(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+", key) or "\r" in value or "\x00" in value:
                raise ValueError("Invalid header; use Name: value on each line")
            pairs.append((key.encode("ascii"), value.strip().encode("utf-8")))
        return pairs

    @staticmethod
    def normalize_body(message):
        # The engine handles transfer framing; calculate length from actual bytes.
        for key in ("content-length", "transfer-encoding"):
            message.headers.pop(key, None)
        if isinstance(message, http.Response) and message.status_code in (204, 304):
            message.raw_content = b""
            return
        if message.raw_content is not None:
            message.headers["content-length"] = str(len(message.raw_content))

    def resume_flow(self, payload):
        flow = self.paused.get(payload["id"])
        if not flow or flow.metadata["reqnivo_phase"] != payload["phase"]:
            raise ValueError("This breakpoint is no longer paused; reopen it")
        if payload["cancel"]:
            # Wake the async hook before kill clears intercepted. No await between them.
            flow.resume()
            flow.kill()
        else:
            phase = payload["phase"]
            original = flow.request if phase == "request" else flow.response
            message = original.copy()
            message.headers = http.Headers(self.header_pairs(payload["headers"]))
            if phase == "request":
                url = urlsplit(payload["url"])
                if url.scheme not in ("http", "https") or not url.hostname or url.username or url.password:
                    raise ValueError("Use an absolute HTTP or HTTPS URL")
                if not re.fullmatch(r"[A-Z]+", payload["method"]):
                    raise ValueError("Invalid HTTP method")
                message.url = payload["url"]
                message.method = payload["method"]
                # Keep HTTP/1 Host and HTTP/2 authority aligned with edited URL.
                message.host_header = url.netloc
            else:
                if not 200 <= payload["status"] <= 599:
                    raise ValueError("Response status must be 200–599")
                message.status_code = payload["status"]
            edited = payload.get("body")
            if edited is not None and edited != self.editable_body(original):
                if flow.metadata.get("reqnivo_headers_only") or self.editable_body(original) is None:
                    raise ValueError("This streamed, encoded or binary body cannot be edited")
                if len(edited.encode("utf-8")) > PREVIEW_BYTES:
                    raise ValueError("Edited body exceeds 256 KiB")
                message.headers.pop("content-encoding", None)
                message.raw_content = edited.encode("utf-8")
            if flow.metadata.get("reqnivo_headers_only") or original.raw_content is None:
                # At a headers-only pause, preserve framing for the bytes still to arrive.
                for key in ("content-length", "transfer-encoding", "content-encoding"):
                    message.headers.pop(key, None)
                    for value in original.headers.get_all(key):
                        message.headers.add(key, value)
            else:
                if self.editable_body(original) is None:
                    message.headers.pop("content-encoding", None)
                    for value in original.headers.get_all("content-encoding"):
                        message.headers.add("content-encoding", value)
                self.normalize_body(message)
            if phase == "request":
                flow.request = message
            else:
                flow.response = message
        # Remove immediately so a second click cannot resume a different phase.
        self.paused.pop(flow.id, None)
        flow.resume()

    def cancel_paused(self):
        for flow in list(self.paused.values()):
            flow.resume()
            if flow.killable:
                flow.kill()
        self.paused.clear()

    def validate_rules(self, rules):
        if not isinstance(rules, list) or len(rules) > 200:
            raise ValueError("Maximum 200 rules")
        for rule in rules:
            if rule["kind"] not in ("mapLocal", "breakpoint") or not rule["host"] or not rule["path"]:
                raise ValueError("Invalid rule type or empty host/path")
            if len(rule["host"]) > 1024 or len(rule["path"]) > 8192:
                raise ValueError("Rule pattern too long")
            if rule.get("urlPattern") is not None and (not rule["urlPattern"] or len(rule["urlPattern"]) > 8192):
                raise ValueError("URL pattern must contain 1–8192 characters")
            if rule["method"] != "*" and not re.fullmatch(r"[A-Z]+", rule["method"]):
                raise ValueError("Invalid HTTP method")
            if rule["kind"] == "breakpoint" and not (rule["request"] or rule["response"]):
                raise ValueError("Choose a request or response breakpoint")
            if rule["kind"] == "mapLocal":
                file = rule["file"]
                if not re.fullmatch(r"[A-Za-z0-9._-]+", file) or file in (".", ".."):
                    raise ValueError("Choose a managed mock file")
                if not (self.assets / file).is_file():
                    raise ValueError("Map Local file is missing")
                if not 200 <= rule["status"] <= 599 or not 0 <= rule["delayMilliseconds"] <= 60000:
                    raise ValueError("Invalid status or delay (0–60000 ms)")
                self.header_pairs(rule["headers"])
        return rules

    def websocket_message(self, flow):
        # Forwarding uses the engine's current message object. Keep only that
        # message so long-lived sockets do not accumulate an unused history.
        if flow.websocket:
            del flow.websocket.messages[:-1]

    async def handle(self, reader, writer):
        status = 200
        result = None
        try:
            head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=3)
            lines = head.decode("iso-8859-1").split("\r\n")
            method, target, _ = lines[0].split(" ", 2)
            headers = dict(line.split(":", 1) for line in lines[1:] if ":" in line)
            headers = {key.lower(): value.strip() for key, value in headers.items()}
            if not secrets.compare_digest(headers.get("authorization", ""), "Bearer " + self.token):
                status, result = 401, {"error": "Unauthorized"}
            elif headers.get("origin"):
                status, result = 403, {"error": "Browser origins are not allowed"}
            else:
                length = int(headers.get("content-length", "0"))
                if length < 0 or length > 2 * 1024 * 1024:
                    raise ValueError("Control body exceeds 2 MiB")
                payload = json.loads(await asyncio.wait_for(reader.readexactly(length), 3)) if length else None
                path = urlsplit(target)
                if method == "GET" and path.path == "/health":
                    result = {"ready": True, "apiVersion": 1, "total": self.total, "retained": len(self.flow_ids), "uptime": time.time() - self.started, "previewBytes": self.preview_bytes}
                elif method == "GET" and path.path == "/lan-devices":
                    result = self.device_list()
                elif method == "POST" and path.path == "/lan-devices":
                    result = self.set_device_approval(payload)
                elif method == "GET" and path.path == "/events":
                    cursor = int(parse_qs(path.query).get("after", ["0"])[0])
                    gap = bool(self.events and cursor < self.events[0]["sequence"] - 1)
                    events = [event for event in self.events if event["sequence"] > cursor][:1000]
                    result = {"events": events, "cursor": events[-1]["sequence"] if events else self.sequence, "gap": gap, "total": self.total}
                elif method == "GET" and re.fullmatch(r"/flow/[a-zA-Z0-9-]{1,80}", path.path):
                    file = self.directory / (path.path.rsplit("/", 1)[1] + ".json")
                    if file.exists():
                        result = json.loads(file.read_text(encoding="utf-8"))
                    else:
                        status, result = 404, {"error": "Flow no longer retained"}
                elif method == "POST" and path.path == "/rules":
                    rules = self.validate_rules(payload)
                    temp = self.rules_file.with_suffix(".tmp")
                    temp.write_text(json.dumps(rules), encoding="utf-8")
                    temp.replace(self.rules_file)
                    self.rules = rules
                    result = {"saved": True}
                elif method == "POST" and path.path == "/https-decryption":
                    self.https_hosts = self.validate_https_hosts(payload)
                    result = {"saved": True}
                elif method == "GET" and path.path == "/paused":
                    result = [self.summary(flow) for flow in self.paused.values()]
                elif method == "GET" and re.fullmatch(r"/paused/[a-zA-Z0-9-]{1,80}", path.path):
                    flow = self.paused.get(path.path.rsplit("/", 1)[1])
                    if not flow:
                        status, result = 404, {"error": "Breakpoint no longer paused"}
                    else:
                        result = self.paused_detail(flow)
                elif method == "POST" and path.path == "/resume":
                    self.resume_flow(payload)
                    result = {"resumed": True}
                elif method == "POST" and path.path == "/shutdown":
                    self.cancel_paused()
                    result = {"stopping": True}
                    asyncio.get_running_loop().call_later(0.1, ctx.master.shutdown)
                else:
                    status, result = 404, {"error": "Not found"}
        except (ValueError, KeyError, TypeError, asyncio.TimeoutError, asyncio.LimitOverrunError, asyncio.IncompleteReadError) as error:
            status, result = 400, {"error": str(error) or "Invalid request"}
        except Exception:
            status, result = 500, {"error": "Bridge failed"}
        try:
            body = json.dumps(result, ensure_ascii=True).encode("utf-8")
            writer.write(f"HTTP/1.1 {status} Response\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".encode() + body)
            await writer.drain()
        except (ConnectionError, BrokenPipeError):
            pass
        finally:
            writer.close()
            await writer.wait_closed()


addons = [Bridge()]
