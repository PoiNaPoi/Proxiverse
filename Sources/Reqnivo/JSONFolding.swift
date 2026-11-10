import AppKit

struct JSONFoldRegion: Equatable, Sendable {
    let opening: Int
    let closing: Int
    let line: Int
}

struct JSONFoldControl {
    let id: Int
    let location: Int
    let line: Int
    let collapsed: Bool
}

struct JSONFoldDisplay {
    let content: NSAttributedString
    let controls: [JSONFoldControl]
}

enum JSONFolding {
    // Offsets use UTF-16, matching NSTextView and NSAttributedString. Brackets
    // inside strings (including escaped quotes/backslashes) are not containers.
    static func regions(in text: String) -> [JSONFoldRegion] {
        var stack: [(opening: Int, line: Int, bracket: UInt16)] = []
        var result: [JSONFoldRegion] = []
        var inString = false
        var escaped = false
        var line = 0
        var previous: UInt16 = 0
        for (offset, unit) in text.utf16.enumerated() {
            if unit == 13 || (unit == 10 && previous != 13) || unit == 0x2028 || unit == 0x2029 { line += 1 }
            previous = unit
            if inString {
                if escaped { escaped = false }
                else if unit == 92 { escaped = true }
                else if unit == 34 { inString = false }
                continue
            }
            switch unit {
            case 34: inString = true
            case 123, 91: stack.append((offset, line, unit))
            case 125, 93:
                guard let start = stack.last else { continue }
                guard start.bracket == (unit == 125 ? 123 : 91) else { stack.removeAll(); continue }
                stack.removeLast()
                if start.line < line {
                    result.append(JSONFoldRegion(opening: start.opening, closing: offset, line: start.line))
                }
            default: break
            }
        }
        return result.sorted { $0.opening < $1.opening }
    }

    static func display(_ content: NSAttributedString, regions: [JSONFoldRegion], collapsed: Set<Int>) -> JSONFoldDisplay {
        if collapsed.isEmpty {
            return JSONFoldDisplay(content: content, controls: regions.map {
                JSONFoldControl(id: $0.opening, location: $0.opening, line: $0.line, collapsed: false)
            })
        }
        let output = NSMutableAttributedString(string: "")
        var controls: [JSONFoldControl] = []
        var cursor = 0
        var removed = 0
        for region in regions {
            if region.opening < cursor { continue } // Hidden by a collapsed ancestor.
            let isCollapsed = collapsed.contains(region.opening)
            controls.append(JSONFoldControl(id: region.opening, location: region.opening - removed,
                                            line: region.line, collapsed: isCollapsed))
            if isCollapsed {
                output.append(content.attributedSubstring(from: NSRange(location: cursor, length: region.opening + 1 - cursor)))
                var attributes = content.attributes(at: region.opening, effectiveRange: nil)
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
                output.append(NSAttributedString(string: " … ", attributes: attributes))
                output.append(content.attributedSubstring(from: NSRange(location: region.closing, length: 1)))
                cursor = region.closing + 1
                removed += region.closing - region.opening - 1 - 3
            }
        }
        output.append(content.attributedSubstring(from: NSRange(location: cursor, length: content.length - cursor)))
        return JSONFoldDisplay(content: output, controls: controls)
    }
}
