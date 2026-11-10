import Combine
import XCTest
@testable import Reqnivo

@MainActor
private final class DetailGate {
    private var requests: [String: CheckedContinuation<FlowDetail, Never>] = [:]
    func load(_ id: String) async -> FlowDetail {
        await withCheckedContinuation { requests[id] = $0 }
    }
    func contains(_ id: String) -> Bool { requests[id] != nil }
    func finish(_ detail: FlowDetail) { requests.removeValue(forKey: detail.summary.id)?.resume(returning: detail) }
}

final class InspectorSelectionTests: XCTestCase {
    private func detail(_ id: String) -> FlowDetail {
        let summary = TrafficFlow(id: id, method: "GET", url: "https://example.test/\(id)", host: "example.test",
                                  status: 200, state: "complete", started: 1, duration: 0.1, size: 11, error: nil)
        let message = FlowMessage(headers: [["content-type", "application/json"]], body: "{\"id\":\"\(id)\"}",
                                  truncated: false, streamed: false, httpVersion: "HTTP/2.0")
        return FlowDetail(summary: summary, request: message, response: message)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for detail loading")
    }

    @MainActor
    func testChangingSelectedRowDoesNotPublishAnEmptyInspector() async {
        let gate = DetailGate()
        let model = CaptureModel(detailLoader: { await gate.load($0) })
        model.selectedID = "a"
        await waitUntil { gate.contains("a") }
        gate.finish(detail("a"))
        await waitUntil { model.detail?.flow.summary.id == "a" }
        var becameEmpty = false
        let observation = model.$detail.dropFirst().sink { if $0 == nil { becameEmpty = true } }
        model.selectedID = "b"
        XCTAssertEqual(model.detail?.flow.summary.id, "a")
        XCTAssertTrue(model.loadingDetail)
        await waitUntil { gate.contains("b") }
        gate.finish(detail("b"))
        await waitUntil { model.detail?.flow.summary.id == "b" }
        XCTAssertFalse(becameEmpty, "Switching rows must keep the current inspector visible until the replacement is ready")
        XCTAssertEqual(model.detail?.request.copyText, "{\n  \"id\": \"b\"\n}")
        XCTAssertEqual(model.detail?.response?.copyText, model.detail?.request.copyText)
        XCTAssertFalse(model.loadingDetail)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testReselectingTheSameRowDoesNotReloadOrClearInspector() async {
        var calls = 0
        let model = CaptureModel(detailLoader: { id in calls += 1; return self.detail(id) })
        model.selectedID = "a"
        await waitUntil { model.detail?.flow.summary.id == "a" }
        model.selectedID = "a"
        await Task.yield()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.detail?.flow.summary.id, "a")
        XCTAssertFalse(model.loadingDetail)
    }

    @MainActor
    func testLateResultCannotOverwriteTheMostRecentSelection() async {
        let gate = DetailGate()
        let model = CaptureModel(detailLoader: { await gate.load($0) })
        model.selectedID = "a"
        await waitUntil { gate.contains("a") }
        model.selectedID = "b"
        await waitUntil { gate.contains("b") }
        gate.finish(detail("b"))
        await waitUntil { model.detail?.flow.summary.id == "b" }
        gate.finish(detail("a"))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.detail?.flow.summary.id, "b")
        XCTAssertEqual(model.detail?.response?.copyText, "{\n  \"id\": \"b\"\n}")
        XCTAssertFalse(model.loadingDetail)
    }

    @MainActor
    func testDeselectingClearsInspectorAndRejectsPendingResult() async {
        let gate = DetailGate()
        let model = CaptureModel(detailLoader: { await gate.load($0) })
        model.selectedID = "a"
        await waitUntil { gate.contains("a") }
        model.selectedID = nil
        XCTAssertNil(model.detail)
        XCTAssertFalse(model.loadingDetail)
        gate.finish(detail("a"))
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(model.detail)
    }
}
