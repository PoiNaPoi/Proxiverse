import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class SyntaxTextEditorTests: XCTestCase {
    func testHeadersScrollInsideTheResponseEditor() async throws {
        try await checkResponseEditorScrolling(syntax: .headers)
    }

    func testBodyScrollsInsideTheResponseEditor() async throws {
        try await checkResponseEditorScrolling(syntax: .json)
    }

    private func checkResponseEditorScrolling(syntax: SyntaxTextEditor.Syntax) async throws {
        let text = syntax == .headers
            ? (0..<100).map { "X-Header-\($0): value" }.joined(separator: "\n")
            : "[\n" + (0..<100).map { "  \($0)" }.joined(separator: ",\n") + "\n]"
        let host = NSHostingController(rootView: ScrollView {
            VStack {
                Text("Response")
                SyntaxTextEditor(text: .constant(text), syntax: syntax).frame(height: 120)
                Color.clear.frame(height: 600)
            }
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 500, height: 300))
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(textViews(in: host.view).first)
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        let outerScroll = try XCTUnwrap(scroll.enclosingScrollView)
        XCTAssertGreaterThan(scroll.contentSize.height, 0)
        XCTAssertGreaterThan(editor.frame.height, scroll.contentSize.height,
                             "Long response content must extend beyond the editor viewport")
        let outerOrigin = outerScroll.contentView.bounds.origin
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                         wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0))
        let wheel = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertLessThan(wheel.scrollingDeltaY, 0)
        editor.scrollWheel(with: wheel)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0,
                             "Scrolling over the response must move its own content")
        XCTAssertEqual(outerScroll.contentView.bounds.origin, outerOrigin,
                       "Scrolling inside the editor must not move the surrounding form")
        XCTAssertEqual(editor.string, text)
    }

    func testRawHeadersRetainWhitespaceDuplicatesInvalidLinesAndLineEndings() {
        let text = "Content-Type: application/json\r\nSet-Cookie: a=1\r\n\r\nSet-Cookie: b=2\nunfinished\nX-URL: https://fixture.test/a:b"
        let styled = MessagePreview.highlightedHeaderText(text)
        XCTAssertEqual(SyntaxTextEditor.highlight(text, syntax: .headers), MessagePreview.headerHighlights(text))
        XCTAssertEqual(styled.string, text)
        func color(_ token: String) -> NSColor? {
            styled.attribute(.foregroundColor, at: (text as NSString).range(of: token).location,
                             effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(color("Content-Type"), .systemBlue)
        XCTAssertEqual(color("application/json"), .systemGreen)
        XCTAssertEqual(color("b=2"), .systemGreen)
        XCTAssertEqual(color("https://fixture.test/a:b"), .systemGreen)
        XCTAssertEqual(color("unfinished"), .labelColor)
    }

    func testJSONEditorUsesInspectorColorsWithoutReformattingOrRounding() {
        let text = "  " + #"{"id":123456789012345678901234567890,"s":"\u0e01","n":-0.0012300e+04,"b":true,"a":null}"# + "\n"
        let expected = MessagePreview.jsonHighlights(text)
        let actual = SyntaxTextEditor.highlight(text, syntax: .json)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(SyntaxTextEditor.highlightingPrefix(text), text)
        XCTAssertEqual(SyntaxTextEditor.highlightingPrefix(#"{"unfinished": "#), #"{"unfinished": "#)
    }

    func testHighlightBudgetDoesNotSplitSurrogatePairsOrCombiningSequences() {
        let limit = SyntaxTextEditor.maximumHighlightedCharacters
        for suffix in ["👋", "e\u{301}"] {
            let text = String(repeating: " ", count: limit - 1) + suffix + String(repeating: "x", count: limit)
            let prefix = SyntaxTextEditor.highlightingPrefix(text)
            XCTAssertLessThanOrEqual(prefix.utf16.count, limit)
            XCTAssertEqual(prefix, String(repeating: " ", count: limit - 1))
        }
    }

    func testLongOrUnfinishedJSONStringsStayStringColoredAtTheHighlightBoundary() throws {
        let prefix = "{\"message\":\""
        let text = prefix + String(repeating: "x", count: SyntaxTextEditor.maximumHighlightedCharacters)
        let highlights = SyntaxTextEditor.highlight(text, syntax: .json)
        let value = try XCTUnwrap(highlights.last)
        XCTAssertEqual(value.color, .green)
        XCTAssertEqual(value.range.location, prefix.utf16.count - 1)
        XCTAssertEqual(NSMaxRange(value.range), SyntaxTextEditor.maximumHighlightedCharacters)
    }

    func testNativeEditingHighlightsWithoutChangingSelectionUndoOrBoundText() async throws {
        var text = #"{"key":"original","id":12345678901234567890}"#
        let binding = Binding(get: { text }, set: { text = $0 })
        let host = NSHostingController(rootView: SyntaxTextEditor(text: binding, syntax: .json))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 500, height: 300))
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(textViews(in: host.view).first)
        XCTAssertGreaterThan(editor.bounds.width, 100)
        window.makeFirstResponder(editor)
        let original = text
        let range = (text as NSString).range(of: "original")
        editor.insertText("edited", replacementRange: range)
        editor.breakUndoCoalescing()
        let selection = editor.selectedRange()
        XCTAssertTrue(text.contains("edited"))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(editor.string, text)
        XCTAssertEqual(editor.selectedRange(), selection)
        let key = (text as NSString).range(of: "\"key\"").location
        XCTAssertEqual(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: key,
                                                                effectiveRange: nil) as? NSColor, .systemPurple)
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(editor.string, original)
        XCTAssertEqual(text, original)
        undo.redo()
        XCTAssertTrue(editor.string.contains("edited"))
        XCTAssertEqual(editor.string, text)
        editor.setMarkedText("composing", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: (text as NSString).range(of: "edited"))
        XCTAssertTrue(editor.hasMarkedText())
        let composing = editor.string
        let composingSelection = editor.selectedRange()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, composing)
        XCTAssertEqual(editor.selectedRange(), composingSelection)
        editor.insertText("committed", replacementRange: editor.markedRange())
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertTrue(editor.string.contains("committed"))
        XCTAssertEqual(editor.string, text)
    }

    func testNativeJSONFoldingChangesLayoutWithoutChangingTheEditableBody() async throws {
        var text = try XCTUnwrap(MessagePreview.prettyJSON(#"{"items":[{"id":12345678901234567890},{"id":2}],"ok":true}"#))
        let original = text
        let host = NSHostingController(rootView: SyntaxTextEditor(
            text: Binding(get: { text }, set: { text = $0 }), syntax: .json))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 500, height: 300))
        defer { window.contentViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(textViews(in: host.view).first)
        let layout = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        layout.ensureLayout(for: container)
        let fullHeight = layout.usedRect(for: container).height
        func buttons(_ view: NSView) -> [NSButton] {
            view.subviews.flatMap { child in (child as? NSButton).map { [$0] } ?? buttons(child) }
        }
        let collapse = try XCTUnwrap(buttons(host.view).first { $0.toolTip == "Collapse JSON at line 1" })
        collapse.performClick(nil)
        layout.ensureLayout(for: container)
        let folding = try XCTUnwrap(layout as? JSONEditorLayoutManager)
        XCTAssertTrue(layout.delegate === folding)
        XCTAssertFalse(folding.hiddenRanges.isEmpty)
        let hiddenGlyph = layout.glyphIndexForCharacter(at: (original as NSString).range(of: "\"items\"").location)
        XCTAssertTrue(layout.propertyForGlyph(at: hiddenGlyph).contains(.null))
        XCTAssertLessThan(layout.usedRect(for: container).height, fullHeight / 2)
        XCTAssertEqual(editor.string, original)
        XCTAssertEqual(text, original)
        host.view.layoutSubtreeIfNeeded()
        let expand = try XCTUnwrap(buttons(host.view).first { $0.toolTip == "Expand JSON at line 1" })
        expand.performClick(nil)
        layout.ensureLayout(for: container)
        XCTAssertEqual(layout.usedRect(for: container).height, fullHeight, accuracy: 1)
        XCTAssertEqual(editor.string, original)
        let gutter = try XCTUnwrap((editor as? JSONEditorTextView)?.editorContainer?.gutter)
        XCTAssertEqual(gutter.lineStarts.count, original.components(separatedBy: "\n").count)
        XCTAssertGreaterThanOrEqual(gutter.frame.width, 64)
        let child = try XCTUnwrap((editor as? JSONEditorTextView)?.regions.dropFirst().first)
        let jsonEditor = try XCTUnwrap(editor as? JSONEditorTextView)
        jsonEditor.toggleFold(child.opening)
        jsonEditor.toggleFold(0)
        jsonEditor.toggleFold(0)
        XCTAssertEqual(jsonEditor.collapsed, [child.opening], "Child fold survives collapsing its parent")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        editor.setSelectedRange(NSRange(location: 0, length: original.utf16.count))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: original.utf16.count))
        XCTAssertTrue(editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string), original)
        window.makeFirstResponder(editor)
        editor.insertText("false", replacementRange: (original as NSString).range(of: "true"))
        XCTAssertTrue(jsonEditor.collapsed.isEmpty, "Editing unfolds the document without replacing hidden content")
        XCTAssertEqual(text, original.replacingOccurrences(of: "true", with: "false"))
        editor.undoManager?.undo()
        XCTAssertEqual(text, original)
    }

    func testFormatCommandIsUndoableAndReportsInvalidJSONWithoutChangingIt() async throws {
        var text = #"{"id":123456789012345678901234567890,"value":1.2300e+04}"#
        let original = text
        let binding = Binding(get: { text }, set: { text = $0 })
        let host = NSHostingController(rootView: SyntaxTextEditor(text: binding, syntax: .json))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 500, height: 300))
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(textViews(in: host.view).first)
        window.makeFirstResponder(editor)
        var error: String? = "pending"
        host.rootView = SyntaxTextEditor(text: binding, syntax: .json, command: .init(kind: .format),
                                         onError: { error = $0 })
        for _ in 0..<50 {
            if error == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(error)
        XCTAssertEqual(text, MessagePreview.prettyJSON(original))
        XCTAssertTrue(editor === textViews(in: host.view).first)
        let undo = try XCTUnwrap(editor.undoManager)
        undo.undo()
        XCTAssertEqual(text, original)
        let invalid = #"{"unfinished": ]"#
        editor.insertText(invalid, replacementRange: NSRange(location: 0, length: text.utf16.count))
        host.rootView = SyntaxTextEditor(text: binding, syntax: .json, command: .init(kind: .format),
                                         onError: { error = $0 })
        for _ in 0..<50 {
            if error != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(error?.contains("Invalid JSON") == true)
        XCTAssertEqual(text, invalid)
        XCTAssertEqual(editor.string, invalid)
    }

    func testJSONNewlineTabAndBacktabUseTwoSpaceIndentation() async throws {
        var text = "{}"
        let host = NSHostingController(rootView: SyntaxTextEditor(
            text: Binding(get: { text }, set: { text = $0 }), syntax: .json))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 500, height: 300))
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(textViews(in: host.view).first)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.insertNewline(nil)
        XCTAssertEqual(text, "{\n  \n}")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
        editor.insertTab(nil)
        XCTAssertEqual(text, "{\n    \n}")
        editor.insertBacktab(nil)
        XCTAssertEqual(text, "{\n  \n}")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        editor.insertTab(nil)
        XCTAssertEqual(text, "  {\n    \n  }")
        editor.insertBacktab(nil)
        XCTAssertEqual(text, "{\n  \n}")
        XCTAssertEqual(SyntaxTextEditor.lineStarts(in: "😀\r\nnext\rend\n"), [0, 4, 9, 13])
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        view.subviews.flatMap { child in
            (child as? NSTextView).map { [$0] } ?? textViews(in: child)
        }
    }
}
