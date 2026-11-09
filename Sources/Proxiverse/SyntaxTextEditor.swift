import AppKit
import SwiftUI

struct SyntaxTextEditor: NSViewRepresentable {
    enum Syntax: Sendable { case json, headers }
    nonisolated static let maximumHighlightedCharacters = 256 * 1024

    @Binding var text: String
    let syntax: Syntax
    var accessibilityName = "Text editor"
    var command: Command?
    var onError: ((String?) -> Void)?
    var maximumFormattedBytes = RuleStore.maximumMockBytes

    struct Command: Equatable {
        enum Kind { case format, collapseAll, expandAll }
        let id = UUID()
        let kind: Kind
    }

    private struct Analysis: Sendable {
        let highlights: [MessagePreview.Highlight]
        let regions: [JSONFoldRegion]
        let lineStarts: [Int]
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> JSONPreviewContainer {
        let storage = NSTextStorage()
        let manager = JSONEditorLayoutManager()
        storage.addLayoutManager(manager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(textContainer)
        let view = JSONEditorTextView(frame: .zero, textContainer: textContainer)
        let container = JSONPreviewContainer(textView: view)
        view.editorContainer = container
        let scroll = container.scrollView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .labelColor
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.maxSize.height = .greatestFiniteMagnitude
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.setAccessibilityLabel(accessibilityName)
        scroll.documentView = view
        container.gutter.onToggle = { [weak view] id in view?.toggleFold(id) }
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak gutter = container.gutter] _ in
            gutter?.needsLayout = true
            gutter?.needsDisplay = true
        }
        context.coordinator.sync(view)
        return container
    }

    func updateNSView(_ container: JSONPreviewContainer, context: Context) {
        context.coordinator.parent = self
        guard let view = container.textView as? JSONEditorTextView else { return }
        view.setAccessibilityLabel(accessibilityName)
        context.coordinator.sync(view)
    }

    nonisolated static func highlightingPrefix(_ text: String) -> String {
        let source = text as NSString
        var length = min(source.length, maximumHighlightedCharacters)
        if length > 0, length < source.length {
            let boundary = source.rangeOfComposedCharacterSequence(at: length - 1)
            if NSMaxRange(boundary) > length { length = boundary.location }
        }
        return source.substring(to: length)
    }

    nonisolated static func highlight(_ text: String, syntax: Syntax) -> [MessagePreview.Highlight] {
        let prefix = highlightingPrefix(text)
        switch syntax {
        case .json: return MessagePreview.jsonHighlights(prefix)
        case .headers: return MessagePreview.headerHighlights(prefix)
        }
    }

    nonisolated static func lineStarts(in text: String) -> [Int] {
        var starts = [0]
        var previous: UInt16 = 0
        for (offset, unit) in text.utf16.enumerated() {
            if unit == 10, previous == 13 { starts[starts.count - 1] = offset + 1 }
            else if unit == 10 || unit == 13 || unit == 0x2028 || unit == 0x2029 { starts.append(offset + 1) }
            previous = unit
        }
        return starts
    }

    nonisolated private static func analyze(_ text: String, syntax: Syntax) -> Analysis {
        Analysis(highlights: highlight(text, syntax: syntax),
                 regions: syntax == .json ? JSONFolding.regions(in: text) : [],
                 lineStarts: syntax == .json ? lineStarts(in: text) : [])
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxTextEditor
        private var highlightTask: Task<Void, Never>?
        private var lastSyntax: Syntax?
        private var lastCommandID: UUID?
        var observer: NSObjectProtocol?

        init(parent: SyntaxTextEditor) { self.parent = parent }
        deinit {
            highlightTask?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func sync(_ view: JSONEditorTextView) {
            view.jsonEditingEnabled = parent.syntax == .json
            let changed = view.string != parent.text
            if changed, !view.hasMarkedText() {
                view.prepareForEditing()
                view.string = parent.text
                view.undoManager?.removeAllActions()
            }
            if changed || lastSyntax != parent.syntax {
                lastSyntax = parent.syntax
                scheduleHighlight(view)
            }
            if let command = parent.command, lastCommandID != command.id {
                lastCommandID = command.id
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view else { return }
                    do {
                        switch command.kind {
                        case .format: try view.formatJSON(maximumBytes: self.parent.maximumFormattedBytes)
                        case .collapseAll: view.collapseAll()
                        case .expandAll: view.expandAll()
                        }
                        self.parent.onError?(nil)
                    } catch { self.parent.onError?(error.localizedDescription) }
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? JSONEditorTextView else { return }
            parent.text = view.string
            scheduleHighlight(view)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            (textView as? JSONEditorTextView)?.prepareForEditing()
            return true
        }

        private func scheduleHighlight(_ view: JSONEditorTextView) {
            highlightTask?.cancel()
            let syntax = parent.syntax
            highlightTask = Task { @MainActor [weak view] in
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                guard !Task.isCancelled, let view, !view.hasMarkedText() else { return }
                let snapshot = view.string
                let analysis = await Task.detached(priority: .userInitiated) {
                    SyntaxTextEditor.analyze(snapshot, syntax: syntax)
                }.value
                guard !Task.isCancelled, view.string == snapshot, !view.hasMarkedText(),
                      let layout = view.layoutManager else { return }
                let range = NSRange(location: 0, length: (snapshot as NSString).length)
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
                for highlight in analysis.highlights {
                    layout.addTemporaryAttribute(.foregroundColor, value: highlight.color.nsColor,
                                                 forCharacterRange: highlight.range)
                }
                view.updateStructure(regions: analysis.regions, lineStarts: analysis.lineStarts)
                view.editorContainer?.layoutSubtreeIfNeeded()
            }
        }
    }
}
