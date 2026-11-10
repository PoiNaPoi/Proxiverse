import Foundation

/// Portable exports contain response bytes, never paths to files on another machine.
enum MapLocalTransfer {
    struct Entry: Codable {
        var rule: DebugRule
        var body: Data
    }

    private struct Archive: Codable {
        var format = "Reqnivo.MapLocal"
        var version = 1
        var entries: [Entry]
    }

    static func export(_ draft: RuleWorkspaceDraft, store: RuleStore, selectedIDs: Set<String>? = nil) throws -> Data {
        let rules = draft.rules.filter { selectedIDs?.contains($0.id) ?? true }
        guard !rules.isEmpty else { throw AppFailure("Select at least one Map Local rule to export") }
        let entries = try rules.map { rule -> Entry in
            guard rule.kind == "mapLocal" else { throw AppFailure("Export only supports Map Local rules") }
            var portable = rule
            let body: Data
            if rule.bodySource == .text, let text = draft.textBodies[rule.id] {
                body = Data(text.utf8)
            } else {
                guard !rule.file.isEmpty, URL(fileURLWithPath: rule.file).lastPathComponent == rule.file else {
                    throw AppFailure("Choose a response body for \(rule.name) before exporting")
                }
                let url = store.assets.appendingPathComponent(rule.file)
                guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= RuleStore.maximumMockBytes else {
                    throw AppFailure("Response body exceeds 8 MiB")
                }
                body = try Data(contentsOf: url)
            }
            guard body.count <= RuleStore.maximumMockBytes else { throw AppFailure("Response body exceeds 8 MiB") }
            portable.file = ""
            return Entry(rule: portable, body: body)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Archive(entries: entries))
    }

    static func decode(_ data: Data) throws -> [Entry] {
        let object = try JSONSerialization.jsonObject(with: data)
        let entries: [Entry]
        if let root = object as? [String: Any], root["format"] != nil {
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.format == "Reqnivo.MapLocal", archive.version == 1 else {
                throw AppFailure("Unsupported Map Local export version")
            }
            entries = archive.entries
        } else {
            var tree = object
            if let root = object as? [String: Any], let map = root["mapLocalData"] as? [String: Any],
               let encoded = map["data"] as? String, let bytes = Data(base64Encoded: encoded) {
                tree = try JSONSerialization.jsonObject(with: bytes)
            }
            guard let nodes = tree as? [[String: Any]] else {
                throw AppFailure("Choose a Reqnivo Map Local export or a Map Local .config file")
            }
            entries = try mapLocalNodes(nodes, enabled: true)
        }
        guard !entries.isEmpty, entries.count <= 200 else { throw AppFailure("Import requires 1–200 Map Local rules") }
        guard entries.allSatisfy({ $0.rule.kind == "mapLocal" && $0.body.count <= RuleStore.maximumMockBytes }) else {
            throw AppFailure("Invalid Map Local rule or response body exceeds 8 MiB")
        }
        return entries
    }

