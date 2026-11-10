import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class InspectorLayoutTests: XCTestCase {
    func testInspectorCollapseReturnsSpaceToTrafficAndCanReopenInBothOrientations() async {
        for vertical in [false, true] {
            let controller = WorkspaceSplitController(first: Color.clear, second: Color.clear)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 1000, height: 700))
            controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
            let name = "Proxiverse.Tests.Collapse.\(UUID().uuidString)"
            controller.configure(vertical: vertical, autosaveName: name,
                                 firstMinimum: 180, secondMinimum: 260, secondCollapsed: true)
            for _ in 0..<5 {
                controller.view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(controller.splitViewItems[1].isCollapsed)
            let collapsedTrafficSize = vertical ? controller.firstHost.view.frame.width : controller.firstHost.view.frame.height

            controller.configure(vertical: vertical, autosaveName: name,
                                 firstMinimum: 180, secondMinimum: 260, secondCollapsed: false)
            for _ in 0..<5 {
                controller.view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(controller.splitViewItems[1].isCollapsed)
            let expandedTrafficSize = vertical ? controller.firstHost.view.frame.width : controller.firstHost.view.frame.height
            XCTAssertGreaterThan(collapsedTrafficSize, expandedTrafficSize)
            window.contentViewController = nil
        }
    }

    func testEmptyInspectorDoesNotShowMessagePanesBehindThePlaceholder() async {
        for stacked in [false, true] {
            for loading in [false, true] {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let host = NSHostingController(rootView: InspectorView(
                        detail: nil, loading: loading, messagesStacked: stacked))
                    let window = makeWindow(host: host, appearance: appearance)
                    await layout(host)
                    XCTAssertFalse(descendants(of: host.view).contains { $0 is NSSplitView },
                                   "An unselected inspector must show only the empty state, not the message split")
                    XCTAssertFalse(descendants(of: host.view).contains { $0 is NSSegmentedControl },
                                   "Headers/Body controls must not show before selecting a request")
                    XCTAssertGreaterThanOrEqual(host.view.frame.height, 350)
                    window.contentViewController = nil
                }
            }
        }
    }

    func testSelectingAndClearingRequestShowsAndRemovesMessagePanes() async {
        let summary = TrafficFlow(id: "layout", method: "GET", url: "https://example.test/",
                                  host: "example.test", status: 200, state: "complete",
                                  started: 1, duration: 0.1, size: 2, error: nil)
        let message = FlowMessage(headers: [], body: "{}", truncated: false,
                                  streamed: false, httpVersion: "HTTP/2.0")
        let detail = InspectorDetail(flow: FlowDetail(summary: summary, request: message, response: message))
        let host = NSHostingController(rootView: InspectorView(detail: nil, loading: false))
        let window = makeWindow(host: host, appearance: .aqua)
        defer { window.contentViewController = nil }
        for stacked in [false, true] {
            host.rootView = InspectorView(detail: detail, loading: false, messagesStacked: stacked)
            await layout(host)
            let split = descendants(of: host.view).compactMap { $0 as? NSSplitView }.first
            XCTAssertNotNil(split)
            XCTAssertEqual(split?.isVertical, !stacked)
            XCTAssertEqual(descendants(of: host.view).filter { $0 is NSSegmentedControl }.count, 2)

            host.rootView = InspectorView(detail: nil, loading: false, messagesStacked: stacked)
            await layout(host)
            XCTAssertFalse(descendants(of: host.view).contains { $0 is NSSplitView })
            XCTAssertFalse(descendants(of: host.view).contains { $0 is NSSegmentedControl })
        }
    }

    func testLongResponseLinesScrollHorizontallyWithoutWrapping() async throws {
        let summary = TrafficFlow(id: "long-response", method: "GET", url: "https://example.test/",
                                  host: "example.test", status: 200, state: "complete",
                                  started: 1, duration: 0.1, size: 2000, error: nil)
        let body = "{\"message\":\"" + String(repeating: "ข้อความยาว ", count: 80)
            + "\",\"url\":\"https://example.test/" + String(repeating: "path/", count: 80) + "\"}"
        let message = FlowMessage(headers: [], body: body, truncated: false,
                                  streamed: false, httpVersion: "HTTP/2.0")
        let detail = InspectorDetail(flow: FlowDetail(summary: summary, request: message, response: message))
        let host = NSHostingController(rootView: InspectorView(detail: detail, loading: false))
        let window = makeWindow(host: host, appearance: .aqua)
        defer { window.contentViewController = nil }
        for stacked in [false, true] {
            host.rootView = InspectorView(detail: detail, loading: false, messagesStacked: stacked)
            await layout(host)
            let response = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? NSTextView }
                .first { $0.accessibilityLabel() == "Response body" })
            let manager = try XCTUnwrap(response.layoutManager)
            let textContainer = try XCTUnwrap(response.textContainer)
            manager.ensureLayout(for: textContainer)
            let text = response.string as NSString
            for token in ["ข้อความยาว", "https://example.test/"] {
                let line = text.lineRange(for: text.range(of: token))
                let first = manager.glyphIndexForCharacter(at: line.location)
                let last = manager.glyphIndexForCharacter(at: NSMaxRange(line) - 2)
                XCTAssertEqual(manager.lineFragmentRect(forGlyphAt: first, effectiveRange: nil).minY,
                               manager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil).minY)
            }
            let scroll = try XCTUnwrap(response.enclosingScrollView)
            XCTAssertGreaterThan(response.frame.width, scroll.contentSize.width)
            scroll.contentView.scroll(to: NSPoint(x: 200, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
            XCTAssertEqual(response.string, detail.response?.copyText)
        }
    }

    private func makeWindow(host: NSHostingController<InspectorView>, appearance: NSAppearance.Name) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 360),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 900, height: 360))
        return window
    }

    private func layout(_ host: NSHostingController<InspectorView>) async {
        for _ in 0..<5 {
            host.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
