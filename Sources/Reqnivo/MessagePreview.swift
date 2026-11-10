import AppKit

struct MessagePresentation {
    let headers: NSAttributedString
    let body: NSAttributedString
    let copyText: String
    let isJSON: Bool
    let folds: [JSONFoldRegion]
}

enum MessagePreview {
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    enum SyntaxColor: Sendable {
        case purple, green, orange, blue, secondary

        var nsColor: NSColor {
            switch self {
            case .purple: return .systemPurple
            case .green: return .systemGreen
            case .orange: return .systemOrange
            case .blue: return .systemBlue
            case .secondary: return .secondaryLabelColor
            }
        }
    }

    struct Highlight: Equatable, Sendable {
        let range: NSRange
        let color: SyntaxColor
    }

    static func render(_ message: FlowMessage) -> MessagePresentation {
        let formatted = message.truncated || message.streamed ? nil : prettyJSON(message.body)
        let body = formatted ?? message.body
        return MessagePresentation(headers: highlightedHeaders(message),
                                   body: formatted == nil ? plain(body) : highlightedJSON(body),
                                   copyText: body, isJSON: formatted != nil,
                                   folds: formatted.map(JSONFolding.regions) ?? [])
    }

    // Validate with Foundation, but format the original tokens. Re-serializing
    // parsed numbers can change large IDs or decimal precision in API payloads.
    static func prettyJSON(_ text: String, maximumBytes: Int = 2 * 1024 * 1024) -> String? {
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { return nil }
        let source = text as NSString
        let values = tokenRanges(text).map { source.substring(with: $0) }
        var output = ""
        var depth = 0
        for (index, value) in values.enumerated() {
            switch value {
            case "{", "[":
                output += value
                depth += 1
                if index + 1 < values.count, values[index + 1] != "}", values[index + 1] != "]" {
                    output += "\n" + String(repeating: "  ", count: depth)
                }
            case "}", "]":
                depth -= 1
                if index > 0, values[index - 1] != "{", values[index - 1] != "[" {
                    output += "\n" + String(repeating: "  ", count: depth)
                }
                output += value
            case ",": output += ",\n" + String(repeating: "  ", count: depth)
            case ":": output += ": "
            default: output += value
            }
            // Pathological nesting can expand a small captured body enormously.
            if output.utf8.count > maximumBytes { return nil }
        }
        return output
    }

    // ICU can stop matching very long strings. Scan their UTF-16 ranges directly,
    // including unfinished strings while editing, without losing their contents.
    private static func tokenRanges(_ text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?
        var quoted = false
        var escaped = false
        func append(endingAt end: Int) {
            if let beginning = start {
                ranges.append(NSRange(location: beginning, length: end - beginning))
                start = nil
            }
        }
        for (offset, unit) in text.utf16.enumerated() {
            if quoted {
                if escaped { escaped = false }
                else if unit == 92 { escaped = true }
                else if unit == 34 {
                    append(endingAt: offset + 1)
                    quoted = false
                }
            } else if unit == 32 || unit == 9 || unit == 10 || unit == 13 || (offset == 0 && unit == 0xFEFF) {
                append(endingAt: offset)
            } else if unit == 34 {
                start = offset
                quoted = true
            } else if [UInt16(123), 125, 91, 93, 58, 44].contains(unit) {
                append(endingAt: offset)
                ranges.append(NSRange(location: offset, length: 1))
            } else if start == nil { start = offset }
        }
        append(endingAt: text.utf16.count)
        return ranges
    }

    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }

    static func highlightedJSON(_ text: String) -> NSAttributedString {
        attributed(text, highlights: jsonHighlights(text))
    }

    static func jsonHighlights(_ text: String) -> [Highlight] {
        let source = text as NSString
        let ranges = tokenRanges(text)
        return ranges.enumerated().compactMap { index, range in
            let value = source.substring(with: range)
            let color: SyntaxColor
            if value.hasPrefix("\"") {
                let isKey = index + 1 < ranges.count && source.substring(with: ranges[index + 1]) == ":"
                color = isKey ? .purple : .green
            } else if value == "true" || value == "false" {
                color = .blue
            } else if value == "null" {
                color = .secondary
            } else if value.first?.isNumber == true || value.hasPrefix("-") {
                color = .orange
            } else if value.count == 1, "{}[]:,".contains(value) {
                color = .secondary
            } else { return nil }
            return Highlight(range: range, color: color)
        }
    }

    static func highlightedHeaders(_ message: FlowMessage) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        func append(_ text: String, color: NSColor) {
            output.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        append(message.httpVersion + "\n\n", color: .systemOrange)
        for header in message.headers where header.count == 2 {
            append(header[0], color: SyntaxColor.blue.nsColor)
            append(": ", color: .secondaryLabelColor)
            append(header[1] + "\n", color: SyntaxColor.green.nsColor)
        }
        return output
    }

    static func highlightedHeaderText(_ text: String) -> NSAttributedString {
        attributed(text, highlights: headerHighlights(text))
    }

    private static func attributed(_ text: String, highlights: [Highlight]) -> NSAttributedString {
        let output = NSMutableAttributedString(attributedString: plain(text))
        for highlight in highlights {
            output.addAttribute(.foregroundColor, value: highlight.color.nsColor, range: highlight.range)
        }
        return output
    }

    static func headerHighlights(_ text: String) -> [Highlight] {
        var highlights: [Highlight] = []
        let source = text as NSString
        var location = 0
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            let colon = source.range(of: ":", range: line)
            if colon.location != NSNotFound {
                highlights.append(Highlight(range: NSRange(location: line.location, length: colon.location - line.location),
                                            color: .blue))
                var valueStart = NSMaxRange(colon)
                if valueStart < NSMaxRange(line), source.character(at: valueStart) == 32 { valueStart += 1 }
                highlights.append(Highlight(range: NSRange(location: colon.location, length: valueStart - colon.location),
                                            color: .secondary))
                highlights.append(Highlight(range: NSRange(location: valueStart, length: NSMaxRange(line) - valueStart),
                                            color: .green))
            }
            location = NSMaxRange(line)
        }
        return highlights
    }
}

struct InspectorDetail {
    let flow: FlowDetail
    let request: MessagePresentation
    let response: MessagePresentation?

    init(flow: FlowDetail) {
        self.flow = flow
        request = MessagePreview.render(flow.request)
        response = flow.response.map(MessagePreview.render)
    }
}
