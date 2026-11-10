import XCTest
@testable import Reqnivo

final class DebugRulesTests: XCTestCase {
    func testSeparateEditorsOnlyReadTheirOwnRuleKind() {
        let map = DebugRule()
        var breakpoint = DebugRule()
        breakpoint.kind = "breakpoint"
        let all = [map, breakpoint]
        XCTAssertEqual(DebugRuleKind.mapLocal.rules(in: all), [map])
        XCTAssertEqual(DebugRuleKind.breakpoint.rules(in: all), [breakpoint])
    }

    func testSavingReorderingAndDeletingOneKindPreservesTheOtherKind() throws {
        let map1 = DebugRule()
        let map2 = DebugRule()
        var breakpoint1 = DebugRule()
        breakpoint1.kind = "breakpoint"
        var breakpoint2 = breakpoint1
        breakpoint2.id = UUID().uuidString
        let original = [map1, breakpoint1, map2, breakpoint2]
        let reordered = try DebugRuleKind.mapLocal.replacingRules(in: original, with: [map2, map1])
        XCTAssertEqual(reordered, [map2, breakpoint1, map1, breakpoint2])
        let deleted = try DebugRuleKind.mapLocal.replacingRules(in: original, with: [])
        XCTAssertEqual(deleted, [breakpoint1, breakpoint2])
        var changed = breakpoint2
        changed.host = "new.test"
        let edited = try DebugRuleKind.breakpoint.replacingRules(in: original, with: [changed])
        XCTAssertEqual(edited, [map1, changed, map2])
        XCTAssertEqual(DebugRuleKind.mapLocal.rules(in: edited), [map1, map2])
    }

    func testAddingRulesAndSavingAgainstLatestRulesDoesNotOverwriteTheOtherEditor() throws {
        let map = DebugRule()
        let addedMap = DebugRule()
        var breakpoint = DebugRule()
        breakpoint.kind = "breakpoint"
        breakpoint.host = "changed-while-map-editor-was-open.test"
        let merged = try DebugRuleKind.mapLocal.replacingRules(in: [map, breakpoint], with: [map, addedMap])
        XCTAssertEqual(merged, [map, breakpoint, addedMap])
        XCTAssertEqual(try DebugRuleKind.breakpoint.replacingRules(in: [map], with: [breakpoint]), [map, breakpoint])
        XCTAssertThrowsError(try DebugRuleKind.mapLocal.replacingRules(in: merged, with: [breakpoint]))
    }

