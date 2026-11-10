import AppKit
import CoreText

final class JSONEditorLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private(set) var hiddenRanges: [NSRange] = []

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHiddenRanges(_ ranges: [NSRange]) {
        guard hiddenRanges != ranges else { return }
        hiddenRanges = ranges
        let range = NSRange(location: 0, length: textStorage?.length ?? 0)
        invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    // Fold glyphs, not text storage: editing, copying and saving retain the full JSON.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard !hiddenRanges.isEmpty else { return 0 }
        var properties = Array(UnsafeBufferPointer(start: props, count: range.length))
        var rendered = Array(UnsafeBufferPointer(start: glyphs, count: range.length))
        var character: UniChar = 0x2026
        var ellipsis: CGGlyph = 0
        let hasEllipsis = CTFontGetGlyphsForCharacters(font as CTFont, &character, &ellipsis, 1)
        for index in 0..<range.length {
            if let hidden = hiddenRanges.first(where: { NSLocationInRange(characterIndexes[index], $0) }) {
                if characterIndexes[index] == hidden.location, hasEllipsis {
                    rendered[index] = ellipsis
                    properties[index] = []
                } else { properties[index] = .null }
            }
        }
        return rendered.withUnsafeBufferPointer { glyphBuffer in
            properties.withUnsafeBufferPointer { propertyBuffer in
                guard let glyphs = glyphBuffer.baseAddress, let properties = propertyBuffer.baseAddress else { return 0 }
                layoutManager.setGlyphs(glyphs, properties: properties, characterIndexes: characterIndexes,
                                       font: font, forGlyphRange: range)
                return range.length
            }
        }
    }
}

final class JSONEditorTextView: NSTextView {
    var jsonEditingEnabled = false
    weak var editorContainer: JSONPreviewContainer?
    private(set) var regions: [JSONFoldRegion] = []
    private(set) var collapsed: Set<Int> = []
    private var lineStarts = [0]

    func updateStructure(regions: [JSONFoldRegion], lineStarts: [Int]) {
        self.regions = regions
        self.lineStarts = lineStarts
        collapsed.formIntersection(regions.map(\.opening))
        refreshFolds()
    }

    func toggleFold(_ id: Int) {
        guard regions.contains(where: { $0.opening == id }), !hasMarkedText() else { return }
        if !collapsed.insert(id).inserted { collapsed.remove(id) }
        refreshFolds()
    }

    func collapseAll() {
        guard !hasMarkedText() else { return }
        collapsed = Set(regions.map(\.opening))
        refreshFolds()
    }

    func expandAll() {
        collapsed.removeAll()
        refreshFolds()
    }

    func prepareForEditing() {
        if !collapsed.isEmpty { expandAll() }
        regions = []
        editorContainer?.setFoldControls([], lineStarts: jsonEditingEnabled ? lineStarts : [])
    }

    private func refreshFolds() {
        var hidden: [NSRange] = []
        var controls: [JSONFoldControl] = []
        var hiddenEnd = 0
        for region in regions {
            guard region.opening >= hiddenEnd else { continue }
            let folded = collapsed.contains(region.opening)
            controls.append(JSONFoldControl(id: region.opening, location: region.opening,
                                            line: region.line, collapsed: folded))
            if folded {
                hidden.append(NSRange(location: region.opening + 1, length: region.closing - region.opening - 1))
                hiddenEnd = region.closing
            }
        }
        if let fold = hidden.first(where: { NSLocationInRange(selectedRange().location, $0) }) {
            setSelectedRange(NSRange(location: fold.location - 1, length: 0))
        }
        let manager = layoutManager as? JSONEditorLayoutManager
        let changed = manager?.hiddenRanges != hidden
        manager?.setHiddenRanges(hidden)
        editorContainer?.setFoldControls(controls, lineStarts: jsonEditingEnabled ? lineStarts : [])
        if changed {
            sizeToFit()
            needsDisplay = true
        }
    }

    func formatJSON(maximumBytes: Int = RuleStore.maximumMockBytes) throws {
        guard !hasMarkedText() else { throw AppFailure("Finish composing text before formatting JSON.") }
        guard let formatted = MessagePreview.prettyJSON(string, maximumBytes: maximumBytes) else {
            do { _ = try JSONSerialization.jsonObject(with: Data(string.utf8), options: [.fragmentsAllowed]) }
            catch { throw AppFailure("Invalid JSON: \(error.localizedDescription). Body was not changed.") }
            throw AppFailure("Formatted JSON exceeds the \(maximumBytes.formatted()) byte body limit. Body was not changed.")
        }
        guard formatted != string else { return }
        breakUndoCoalescing()
        insertText(formatted, replacementRange: NSRange(location: 0, length: string.utf16.count))
        breakUndoCoalescing()
        undoManager?.setActionName("Format JSON")
    }

    override func insertNewline(_ sender: Any?) {
        guard jsonEditingEnabled, !hasMarkedText() else { super.insertNewline(sender); return }
        let source = string as NSString
        let selection = selectedRange()
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let indent = String(prefix.prefix { $0 == " " || $0 == "\t" })
        let opening = prefix.trimmingCharacters(in: .whitespaces).last
        let nested = !insideString(before: selection.location) && (opening == "{" || opening == "[")
        let indentation = indent + (nested ? "  " : "")
        var insertion = "\n" + indentation
        let end = NSMaxRange(selection)
        if nested, end < source.length,
           source.character(at: end) == (opening == "{" ? 125 : 93) {
            insertion += "\n" + indent
        }
        insertText(insertion, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + 1 + indentation.utf16.count, length: 0))
    }

    override func insertTab(_ sender: Any?) {
        guard jsonEditingEnabled, !hasMarkedText() else { super.insertTab(sender); return }
        if selectedRange().length == 0 { insertText("  ", replacementRange: selectedRange()) }
        else { indentSelection(outdent: false) }
    }

    override func insertBacktab(_ sender: Any?) {
        guard jsonEditingEnabled, !hasMarkedText() else { super.insertBacktab(sender); return }
        indentSelection(outdent: true)
    }

    private func indentSelection(outdent: Bool) {
        let source = string as NSString
        let selection = selectedRange()
        let range = source.lineRange(for: selection)
        let original = source.substring(with: range)
        let lines = original.components(separatedBy: "\n")
        let replacement = lines.enumerated().map { index, line in
            if line.isEmpty, index == lines.count - 1 { return line }
            if !outdent { return "  " + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.dropFirst(line.prefix(2).prefix { $0 == " " }.count))
        }.joined(separator: "\n")
        guard replacement != original else { return }
        insertText(replacement, replacementRange: range)
        if selection.length == 0 {
            let location = max(range.location, selection.location + replacement.utf16.count - range.length)
            setSelectedRange(NSRange(location: location, length: 0))
        } else { setSelectedRange(NSRange(location: range.location, length: replacement.utf16.count)) }
    }

    private func insideString(before offset: Int) -> Bool {
        var quoted = false
        var escaped = false
        for unit in string.utf16.prefix(offset) {
            if escaped { escaped = false }
            else if quoted, unit == 92 { escaped = true }
            else if unit == 34 { quoted.toggle() }
        }
        return quoted
    }
}
