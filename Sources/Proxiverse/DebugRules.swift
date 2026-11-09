import AppKit
import Foundation

enum DebugRuleKind: String, CaseIterable {
    case mapLocal, breakpoint

    var title: String { self == .mapLocal ? "Map Local" : "Breakpoint" }
    var symbol: String { self == .mapLocal ? "arrow.triangle.branch" : "pause.circle" }

    func rules(in all: [DebugRule]) -> [DebugRule] {
        all.filter { $0.kind == rawValue }
    }

    func replacingRules(in all: [DebugRule], with draft: [DebugRule]) throws -> [DebugRule] {
        guard draft.allSatisfy({ $0.kind == rawValue }) else {
            throw AppFailure("Only \(title) rules can be saved in this editor")
        }
        var replacements = draft.makeIterator()
        var result: [DebugRule] = []
        for rule in all {
            if rule.kind == rawValue {
                if let replacement = replacements.next() { result.append(replacement) }
            } else {
                result.append(rule)
            }
        }
        result.append(contentsOf: replacements)
        return result
    }
}

enum MockBodySource: String, Codable {
    case text, file
}

struct MapLocalPrefill {
    var rule: DebugRule
    var body: String? = nil
    var notice: String? = nil

    static func captured(_ flow: TrafficFlow, response: FlowMessage?) -> MapLocalPrefill {
        var rule = DebugRule.mapLocal(from: flow, response: response)
        rule.bodySource = .text
        guard let response else {
            return MapLocalPrefill(rule: rule, notice: "No captured response body is available. Enter a mock body before applying.")
        }
        guard !response.truncated, !response.streamed, response.captureState == .complete else {
            return MapLocalPrefill(rule: rule, notice: "Response body is incomplete, streamed, encoded, binary or lacks completeness metadata. It was not prefilled; enter the mock body yourself.")
        }
        return MapLocalPrefill(rule: rule, body: response.body)
    }
}

struct DebugRule: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "New rule"
    var enabled = true
    var kind = "mapLocal"
    var host = "*"
    var path = "/*"
    var method = "*"
    var file = ""
    var status = 200
    var headers = "Content-Type: application/json"
    var delayMilliseconds = 0
    var request = true
    var response = false
    var bodySource: MockBodySource? = nil
    var urlPattern: String? = nil
    var includeSubpaths: Bool? = nil

    static func breakpoint(from flow: TrafficFlow) -> DebugRule {
        var rule = DebugRule()
        rule.kind = "breakpoint"
        rule.name = "\(flow.method) \(flow.path)"
        rule.host = URLComponents(string: flow.url)?.host ?? flow.host
        rule.path = flow.path
        rule.method = flow.method
        return rule
    }

    static func mapLocal(from flow: TrafficFlow, response: FlowMessage? = nil) -> DebugRule {
        var rule = DebugRule()
        rule.name = "\(flow.method) \(flow.path)"
        rule.host = URLComponents(string: flow.url)?.host ?? flow.host
        rule.path = flow.path
        rule.method = flow.method
        rule.status = flow.status ?? 200
        if let response {
            let automatic = Set(["content-length", "transfer-encoding", "content-encoding", "connection", "keep-alive", "proxy-connection"])
            rule.headers = response.headers.filter { $0.count == 2 && !automatic.contains($0[0].lowercased()) }
                .map { "\($0[0]): \($0[1])" }.joined(separator: "\n")
        }
        return rule
    }
}

struct PausedEdit: Codable, Identifiable {
    var id: String
    var phase: String
    var url: String
    var method: String
    var status: Int
    var headers: String
    var body: String?
    var cancel = false
}

struct RuleStore {
    static let maximumMockBytes = 8 * 1024 * 1024
    let root: URL
    var file: URL { root.appendingPathComponent("rules.json") }
    var assets: URL { root.appendingPathComponent("mock-files", isDirectory: true) }