    func testManagedCopySurvivesOriginalChangeAndRulesRoundTripInOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.json")
        try Data("{\"ok\":true}".utf8).write(to: source)
        let store = RuleStore(root: root.appendingPathComponent("data"))
        var map = DebugRule()
        map.file = try store.importFile(source)
        var breakpoint = DebugRule()
        breakpoint.kind = "breakpoint"
        breakpoint.response = true
        let rules = [breakpoint, map]
        try store.validate(rules)
        try store.save(rules)
        try Data("changed".utf8).write(to: source)
        XCTAssertEqual(try store.load(), rules)
        XCTAssertEqual(try String(contentsOf: store.assets.appendingPathComponent(map.file)), "{\"ok\":true}")
    }

    func testRejectsMissingMockAndNoBreakpointPhase() throws {
        let store = RuleStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var rule = DebugRule()
        XCTAssertThrowsError(try store.validate([rule]))
        rule.kind = "breakpoint"
        rule.request = false
        XCTAssertThrowsError(try store.validate([rule]))
        rule.response = true
        XCTAssertNoThrow(try store.validate([rule]))
        rule.host = ""
        XCTAssertThrowsError(try store.validate([rule]))
    }

    func testRejectsInvalidMapStatusDelayAndHeaders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(root: root)
        try FileManager.default.createDirectory(at: store.assets, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: store.assets.appendingPathComponent("test.mock"))
        var rule = DebugRule()
        rule.file = "test.mock"
        XCTAssertNoThrow(try store.validate([rule]))
        rule.status = 999
        XCTAssertThrowsError(try store.validate([rule]))
        rule.status = 200
        rule.delayMilliseconds = -1
        XCTAssertThrowsError(try store.validate([rule]))
        rule.delayMilliseconds = 0
        rule.headers = "invalid"
        XCTAssertThrowsError(try store.validate([rule]))
    }

    func testPausedPayloadDecodesUneditableBodyAndEncodesCancel() throws {
        let json = #"{"id":"one","phase":"response","url":"http://test/","method":"GET","status":200,"headers":"","body":null,"cancel":false}"#
        var edit = try JSONDecoder().decode(PausedEdit.self, from: Data(json.utf8))
        XCTAssertNil(edit.body)
        edit.cancel = true
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any]
        XCTAssertEqual(payload?["cancel"] as? Bool, true)
    }

    @MainActor func testLaunchDefaultsUseLocalhostWithoutEnablingSystemProxy() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CaptureModel(settingsStore: AppSettingsStore(root: root))
        XCTAssertFalse(model.allowLAN)
        XCTAssertFalse(model.setMacProxy)
    }

    @MainActor func testMapLocalContextActionOnlyOpensTheMapLocalManager() async {
        let flow = TrafficFlow(id: "fixture", method: "GET", url: "https://fixture.test/items",
                               host: "fixture.test", status: 200, state: "complete",
                               started: 1, duration: 0.1, size: 2, error: nil)
        let message = FlowMessage(headers: [["content-type", "application/json"], ["content-length", "2"]],
                                  body: #"{"id":12345678901234567890,"value":"captured"}"#, truncated: false,
                                  streamed: false, httpVersion: "HTTP/2", captureState: .complete)
        let request = FlowMessage(headers: [], body: "not the response", truncated: false,
                                  streamed: false, httpVersion: "HTTP/2", captureState: .complete)
        let other = TrafficFlow(id: "selected", method: "GET", url: "https://other.test/selected",
                                host: "other.test", status: 200, state: "complete",
                                started: 2, duration: 0.1, size: 2, error: nil)
        let model = CaptureModel(detailLoader: { id in
            if id == other.id { return FlowDetail(summary: other, request: request, response: request) }
            XCTAssertEqual(id, flow.id)
            return FlowDetail(summary: flow, request: request, response: message)
        })
        model.selectedID = other.id
        model.openMapLocal(flow)
        for _ in 0..<100 {
            if model.showMapLocalRules { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.showMapLocalRules)
        XCTAssertFalse(model.showBreakpoints)
        XCTAssertEqual(model.pendingMapLocal?.rule.kind, "mapLocal")
        XCTAssertEqual(model.pendingMapLocal?.rule.host, "fixture.test")
        XCTAssertEqual(model.pendingMapLocal?.rule.bodySource, .text)
        XCTAssertEqual(model.pendingMapLocal?.rule.headers, "content-type: application/json")
        XCTAssertEqual(model.pendingMapLocal?.body, message.body)
        XCTAssertNil(model.pendingMapLocal?.notice)
    }

    func testMapLocalDoesNotPrefillOmittedPartialOrLegacyBodies() {
        let flow = TrafficFlow(id: "fixture", method: "GET", url: "https://fixture.test/items",
                               host: "fixture.test", status: 200, state: "complete",
                               started: 1, duration: 0.1, size: 2, error: nil)
        for state: BodyCaptureState? in [nil, .truncated, .streamed, .encoded, .binary] {
            let message = FlowMessage(headers: [], body: "must not be mocked", truncated: false,
                                      streamed: false, httpVersion: "HTTP/2", captureState: state)
            let prefill = MapLocalPrefill.captured(flow, response: message)
            XCTAssertNil(prefill.body)
            XCTAssertNotNil(prefill.notice)
        }
        for flags in [(true, false), (false, true)] {
            let message = FlowMessage(headers: [], body: "partial", truncated: flags.0,
                                      streamed: flags.1, httpVersion: "HTTP/2", captureState: .complete)
            XCTAssertNil(MapLocalPrefill.captured(flow, response: message).body)
        }
        let missing = MapLocalPrefill.captured(flow, response: nil)
        XCTAssertNil(missing.body)
        XCTAssertNotNil(missing.notice)
        let empty = FlowMessage(headers: [], body: "", truncated: false,
                                streamed: false, httpVersion: "HTTP/2", captureState: .complete)
        XCTAssertEqual(MapLocalPrefill.captured(flow, response: empty).body, "")
        XCTAssertNil(MapLocalPrefill.captured(flow, response: empty).notice)
    }

    @MainActor func testMapLocalDetailFailureExplicitlyExplainsMissingPrefill() async {
        let flow = TrafficFlow(id: "missing", method: "POST", url: "https://fixture.test/new",
                               host: "fixture.test", status: nil, state: "pending",
                               started: 1, duration: 0, size: nil, error: nil)
        let model = CaptureModel(detailLoader: { _ in throw AppFailure("Fixture detail unavailable") })
        model.openMapLocal(flow)
        for _ in 0..<100 {
            if model.showMapLocalRules { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.showMapLocalRules)
        XCTAssertEqual(model.pendingMapLocal?.rule.path, "/new")
        XCTAssertNil(model.pendingMapLocal?.body)
        XCTAssertTrue(model.pendingMapLocal?.notice?.contains("Fixture detail unavailable") == true)
    }
}
