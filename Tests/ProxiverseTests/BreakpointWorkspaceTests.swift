import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class BreakpointWorkspaceTests: XCTestCase {
    private func model() -> CaptureModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["PROXIVERSE_DATA_DIR"]
        setenv("PROXIVERSE_DATA_DIR", root.path, 1)
        let model = CaptureModel()
        if let previous { setenv("PROXIVERSE_DATA_DIR", previous, 1) } else { unsetenv("PROXIVERSE_DATA_DIR") }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        model.breakpointLoader = { id in self.edit(id) }
        return model
    }

    private func flow(_ id: String, phase: String = "request", started: Double = 1) -> TrafficFlow {
        TrafficFlow(id: id, method: "POST", url: "https://fixture.test/api", host: "fixture.test", status: nil,
                    state: "paused-" + phase, started: started, duration: 0, size: nil, error: nil, number: 1)
    }

    private func edit(_ id: String = "a", phase: String = "request", body: String? = #"{"id":12345678901234567890}"#) -> PausedEdit {
        PausedEdit(id: id, phase: phase, url: "https://fixture.test/api", method: "POST", status: 200,
                   headers: "Content-Type: application/json\nSet-Cookie: a=1\nSet-Cookie: b=2\nX-Empty: \nX-URL: https://a.test:443", body: body)
    }

    private func loaded(_ model: CaptureModel, _ key: String) async throws {
        for _ in 0..<100 {
            if model.breakpointDrafts[key] != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Draft did not load: \(model.breakpointErrors)")
    }

    func testQueueOpensOnceKeepsSelectionAndDraftsAcrossPollsAndReopening() async throws {
        let model = model()
        let a = flow("a"), b = flow("b", started: 2)
        model.updatePausedTraffic([a])
        XCTAssertTrue(model.showPausedTraffic)
        try await loaded(model, a.breakpointKey)
        model.showPausedTraffic = false // Window opened, then closed.
        model.breakpointDrafts[a.breakpointKey]?.edit.body = "unfinished draft"
        model.updatePausedTraffic([a])
        XCTAssertFalse(model.showPausedTraffic)
        model.updatePausedTraffic([b, a])
        XCTAssertTrue(model.showPausedTraffic)
        XCTAssertEqual(model.paused.map(\.id), ["a", "b"])
        XCTAssertEqual(model.selectedBreakpoint, a.breakpointKey)
        model.selectBreakpoint(b.breakpointKey)
        try await loaded(model, b.breakpointKey)
        model.selectBreakpoint(a.breakpointKey)
        XCTAssertEqual(model.breakpointDrafts[a.breakpointKey]?.edit.body, "unfinished draft")
        model.updatePausedTraffic([a, b])
        XCTAssertEqual(model.breakpointDrafts[a.breakpointKey]?.edit.body, "unfinished draft")
    }

    func testContinueFailureKeepsDraftThenSuccessSelectsNextAndSuppressesOldSnapshot() async throws {
        let model = model()
        let a = flow("a"), b = flow("b", started: 2)
        model.updatePausedTraffic([a, b])
        try await loaded(model, a.breakpointKey)
        model.breakpointDrafts[a.breakpointKey]?.edit.body = "changed"
        model.breakpointResumer = { _ in throw AppFailure("Try again") }
        let failed = await model.continueBreakpoint(a.breakpointKey, cancel: false)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.breakpointDrafts[a.breakpointKey]?.edit.body, "changed")
        XCTAssertEqual(model.breakpointErrors[a.breakpointKey], "Try again")
        XCTAssertNil(model.error)
        var sent: PausedEdit?
        model.breakpointResumer = { sent = $0 }
        let succeeded = await model.continueBreakpoint(a.breakpointKey, cancel: false)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(sent?.body, "changed")
        XCTAssertEqual(model.selectedBreakpoint, b.breakpointKey)
        XCTAssertNil(model.breakpointDrafts[a.breakpointKey])
        model.showPausedTraffic = false
        model.updatePausedTraffic([a, b]) // In-flight snapshot obtained before Continue.
        XCTAssertEqual(model.paused.map(\.id), ["b"])
        XCTAssertFalse(model.showPausedTraffic)
    }

    func testSameFlowResponseIsANewDraftAndStaleLoadCannotRestoreRequest() async throws {
        let model = model()
        let request = flow("a"), response = flow("a", phase: "response")
        var finishRequest: CheckedContinuation<PausedEdit, Error>?
        model.breakpointLoader = { _ in try await withCheckedThrowingContinuation { finishRequest = $0 } }
        model.updatePausedTraffic([request])
        for _ in 0..<100 {
            if finishRequest != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        model.breakpointLoader = { _ in self.edit(phase: "response", body: "response") }
        model.showPausedTraffic = false
        model.updatePausedTraffic([response])
        try await loaded(model, response.breakpointKey)
        XCTAssertTrue(model.showPausedTraffic)
        finishRequest?.resume(returning: edit(body: "old request"))
        await Task.yield()
        XCTAssertNil(model.breakpointDrafts[request.breakpointKey])
        XCTAssertEqual(model.breakpointDrafts[response.breakpointKey]?.edit.body, "response")
        model.updatePausedTraffic([])
        XCTAssertTrue(model.breakpointDrafts.isEmpty)
        XCTAssertNil(model.selectedBreakpoint)
        XCTAssertNotNil(model.breakpointNotice)
    }

    func testCancelBypassesDraftValidationAndDuplicateSubmitIsBlocked() async throws {
        let model = model()
        let a = flow("a")
        model.updatePausedTraffic([a])
        try await loaded(model, a.breakpointKey)
        model.breakpointDrafts[a.breakpointKey]?.edit.url = "invalid"
        var finish: CheckedContinuation<Void, Error>?
        var count = 0
        model.breakpointResumer = { payload in
            XCTAssertTrue(payload.cancel)
            count += 1
            try await withCheckedThrowingContinuation { finish = $0 }
        }
        let invalid = await model.continueBreakpoint(a.breakpointKey, cancel: false)
        XCTAssertFalse(invalid)
        XCTAssertEqual(count, 0)
        let task = Task { await model.continueBreakpoint(a.breakpointKey, cancel: true) }
        for _ in 0..<100 {
            if finish != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let duplicate = await model.continueBreakpoint(a.breakpointKey, cancel: true)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(count, 1)
        finish?.resume()
        let result = await task.value
        XCTAssertTrue(result)
        XCTAssertTrue(model.paused.isEmpty)
    }

    func testHeaderRowsRoundTripDuplicatesEmptyValuesAndColons() {
        var draft = BreakpointDraft(edit())
        XCTAssertEqual(draft.payload.headers, edit().headers)
        XCTAssertEqual(draft.headers.filter { $0.name == "Set-Cookie" }.count, 2)
        draft.headers.append(BreakpointHeader(name: "X-New", value: "a:b"))
        draft.headers.remove(at: 0)
        XCTAssertTrue(draft.payload.headers.hasSuffix("X-New: a:b"))
        XCTAssertNil(draft.validationError)
        draft.headers[0].value = "bad\r\nInjected: x"
        XCTAssertNotNil(draft.validationError)
        draft.headers[0].value = "okay"
        draft.headers[0].name = "Bad Name"
        XCTAssertNotNil(draft.validationError)
    }

    func testFormattingPreservesLexemesAndLeavesTextAndOversizedExpansionUnchanged() {
        let json = #"{"id":123456789012345678901234567890,"n":-0.0012300e+04,"s":"\u0e01"}"#
        let draft = BreakpointDraft(edit(body: json))
        XCTAssertEqual(draft.edit.body, MessagePreview.prettyJSON(json))
        XCTAssertTrue(draft.edit.body?.contains("123456789012345678901234567890") == true)
        XCTAssertTrue(draft.edit.body?.contains("-0.0012300e+04") == true)
        XCTAssertEqual(BreakpointDraft(edit(body: "plain text")).edit.body, "plain text")
        XCTAssertNil(BreakpointDraft(edit(body: nil)).edit.body)
        let compact = "[" + Array(repeating: "0", count: 90_000).joined(separator: ",") + "]"
        XCTAssertLessThan(compact.utf8.count, BreakpointDraft.maximumBodyBytes)
        XCTAssertEqual(BreakpointDraft(edit(body: compact)).edit.body, compact)
        var overLimit = BreakpointDraft(edit(body: String(repeating: "ก", count: 90_000)))
        XCTAssertNotNil(overLimit.validationError)
        overLimit.edit.body = "{invalid JSON"
        XCTAssertNil(overLimit.validationError, "Invalid JSON can still be forwarded as text")
        overLimit.statusText = "199"
        overLimit.edit.phase = "response"
        XCTAssertNotNil(overLimit.validationError)
        overLimit.statusText = "abc"
        XCTAssertNotNil(overLimit.validationError)
        overLimit.statusText = "201"
        XCTAssertNil(overLimit.validationError)
        XCTAssertEqual(overLimit.payload.status, 201)
        overLimit.edit.phase = "request"
        overLimit.edit.method = "GET\n"
        XCTAssertNotNil(overLimit.validationError)
        overLimit.edit.method = "GET"
        overLimit.headers[0].name = "X-Test\n"
        XCTAssertNotNil(overLimit.validationError)
    }

    func testFormatCommandUsesBreakpointBudgetWithoutChangingBodyOnFailure() async throws {
        var text = "[" + Array(repeating: "0", count: 90_000).joined(separator: ",") + "]"
        let original = text
        var error: String?
        let host = NSHostingController(rootView: SyntaxTextEditor(
            text: Binding(get: { text }, set: { text = $0 }), syntax: .json,
            command: .init(kind: .format), onError: { error = $0 },
            maximumFormattedBytes: BreakpointDraft.maximumBodyBytes))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        for _ in 0..<100 {
            if error != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(error)
        XCTAssertEqual(text, original)
    }

    func testBreakpointLayoutAndBodyScrollingInBothAppearances() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let model = model()
            let a = flow("a")
            let body = "[\n" + (0..<200).map(String.init).joined(separator: ",\n") + "\n]"
            model.breakpointLoader = { _ in self.edit(body: body) }
            model.updatePausedTraffic([a])
            try await loaded(model, a.breakpointKey)
            let host = NSHostingController(rootView: BreakpointsView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentViewController = host
            window.appearance = NSAppearance(named: appearance)
            defer { window.contentViewController = nil }
            for size in [NSSize(width: 1100, height: 760), NSSize(width: 960, height: 680)] {
                window.setContentSize(size)
                host.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(350))
                host.view.layoutSubtreeIfNeeded()
                let views = descendants(host.view)
                let editor = try XCTUnwrap(views.compactMap { $0 as? JSONEditorTextView }.first)
                let scroll = try XCTUnwrap(editor.enclosingScrollView)
                XCTAssertGreaterThan(scroll.contentSize.height, 80)
                XCTAssertGreaterThan(editor.frame.height, scroll.contentSize.height)
                let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                                 wheelCount: 1, wheel1: -80, wheel2: 0, wheel3: 0))
                editor.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
                XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
                XCTAssertEqual(editor.string, model.breakpointDrafts[a.breakpointKey]?.edit.body)
                let editorRect = scroll.convert(scroll.bounds, to: host.view)
                XCTAssertTrue(host.view.bounds.contains(editorRect), "Editor must fit inside the window")
                XCTAssertLessThan(editorRect.height, host.view.bounds.height - 160,
                                  "Metadata, headers and footer must retain space outside the body editor")
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