    /// Validate the complete batch before adding anything to the editor. Roll back staged assets on failure.
    static func append(_ entries: [Entry], to draft: RuleWorkspaceDraft, store: RuleStore,
                       otherRuleCount: Int) throws -> RuleWorkspaceDraft {
        guard draft.rules.count + entries.count + otherRuleCount <= 200 else { throw AppFailure("Maximum 200 rules") }
        var result = draft
        var created: [URL] = []
        do {
            try FileManager.default.createDirectory(at: store.assets, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var imported: [DebugRule] = []
            for entry in entries {
                guard entry.rule.kind == "mapLocal", entry.body.count <= RuleStore.maximumMockBytes else {
                    throw AppFailure("Invalid Map Local rule or response body exceeds 8 MiB")
                }
                var rule = entry.rule
                rule.id = UUID().uuidString
                rule.file = UUID().uuidString + ".mock"
                // Keep bytes unchanged; text bodies can be opened in the editor on selection.
                if rule.bodySource == .text, String(data: entry.body, encoding: .utf8) == nil { rule.bodySource = .file }
                let url = store.assets.appendingPathComponent(rule.file)
                created.append(url)
                try entry.body.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                imported.append(rule)
            }
            try store.validate(imported)
            for rule in imported { result.add(rule) }
            return result
        } catch {
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    private static func mapLocalNodes(_ nodes: [[String: Any]], enabled: Bool) throws -> [Entry] {
        var result: [Entry] = []
        for node in nodes {
            guard let type = node["nodeType"] as? [String: Any] else { throw AppFailure("Invalid Map Local tree") }
            if let folder = (type["folder"] as? [String: Any])?["_0"] as? [String: Any],
               let children = folder["entries"] as? [[String: Any]] {
                result += try mapLocalNodes(children, enabled: enabled && (folder["isEnabled"] as? Bool ?? true))
            } else if let rule = (type["node"] as? [String: Any])?["_0"] as? [String: Any] {
                result += try mapLocalRule(rule, enabled: enabled)
            } else { throw AppFailure("Invalid Map Local node") }
            guard result.count <= 200 else { throw AppFailure("Maximum 200 rules") }
        }
        return result
    }

    private static func mapLocalRule(_ source: [String: Any], enabled: Bool) throws -> [Entry] {
        let name = source["name"] as? String ?? "Imported response"
        guard source["regex"] as? String == "useWildcard",
              source["isDirectoryFileEnable"] as? Bool != true,
              source["isLocalFileEnable"] as? Bool == true,
              (source["graphQLQueryName"] as? String ?? "").isEmpty else {
            throw AppFailure("\(name): Regex, Directory and GraphQL rules are not supported")
        }
        guard let url = source["url"] as? String, !url.isEmpty, url.count <= 8192,
              let local = source["localFile"] as? [String: Any],
              let encoded = local["importFileData"] as? String, let bytes = Data(base64Encoded: encoded) else {
            throw AppFailure("\(name): missing embedded response. Export the rule with its response file embedded")
        }
        var rule = DebugRule()
        rule.name = name
        rule.enabled = enabled && (source["isEnabled"] as? Bool ?? true)
        rule.urlPattern = url
        rule.includeSubpaths = source["isIncludingPaths"] as? Bool ?? false
        rule.host = URLComponents(string: url)?.host ?? "*"
        rule.path = URLComponents(string: url)?.percentEncodedPath ?? "/*"
        if rule.path.isEmpty { rule.path = "/" }
        rule.bodySource = .file
        let body = try response(bytes, rule: &rule)
        guard let method = source["method"] as? [String: Any] else { throw AppFailure("\(name): missing HTTP method") }
        let methods: [String]
        if method["any"] != nil { methods = ["*"] }
        else if let exact = method["exact"] as? [[String: Any]], !exact.isEmpty,
                exact.allSatisfy({ $0["name"] is String }) { methods = exact.compactMap { $0["name"] as? String } }
        else { throw AppFailure("\(name): unsupported HTTP method") }
        return methods.map { method in
            var copy = rule
            copy.method = method
            return Entry(rule: copy, body: body)
        }
    }

    private static func response(_ bytes: Data, rule: inout DebugRule) throws -> Data {
        guard bytes.starts(with: Data("HTTP/".utf8)) else { return bytes }
        let separator = bytes.range(of: Data("\r\n\r\n".utf8)) ?? bytes.range(of: Data("\n\n".utf8))
        guard let separator, let head = String(data: bytes[..<separator.lowerBound], encoding: .utf8) else {
            throw AppFailure("\(rule.name): invalid HTTP response")
        }
        let lines = head.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let first = lines.first, let status = Int(first.split(separator: " ").dropFirst().first ?? "") else {
            throw AppFailure("\(rule.name): invalid HTTP status")
        }
        rule.status = status
        let framing = Set(["content-length", "transfer-encoding", "connection", "keep-alive", "proxy-connection"])
        rule.headers = lines.dropFirst().filter { line in
            !framing.contains(String(line.split(separator: ":", maxSplits: 1).first ?? "").lowercased())
        }.joined(separator: "\n")
        let body = Data(bytes[separator.upperBound...])
        if body.range(of: Data("<FILE_URL=".utf8)) != nil {
            throw AppFailure("\(rule.name): external FILE_URL responses must be embedded before importing")
        }
        return body
    }
}
