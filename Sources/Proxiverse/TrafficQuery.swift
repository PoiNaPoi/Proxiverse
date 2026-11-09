import Foundation

struct TrafficQuery: Equatable {
    enum Field: String, CaseIterable, Identifiable, Codable {
        case host, path, method, status, type, state
        var id: String { rawValue }
    }

    struct Term: Equatable {
        let field: Field
        let value: String
        var excluded: Bool
        fileprivate let statusRange: ClosedRange<Int>?

        init(field: Field, value: String, excluded: Bool = false) throws {
            guard !value.isEmpty else { throw AppFailure("Enter a value for \(field.rawValue)") }
            self.field = field
            self.value = value
            self.excluded = excluded
            if field == .status {
                let parts = value.split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(parts.count),
                      parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
                      let lower = Int(parts[0]), let upper = Int(parts.last!),
                      (100...599).contains(lower), (lower...599).contains(upper) else {
                    throw AppFailure("Status must be 100–599 or an ascending range such as 400-499")
                }
                statusRange = lower...upper
            } else {
                statusRange = nil
            }
            if field == .state, !["pending", "complete", "error", "paused-request", "paused-response"].contains(value.lowercased()) {
                throw AppFailure("Unknown state: \(value)")
            }
        }

        var text: String { "\(excluded ? "-" : "")\(field.rawValue):\(TrafficQuery.quote(value))" }

        func matches(_ flow: TrafficFlow) -> Bool {
            let included: Bool
            switch field {
            case .host: included = flow.host.caseInsensitiveCompare(value) == .orderedSame
            case .path: included = flow.path.localizedCaseInsensitiveContains(value)
            case .method: included = flow.method.caseInsensitiveCompare(value) == .orderedSame
            case .status: included = flow.status.map { statusRange?.contains($0) == true } ?? false
            case .type: included = flow.contentType?.localizedCaseInsensitiveContains(value) ?? false
            case .state: included = flow.state.caseInsensitiveCompare(value) == .orderedSame
            }
            return excluded ? !included : included
        }
    }

    var terms: [Term] = []
    var freeText = ""
    var text: String {
        (terms.map(\.text) + (freeText.isEmpty ? [] : [Self.quote(freeText)])).joined(separator: " ")
    }

    func matches(_ flow: TrafficFlow) -> Bool {
        terms.allSatisfy { $0.matches(flow) } &&
        (freeText.isEmpty || "\(flow.method) \(flow.url) \(flow.status.map(String.init) ?? "") \(flow.error ?? "")".localizedCaseInsensitiveContains(freeText))
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func parse(_ text: String) throws -> TrafficQuery {
        let chars = Array(text)
        var index = 0
        var result = TrafficQuery()
        var plain: [String] = []
        var structured = false
        var quotedPlain = false
        while index < chars.count {
            if chars[index].isWhitespace { index += 1; continue }
            let start = index
            var token = ""
            var quoted = false
            var hasQuote = false
            var colon: String.Index?
            while index < chars.count, quoted || !chars[index].isWhitespace {
                let char = chars[index]
                if char == "\"" {
                    quoted.toggle()
                    hasQuote = true
                } else if char == "\\", quoted {
                    index += 1
                    guard index < chars.count, chars[index] == "\"" || chars[index] == "\\" else {
                        throw AppFailure("Invalid escape at character \(index + 1)")
                    }
                    token.append(chars[index])
                } else {
                    if char == ":", !quoted, colon == nil { colon = token.endIndex }
                    token.append(char)
                }
                index += 1
            }
            guard !quoted else { throw AppFailure("Unclosed quote at character \(start + 1)") }
            if let colon {
                let prefix = String(token[..<colon])
                let excluded = prefix.hasPrefix("-")
                let name = excluded ? String(prefix.dropFirst()) : prefix
                // Preserve bare URLs, including http://, in legacy free-text search.
                if token[token.index(after: colon)...].hasPrefix("//"), !excluded {
                    plain.append(token)
                    continue
                }
                guard let field = Field(rawValue: name.lowercased()) else {
                    throw AppFailure("Unknown field '\(name)' at character \(start + 1)")
                }
                do {
                    result.terms.append(try Term(field: field, value: String(token[token.index(after: colon)...]), excluded: excluded))
                } catch {
                    throw AppFailure("\(error.localizedDescription) (character \(start + 1))")
                }
                structured = true
            } else {
                plain.append(token)
                quotedPlain = quotedPlain || hasQuote
            }
        }
        result.freeText = !structured && !quotedPlain ? text : plain.joined(separator: " ")
        return result
    }
}
