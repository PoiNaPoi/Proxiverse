import XCTest
@testable import Reqnivo

final class PerformanceStatsTests: XCTestCase {
    func testNearestRankPercentilesAndBoundedHistory() {
        var samples = LatencySamples(limit: 100)
        XCTAssertEqual(samples.percentile(0.95), 0)
        for value in 1...100 { samples.add(Double(value)) }
        XCTAssertEqual(samples.percentile(0.5), 50)
        XCTAssertEqual(samples.percentile(0.95), 95)
        XCTAssertEqual(samples.percentile(1), 100)
        samples.add(1_000)
        XCTAssertEqual(samples.count, 100)
        XCTAssertEqual(samples.totalCount, 101)
        XCTAssertEqual(samples.percentile(1), 1_000)
        XCTAssertEqual(samples.last, 1_000)
    }

    func testUIAndEngineUsageAreSplitWithoutDoubleCounting() {
        let output = """
          1     0  1000  1.0
        100     1  2048  2.0
        101   100  4096  3.0
        102   101  1024  4.0
        200     1  9999  9.0
        300   100  3072  5.0
        """
        let processes = ResourceUsage.parse(psOutput: output)
        XCTAssertEqual(processes.count, 6)
        // UI 100 owns the engine (101) and 300 (a UI helper); engine tree is 101 + 102.
        let usage = ResourceUsage.measure(uiPID: 100, enginePID: 101, processes: processes)
        XCTAssertEqual(usage.uiMB, (2048 + 3072) / 1024.0, accuracy: 0.001)
        XCTAssertEqual(usage.engineMB, (4096 + 1024) / 1024.0, accuracy: 0.001)
        XCTAssertEqual(usage.uiCPU, 7, accuracy: 0.001)
        XCTAssertEqual(usage.engineCPU, 7, accuracy: 0.001)
        XCTAssertEqual(usage.totalMB, 10, accuracy: 0.001)
        let stopped = ResourceUsage.measure(uiPID: 100, enginePID: 0, processes: processes)
        XCTAssertEqual(stopped.engineMB, 0)
        XCTAssertEqual(stopped.uiMB, (2048 + 4096 + 1024 + 3072) / 1024.0, accuracy: 0.001)
        XCTAssertTrue(ResourceUsage.parse(psOutput: "garbage line\n1 2 x 4").isEmpty)
    }

    func testEnvironmentPortOverrideIsValidated() {
        setenv("REQNIVO_TEST_PORT", "19090", 1)
        XCTAssertEqual(CaptureModel.environmentPort("REQNIVO_TEST_PORT"), 19090)
        setenv("REQNIVO_TEST_PORT", "80", 1)
        XCTAssertNil(CaptureModel.environmentPort("REQNIVO_TEST_PORT"))
        setenv("REQNIVO_TEST_PORT", "abc", 1)
        XCTAssertNil(CaptureModel.environmentPort("REQNIVO_TEST_PORT"))
        unsetenv("REQNIVO_TEST_PORT")
        XCTAssertNil(CaptureModel.environmentPort("REQNIVO_TEST_PORT"))
    }

    @MainActor
    func testSelectionRenderSampleNeedsEveryVisiblePaneAndMatchingFlow() async {
        func detail(_ id: String, response: Bool) -> FlowDetail {
            let summary = TrafficFlow(id: id, method: "GET", url: "https://t.test/\(id)", host: "t.test", status: 200,
                                      state: "complete", started: 1, duration: 0.1, size: 2, error: nil)
            let message = FlowMessage(headers: [], body: "{}", truncated: false, streamed: false, httpVersion: "HTTP/1.1")
            return FlowDetail(summary: summary, request: message, response: response ? message : nil)
        }
        let model = CaptureModel(detailLoader: { detail($0, response: $0 != "pending") })
        func settle() async { for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(20)) } }
        model.selectedID = "a"
        for _ in 0..<200 where model.detail?.flow.summary.id != "a" { try? await Task.sleep(for: .milliseconds(5)) }
        model.markSelectionRendered(flowID: "stale")
        model.markSelectionRendered(flowID: "a")
        await settle()
        XCTAssertEqual(model.selectionRenderSamples.totalCount, 0, "Only one of two panes reported")
        model.markSelectionRendered(flowID: "a")
        await settle()
        XCTAssertEqual(model.selectionRenderSamples.totalCount, 1)
        model.markSelectionRendered(flowID: "a")
        await settle()
        XCTAssertEqual(model.selectionRenderSamples.totalCount, 1, "A completed selection must not be sampled again")
        model.selectedID = "pending"
        for _ in 0..<200 where model.detail?.flow.summary.id != "pending" { try? await Task.sleep(for: .milliseconds(5)) }
        model.markSelectionRendered(flowID: "pending")
        await settle()
        XCTAssertEqual(model.selectionRenderSamples.totalCount, 2, "Request-only detail needs a single pane")
    }

    @MainActor
    func testUserFilterIsCompletedOnlyByTableReload() async {
        let model = CaptureModel()
        model.markTableReloaded()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.filterEndToEndSamples.totalCount, 0, "No pending user filter yet")
        model.sidebarSelection = .domain("x.test")
        XCTAssertEqual(model.filterModelSamples.totalCount >= 1, true)
        model.markTableReloaded()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.filterEndToEndSamples.totalCount, 1)
        model.markTableReloaded()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.filterEndToEndSamples.totalCount, 1)
    }
}

