import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class RulesLayoutTests: XCTestCase {
    func testBreakpointPrefillIsConsumedOnceAndAutosavesWithoutChangingMapLocal() async throws {
        let model = isolatedModel()
        var map = DebugRule()
        map.bodySource = .text
        let saved = await model.saveRules([map], inlineBodies: [map.id: "{}"])
        XCTAssertTrue(saved)
        map = try XCTUnwrap(model.rules.first)
        let flow = TrafficFlow(id: "clicked", method: "PATCH", url: "https://api.test/items/7?page=2", host: "api.test",
                               status: 200, state: "complete", started: 1, duration: 0, size: 0, error: nil)
        model.openBreakpointRules(flow)
        let pendingID = try XCTUnwrap(model.pendingBreakpoint?.id)
        XCTAssertTrue(model.showBreakpoints)
        let host = NSHostingController(rootView: RulesView(model: model, kind: .breakpoint))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        for _ in 0..<150 {
            if model.rules.contains(where: { $0.id == pendingID }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.pendingBreakpoint)
        let rule = try XCTUnwrap(model.rules.first { $0.id == pendingID })
        XCTAssertEqual(rule.kind, "breakpoint")
        XCTAssertEqual(rule.host, "api.test")
        XCTAssertEqual(rule.path, "/items/7?page=2")
        XCTAssertEqual(rule.method, "PATCH")
        XCTAssertTrue(rule.enabled)
        XCTAssertTrue(rule.request)
        XCTAssertFalse(rule.response)
        XCTAssertEqual(model.rules.filter { $0.kind == "mapLocal" }, [map])
        XCTAssertEqual(try model.ruleStore.load().filter { $0.id == pendingID }.count, 1)
        // Deliver another right-click while the window is already open.
        model.openBreakpointRules(flow)
        let nextID = try XCTUnwrap(model.pendingBreakpoint?.id)
        for _ in 0..<150 {
            if model.rules.contains(where: { $0.id == nextID }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.pendingBreakpoint)
        XCTAssertEqual(model.rules.filter { $0.id == pendingID }.count, 1)
        XCTAssertEqual(model.rules.filter { $0.id == nextID }.count, 1)
    }

    func testTypingInlineBodyAndSwitchingRulesKeepsTheDraft() async throws {
        let model = isolatedModel()
        model.rules = [DebugRule()]
        let pending = DebugRule()
        let capturedBody = #"{"response":"prefilled","id":12345678901234567890}"#
        let formattedBody = try XCTUnwrap(MessagePreview.prettyJSON(capturedBody))
        model.pendingMapLocal = MapLocalPrefill(rule: pending, body: capturedBody)
        let host = NSHostingController(rootView: RulesView(model: model, kind: .mapLocal))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1040, height: 700))
        defer { window.contentViewController = nil }
        for _ in 0..<50 {
            host.view.layoutSubtreeIfNeeded()
            if descendants(of: host.view).contains(where: { $0 is NSTextView }) { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let table = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? NSTableView }.first)
        let editor = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(editor.string, formattedBody)
        XCTAssertNil(model.pendingMapLocal, "The pending response must be consumed only once")
        try await Task.sleep(for: .milliseconds(300))
        let valueOffset = (formattedBody as NSString).range(of: "\"prefilled\"").location
        XCTAssertEqual(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: valueOffset,
                                                                effectiveRange: nil) as? NSColor, .systemGreen)
        let body = #"{"draft":"keep me"}"#
        editor.insertText(body, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try await Task.sleep(for: .milliseconds(30))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(30))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        for _ in 0..<50 {
            host.view.layoutSubtreeIfNeeded()
            if descendants(of: host.view).compactMap({ $0 as? NSTextView }).first?.string == body { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(descendants(of: host.view).compactMap { $0 as? NSTextView }.first?.string, body)
    }

    func testMapLocalSupportsSelectingMultipleRulesThenReturningToSingleSelection() async throws {
        let model = isolatedModel()
        model.rules = (0..<3).map { index in
            var rule = DebugRule()
            rule.name = "Rule \(index)"
            rule.bodySource = .text
            return rule
        }
        let host = NSHostingController(rootView: RulesView(model: model, kind: .mapLocal))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        defer { window.contentViewController = nil }
        for _ in 0..<50 {
            host.view.layoutSubtreeIfNeeded()
            if descendants(of: host.view).compactMap({ $0 as? NSTableView }).first?.numberOfRows == 3 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let table = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? NSTableView }.first)
        XCTAssertTrue(table.allowsMultipleSelection)
        table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.selectedRowIndexes, IndexSet([0, 2]))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))
        XCTAssertEqual(model.rules.count, 3)
    }

    func testEmptyRuleListFillsTheEditorRatherThanCollapsingAtTheBottom() async {
        for kind in DebugRuleKind.allCases {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                await checkLayout(kind: kind, rules: [], appearance: appearance)
            }
        }
    }

    func testPopulatedEditorsHaveRoomForTheRuleListAndFields() async {
        for kind in DebugRuleKind.allCases {
            var rule = DebugRule()
            rule.kind = kind.rawValue
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                await checkLayout(kind: kind, rules: [rule], appearance: appearance)
            }
        }
    }

    private func checkLayout(kind: DebugRuleKind, rules: [DebugRule], appearance: NSAppearance.Name) async {
        let model = isolatedModel()
        model.rules = rules
        let host = NSHostingController(rootView: RulesView(model: model, kind: kind))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(NSSize(width: 1040, height: 700))
        defer { window.contentViewController = nil }
        for _ in 0..<20 {
            host.view.layoutSubtreeIfNeeded()
            let tables = descendants(of: host.view).compactMap { $0 as? NSTableView }
            if let list = tables.first, list.numberOfRows >= rules.count { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        host.view.layoutSubtreeIfNeeded()
        let lists = descendants(of: host.view).compactMap { $0 as? NSScrollView }
        XCTAssertFalse(lists.isEmpty, "The rules list must be present even before adding a rule")
        XCTAssertGreaterThanOrEqual(lists.first?.frame.height ?? 0, 300,
                      "\(kind.title) list must fill the sheet; scroll heights: \(lists.map { $0.frame.height })")
        if !rules.isEmpty {
            XCTAssertGreaterThanOrEqual(lists.count, 2, "The selected rule editor must be scrollable")
            let tables = descendants(of: host.view).compactMap { $0 as? NSTableView }
            XCTAssertGreaterThanOrEqual(tables.first?.numberOfRows ?? 0, rules.count)
        }
    }

    private func isolatedModel() -> CaptureModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["PROXIVERSE_DATA_DIR"]
        setenv("PROXIVERSE_DATA_DIR", root.path, 1)
        let model = CaptureModel()
        if let previous { setenv("PROXIVERSE_DATA_DIR", previous, 1) }
        else { unsetenv("PROXIVERSE_DATA_DIR") }
        addTeardownBlock {
            try? await Task.sleep(for: .milliseconds(1200))
            try? FileManager.default.removeItem(at: root)
        }
        return model
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
