import AppKit
import Foundation

struct RuntimePaths {
    let root: URL
    var certificate: URL { root.appendingPathComponent("ca/mitmproxy-ca-cert.pem") }
    var captureRoot: URL { root.appendingPathComponent("captures", isDirectory: true) }

    init() {
        if let override = ProcessInfo.processInfo.environment["REQNIVO_DATA_DIR"] {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Reqnivo", isDirectory: true)
        }
    }

    func prepare() throws {
        for directory in [root, root.appendingPathComponent("ca"), captureRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
    }

    static func engine() throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Engine/mitmproxy.app/Contents/MacOS/mitmdump"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("vendor/mitmproxy.app/Contents/MacOS/mitmdump")
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw AppFailure("Engine not found. Run scripts/fetch-engine.sh, then scripts/build-app.sh.")
        }
        return url
    }
}

actor EngineAPI {
    let port: Int
    let token: String
    let session: URLSession

    init(port: Int, token: String) {
        self.port = port
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 3
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await request(path)
        return try JSONDecoder().decode(type, from: data)
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { throw AppFailure("Invalid control URL") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw AppFailure(reason ?? "Engine API rejected the request")
        }
        return data
    }
}

@MainActor
final class EngineRuntime {
    private(set) var process: Process?
    private(set) var api: EngineAPI?
    private(set) var captureDirectory: URL?
    private var logHandle: FileHandle?
    private var lockDescriptor: Int32 = -1
    let paths = RuntimePaths()

    func start(proxyPort: Int, apiPort: Int, lan: Bool, skipUpstreamVerification: Bool = false,
               httpsDecryptionHosts: [String] = []) async throws {
        guard process == nil else { throw AppFailure("Engine is already running") }
        guard (1024...65535).contains(proxyPort), (1024...65535).contains(apiPort), proxyPort != apiPort else {
            throw AppFailure("Use different proxy/control ports between 1024 and 65535")
        }
        try paths.prepare()
        if lockDescriptor < 0 {
            let descriptor = Darwin.open(paths.root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else { throw AppFailure("Cannot open application data lock") }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(descriptor)
                throw AppFailure("Another Reqnivo capture is using this data directory")
            }
            lockDescriptor = descriptor
            // No other capture can own this directory while the lock is held.
            for old in try FileManager.default.contentsOfDirectory(at: paths.captureRoot, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: old)
            }
        }
        let directory = paths.captureRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        captureDirectory = directory
        let token = UUID().uuidString + UUID().uuidString
        let process = Process()
        process.executableURL = try RuntimePaths.engine()
        guard let addon = AppResources.bundle.url(forResource: "bridge", withExtension: "py") else { throw AppFailure("Missing bridge addon") }
        process.arguments = ["-q", "-s", addon.path, "--listen-host", lan ? "0.0.0.0" : "127.0.0.1",
                             "--listen-port", String(proxyPort), "--set", "confdir=\(paths.root.appendingPathComponent("ca").path)",
                             "--set", "ssl_insecure=\(skipUpstreamVerification)",
                             "--set", "stream_large_bodies=1m", "--set", "block_global=true", "--set", "connection_strategy=lazy"]
        var environment = ProcessInfo.processInfo.environment
        let upstreamCA = UpstreamCAStore(root: paths.root)
        if upstreamCA.isConfigured && !skipUpstreamVerification {
            environment["REQNIVO_UPSTREAM_CA"] = upstreamCA.file.path
        } else {
            environment.removeValue(forKey: "REQNIVO_UPSTREAM_CA")
        }
        environment["REQNIVO_RULES_FILE"] = paths.root.appendingPathComponent("rules.json").path
        environment["REQNIVO_TOKEN"] = token
        environment["REQNIVO_HTTPS_HOSTS"] = String(decoding: try JSONEncoder().encode(httpsDecryptionHosts), as: UTF8.self)
        environment["REQNIVO_API_PORT"] = String(apiPort)
        environment["REQNIVO_CAPTURE_DIR"] = directory.path
        environment["REQNIVO_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        let log = paths.root.appendingPathComponent("engine.log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        logHandle = try FileHandle(forWritingTo: log)
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        self.process = process
        let api = EngineAPI(port: apiPort, token: token)
        self.api = api
        for _ in 0..<80 {
            if !process.isRunning {
                let logText = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                await stop()
                throw AppFailure("Engine exited during startup. \(logText.suffix(1500))")
            }
            if let health = try? await api.get("/health", as: EngineHealth.self), health.ready {
                try health.validateVersion()
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        await stop()
        throw AppFailure("Engine startup timed out. See engine.log in \(paths.root.path).")
    }

    func stop() async {
        if let api { _ = try? await api.request("/shutdown", method: "POST") }
        if let process {
            for _ in 0..<30 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning { process.terminate() }
            for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process = nil
        api = nil
        try? logHandle?.close()
        logHandle = nil
        // Keep previews available until the next capture or application termination.
    }

    deinit {
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }

    func discardCapture() {
        if let captureDirectory { try? FileManager.default.removeItem(at: captureDirectory) }
        captureDirectory = nil
    }
}
