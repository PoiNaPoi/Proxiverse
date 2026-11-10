import Foundation
import Security
import SystemConfiguration

struct ProxyEndpoint: Codable, Equatable {
    let enabled: Bool
    let server: String
    let port: Int
    let authenticated: Bool

    init(enabled: Bool, server: String, port: Int, authenticated: Bool) {
        self.enabled = enabled
        self.server = server
        self.port = port
        self.authenticated = authenticated
    }

    init(output: String) throws {
        let fields = Dictionary(output.split(separator: "\n").compactMap { line -> (String, String)? in
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return (pair[0], pair[1].trimmingCharacters(in: .whitespaces))
        }, uniquingKeysWith: { _, latest in latest })
        guard let enabled = fields["Enabled"], let port = Int(fields["Port"] ?? "") else {
            throw AppFailure("Cannot read the existing macOS proxy settings")
        }
        self.enabled = enabled == "Yes"
        self.server = fields["Server"] ?? ""
        self.port = port
        authenticated = fields["Authenticated Proxy Enabled"] == "1"
    }
}

struct ProxyJournal: Codable {
    let service: String
    let http: ProxyEndpoint
    let https: ProxyEndpoint
    let installedPort: Int
}

enum SystemProxy {
    struct Change: Equatable {
        let secure: Bool
        let endpoint: ProxyEndpoint
    }

    static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw AppFailure(output) }
        return output
    }

    static func services() throws -> [String] {
        try command("/usr/sbin/networksetup", ["-listallnetworkservices"])
            .split(separator: "\n").dropFirst().map(String.init).filter { !$0.hasPrefix("*") }
    }

    static func read(_ service: String, secure: Bool) throws -> ProxyEndpoint {
        try ProxyEndpoint(output: command("/usr/sbin/networksetup", [secure ? "-getsecurewebproxy" : "-getwebproxy", service]))
    }

    static func journalURL(_ paths: RuntimePaths) -> URL { paths.root.appendingPathComponent("proxy-recovery.json") }

    // Ask macOS for network configuration rights directly. AppleScript's generic
    // script-elevation dialog cannot offer the native network authorization flow.
    static func write(service: String, changes: [Change]) throws {
        var authorization: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw AppFailure("Cannot authorize Mac proxy changes (\(status)).")
        }
        defer { AuthorizationFree(authorization, []) }
        guard let preferences = SCPreferencesCreateWithAuthorization(nil, "Reqnivo" as CFString, nil, authorization) else {
            throw configurationError()
        }
        guard SCPreferencesLock(preferences, true) else { throw configurationError() }
        defer { SCPreferencesUnlock(preferences) }
        let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []
        guard let selected = services.first(where: { (SCNetworkServiceGetName($0) as String?) == service }),
              let proxies = SCNetworkServiceCopyProtocol(selected, kSCNetworkProtocolTypeProxies) else {
            throw AppFailure("Cannot find proxy settings for network service \(service).")
        }
        let current = SCNetworkProtocolGetConfiguration(proxies) as? [String: Any] ?? [:]
        let updated = configuration(current, applying: changes)
        guard SCNetworkProtocolSetConfiguration(proxies, updated as CFDictionary),
              SCPreferencesCommitChanges(preferences),
              SCPreferencesApplyChanges(preferences) else { throw configurationError() }
    }

    static func configuration(_ current: [String: Any], applying changes: [Change]) -> [String: Any] {
        var result = current
        for change in changes {
            let endpoint = change.endpoint
            let enabledKey = change.secure ? kSCPropNetProxiesHTTPSEnable : kSCPropNetProxiesHTTPEnable
            let serverKey = change.secure ? kSCPropNetProxiesHTTPSProxy : kSCPropNetProxiesHTTPProxy
            let portKey = change.secure ? kSCPropNetProxiesHTTPSPort : kSCPropNetProxiesHTTPPort
            result[enabledKey as String] = endpoint.enabled ? 1 : 0
            if !endpoint.server.isEmpty && endpoint.port > 0 {
                result[serverKey as String] = endpoint.server
                result[portKey as String] = endpoint.port
            }
        }
        return result
    }

    private static func configurationError() -> AppFailure {
        let status = SCError()
        return AppFailure("Mac proxy configuration failed: \(String(cString: SCErrorString(status))) (\(status)).")
    }

    static func enable(service: String, port: Int, paths: RuntimePaths) throws {
        let file = journalURL(paths)
        guard !FileManager.default.fileExists(atPath: file.path) else { throw AppFailure("Restore the previous proxy settings before starting another Mac capture") }
        let journal = try ProxyJournal(service: service, http: read(service, secure: false), https: read(service, secure: true), installedPort: port)
        guard !journal.http.authenticated, !journal.https.authenticated else {
            throw AppFailure("The existing proxy requires authentication. Use manual proxy setup to preserve its credentials.")
        }
        try JSONEncoder().encode(journal).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        do {
            let endpoint = ProxyEndpoint(enabled: true, server: "127.0.0.1", port: port, authenticated: false)
            try write(service: service, changes: [Change(secure: false, endpoint: endpoint), Change(secure: true, endpoint: endpoint)])
        } catch {
            // Preserve the journal even after a partial write or denied authorization.
            throw AppFailure("Mac proxy setup did not finish: \(error.localizedDescription). Use Restore Mac Proxy before closing.")
        }
    }

    static func restore(paths: RuntimePaths) throws {
        let file = journalURL(paths)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let journal = try JSONDecoder().decode(ProxyJournal.self, from: Data(contentsOf: file))
        let plan = recoveryPlan(journal: journal,
                                currentHTTP: try read(journal.service, secure: false),
                                currentHTTPS: try read(journal.service, secure: true))
        if !plan.changes.isEmpty { try write(service: journal.service, changes: plan.changes) }
        guard plan.conflicts.isEmpty else {
            throw AppFailure("Proxy settings changed outside Reqnivo (\(plan.conflicts.joined(separator: ", "))). Owned settings were restored; review System Settings. Recovery record preserved.")
        }
        try FileManager.default.removeItem(at: file)
    }

    static func recoveryPlan(journal: ProxyJournal, currentHTTP: ProxyEndpoint, currentHTTPS: ProxyEndpoint) -> (changes: [Change], conflicts: [String]) {
        var changes: [Change] = []
        var conflicts: [String] = []
        for (secure, previous, current) in [(false, journal.http, currentHTTP), (true, journal.https, currentHTTPS)] {
            if current == previous || (!current.enabled && !previous.enabled) { continue }
            // Restore only endpoints that still point at this capture. A change to
            // one endpoint must not prevent restoring the other owned endpoint.
            guard current.server == "127.0.0.1", current.port == journal.installedPort else {
                conflicts.append(secure ? "HTTPS" : "HTTP")
                continue
            }
            changes.append(Change(secure: secure, endpoint: previous))
        }
        return (changes, conflicts)
    }
}