    func load() throws -> [DebugRule] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([DebugRule].self, from: Data(contentsOf: file))
    }

    func save(_ rules: [DebugRule]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(rules).write(to: file, options: .atomic)
    }

    func importFile(_ source: URL) throws -> String {
        let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, (size.fileSize ?? 0) <= Self.maximumMockBytes else {
            throw AppFailure("Choose a regular mock file up to 8 MiB")
        }
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = UUID().uuidString + ".mock"
        try FileManager.default.copyItem(at: source, to: assets.appendingPathComponent(name))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: assets.appendingPathComponent(name).path)
        return name
    }

    func readTextAsset(_ name: String) throws -> String {
        guard !name.isEmpty, URL(fileURLWithPath: name).lastPathComponent == name else {
            throw AppFailure("Invalid managed response file")
        }
        let url = assets.appendingPathComponent(name)
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, (size.fileSize ?? 0) <= Self.maximumMockBytes else {
            throw AppFailure("Response body exceeds 8 MiB")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumMockBytes, let text = String(data: data, encoding: .utf8) else {
            throw AppFailure("This response file is not UTF-8 text. Keep File mode for binary content.")
        }
        return text
    }

    func prepareRules(_ rules: [DebugRule], inlineBodies: [String: String]) throws -> [DebugRule] {
        guard rules.count <= 200 else { throw AppFailure("Maximum 200 rules") }
        var prepared = rules
        var created: [URL] = []
        do {
            for index in prepared.indices where prepared[index].kind == "mapLocal" && prepared[index].bodySource == .text {
                guard let body = inlineBodies[prepared[index].id] else { continue }
                let data = Data(body.utf8)
                guard data.count <= Self.maximumMockBytes else {
                    throw AppFailure("Body for \(prepared[index].name) exceeds 8 MiB")
                }
                try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let name = UUID().uuidString + ".mock"
                let url = assets.appendingPathComponent(name)
                created.append(url)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                prepared[index].file = name
            }
            try validate(prepared)
            return prepared
        } catch {
            let failure = error
            for url in created where FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch {
                    throw AppFailure("\(failure.localizedDescription). Could not remove unused mock file: \(error.localizedDescription)")
                }
            }
            throw failure
        }
    }

    func validate(_ rules: [DebugRule]) throws {
        guard rules.count <= 200 else { throw AppFailure("Maximum 200 rules") }
        for rule in rules {
            guard !rule.host.isEmpty, !rule.path.isEmpty, rule.host.count <= 1024, rule.path.count <= 8192 else {
                throw AppFailure("Enter host and path patterns (up to 1024 / 8192 characters)")
            }
            guard ["mapLocal", "breakpoint"].contains(rule.kind),
                  rule.method == "*" || rule.method.range(of: "^[A-Z]+$", options: .regularExpression) != nil else {
                throw AppFailure("Invalid rule type or HTTP method")
            }
            if let pattern = rule.urlPattern, pattern.isEmpty || pattern.count > 8192 {
                throw AppFailure("URL pattern must contain 1–8192 characters")
            }
            if rule.kind == "mapLocal" {
                guard (200...599).contains(rule.status), (0...60000).contains(rule.delayMilliseconds) else {
                    throw AppFailure("Status must be 200–599; delay must be 0–60000 ms")
                }
                for line in rule.headers.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    let allowed = CharacterSet(charactersIn: "!#$%&'*+.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-")
                    guard parts.count == 2, !parts[0].isEmpty,
                          parts[0].unicodeScalars.allSatisfy({ allowed.contains($0) }), !line.contains("\0") else {
                        throw AppFailure("Invalid header; use Name: value on each line")
                    }
                }
                guard !rule.file.isEmpty, URL(fileURLWithPath: rule.file).lastPathComponent == rule.file,
                      FileManager.default.fileExists(atPath: assets.appendingPathComponent(rule.file).path) else {
                    throw AppFailure("Choose a local response file for \(rule.name)")
                }
            } else if !rule.request && !rule.response {
                throw AppFailure("Choose request or response for \(rule.name)")
            }
        }
    }
}
