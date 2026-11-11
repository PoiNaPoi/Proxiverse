import XCTest
@testable import Reqnivo

final class UpstreamVerificationTests: XCTestCase {
    @MainActor
    func testRuntimeLANStartsWithDeviceApproval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["REQNIVO_DATA_DIR"]
        setenv("REQNIVO_DATA_DIR", root.path, 1)
        defer {
            if let previous { setenv("REQNIVO_DATA_DIR", previous, 1) }
            else { unsetenv("REQNIVO_DATA_DIR") }
            try? FileManager.default.removeItem(at: root)
        }
        let ports = try SystemProxy.command("/usr/bin/python3", ["-c", """
        import socket
        a, b = socket.socket(), socket.socket()
        a.bind(('127.0.0.1', 0)); b.bind(('127.0.0.1', 0))
        print(a.getsockname()[1], b.getsockname()[1])
        """]).split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let runtime = EngineRuntime()
        do {
            try await runtime.start(proxyPort: ports[0], apiPort: ports[1], lan: true)
            let api = try XCTUnwrap(runtime.api)
            let devices = try await api.get("/lan-devices", as: [LANDevice].self)
            XCTAssertTrue(devices.isEmpty)
            await runtime.stop()
        } catch {
            await runtime.stop()
            throw error
        }
    }

    @MainActor
    func testRuntimeRejectsUntrustedServerUntilBypassIsEnabled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = ProcessInfo.processInfo.environment["REQNIVO_DATA_DIR"]
        setenv("REQNIVO_DATA_DIR", root.appendingPathComponent("data").path, 1)
        defer {
            if let previous { setenv("REQNIVO_DATA_DIR", previous, 1) }
            else { unsetenv("REQNIVO_DATA_DIR") }
            try? FileManager.default.removeItem(at: root)
        }
        let key = root.appendingPathComponent("key.pem")
        let cert = root.appendingPathComponent("cert.pem")
        _ = try SystemProxy.command("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost", "-keyout", key.path, "-out", cert.path])
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", """
        import http.server, ssl, pathlib, sys
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'fixture-ok')
            def log_message(self, *args): pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(sys.argv[1], sys.argv[2])
        server.socket = context.wrap_socket(server.socket, server_side=True)
        pathlib.Path(sys.argv[3]).write_text(str(server.server_port))
        server.serve_forever()
        """, cert.path, key.path, root.appendingPathComponent("port").path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        let portFile = root.appendingPathComponent("port")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: portFile.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        let serverPort = try String(contentsOf: portFile)
        let ports = try SystemProxy.command("/usr/bin/python3", ["-c", """
        import socket
        a, b = socket.socket(), socket.socket()
        a.bind(('127.0.0.1', 0)); b.bind(('127.0.0.1', 0))
        print(a.getsockname()[1], b.getsockname()[1])
        """]).split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let runtime = EngineRuntime()
        for skip in [false, true, false] {
            do {
                try await runtime.start(proxyPort: ports[0], apiPort: ports[1], lan: false, skipUpstreamVerification: skip,
                                        httpsDecryptionHosts: ["localhost"])
                let body = root.appendingPathComponent("response")
                let status = try SystemProxy.command("/usr/bin/curl", ["--noproxy", "", "--proxy", "http://127.0.0.1:\(ports[0])",
                    "--cacert", runtime.paths.certificate.path, "--max-time", "10", "-sS", "-o", body.path, "-w", "%{http_code}",
                    "https://localhost:\(serverPort)/"])
                XCTAssertEqual(status, skip ? "200" : "502")
                let content = try String(contentsOf: body)
                if skip { XCTAssertEqual(content, "fixture-ok") }
                else { XCTAssertTrue(content.contains("Certificate verify failed")) }
                await runtime.stop()
            } catch {
                await runtime.stop()
                throw error
            }
        }
    }
}
