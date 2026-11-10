import XCTest
@testable import Reqnivo

final class EngineContractTests: XCTestCase {
    func testLegacyMessageAndHealthRemainReadable() throws {
        let message = try JSONDecoder().decode(FlowMessage.self, from: Data("""
        {"headers":[["Set-Cookie","a=1"],["Set-Cookie","b=2"]],"body":"{}","truncated":false,"streamed":false,"httpVersion":"HTTP/2"}
        """.utf8))
        XCTAssertNil(message.captureState)
        XCTAssertEqual(message.headers.count, 2)
        let health = try JSONDecoder().decode(EngineHealth.self, from: Data("""
        {"ready":true,"total":1,"retained":1,"uptime":2}
        """.utf8))
        XCTAssertNoThrow(try health.validateVersion())
    }

    func testVersionAndExplicitBodyStatesRoundTrip() throws {
        for state: BodyCaptureState in [.complete, .truncated, .streamed, .encoded, .binary] {
            let original = FlowMessage(headers: [], body: "", truncated: state == .truncated,
                                       streamed: state == .streamed, httpVersion: "HTTP/1.1", captureState: state)
            XCTAssertEqual(try JSONDecoder().decode(FlowMessage.self, from: JSONEncoder().encode(original)), original)
        }
        XCTAssertNoThrow(try EngineHealth(ready: true, total: 0, retained: 0, uptime: 0, apiVersion: 1).validateVersion())
        XCTAssertThrowsError(try EngineHealth(ready: true, total: 0, retained: 0, uptime: 0, apiVersion: 2).validateVersion())
    }

    func testUnsupportedAPIVersionsAreRejectedAndMissingVersionIsLegacy() throws {
        for version in [0, 2, 99, -1] {
            XCTAssertThrowsError(try EngineHealth(ready: true, total: 0, retained: 0, uptime: 0, apiVersion: version).validateVersion())
        }
        let decoded = try JSONDecoder().decode(EngineHealth.self, from: Data(#"{"ready":true,"total":0,"retained":0,"uptime":1,"apiVersion":3}"#.utf8))
        XCTAssertEqual(decoded.apiVersion, 3)
        XCTAssertThrowsError(try decoded.validateVersion())
        let legacy = try JSONDecoder().decode(EngineHealth.self, from: Data(#"{"ready":true,"total":0,"retained":0,"uptime":1}"#.utf8))
        XCTAssertNil(legacy.apiVersion)
        XCTAssertNoThrow(try legacy.validateVersion())
    }

    func testLegacyFlowDetailWithoutNumberClientOrCaptureStateStillDecodes() throws {
        let json = """
        {"summary":{"id":"old","method":"GET","url":"https://old.test/a?x=1","host":"old.test","status":200,
                    "state":"complete","started":1,"duration":0.1,"size":2,"error":null},
         "request":{"headers":[],"body":"","truncated":false,"streamed":false,"httpVersion":"HTTP/1.1"},
         "response":{"headers":[["Content-Type","application/json"]],"body":"{}","truncated":false,"streamed":false,"httpVersion":"HTTP/1.1"}}
        """
        let detail = try JSONDecoder().decode(FlowDetail.self, from: Data(json.utf8))
        XCTAssertNil(detail.summary.number)
        XCTAssertNil(detail.summary.client)
        XCTAssertNil(detail.summary.mapLocal)
        XCTAssertNil(detail.request.captureState)
        XCTAssertNil(detail.response?.captureState)
        XCTAssertEqual(InspectorDetail(flow: detail).response?.copyText, "{}")
        let pending = #"{"summary":{"id":"p","method":"GET","url":"https://old.test/","host":"old.test","status":null,"state":"pending","started":1,"duration":0,"size":null,"error":null},"request":{"headers":[],"body":"","truncated":false,"streamed":false,"httpVersion":"HTTP/1.1"},"response":null}"#
        XCTAssertNil(try JSONDecoder().decode(FlowDetail.self, from: Data(pending.utf8)).response)
    }

    func testLegacyRulesWithoutBodySourceLoadAndValidateAsFileRules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(root: root)
        try FileManager.default.createDirectory(at: store.assets, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: store.assets.appendingPathComponent("legacy.mock"))
        let json = """
        [{"id":"r1","name":"Old","enabled":true,"kind":"mapLocal","host":"api.test","path":"/*","method":"GET",
          "file":"legacy.mock","status":200,"headers":"Content-Type: application/json","delayMilliseconds":0,
          "request":true,"response":false},
         {"id":"r2","name":"Break","enabled":false,"kind":"breakpoint","host":"*","path":"/*","method":"*",
          "file":"","status":200,"headers":"","delayMilliseconds":0,"request":true,"response":true}]
        """
        try Data(json.utf8).write(to: store.file)
        let rules = try store.load()
        XCTAssertEqual(rules.map(\.id), ["r1", "r2"])
        XCTAssertNil(rules[0].bodySource)
        XCTAssertNoThrow(try store.validate(rules))
        let prepared = try store.prepareRules(rules, inlineBodies: [:])
        XCTAssertEqual(prepared, rules)
    }

    func testMapLocalAttributionDecodesAndRoundTrips() throws {
        for mapped in [true, false] {
            let json = """
            {"id":"mapped","method":"GET","url":"https://api.test/mock","host":"api.test","status":200,
             "state":"complete","started":1,"duration":0.1,"size":2,"mapLocal":\(mapped)}
            """
            let flow = try JSONDecoder().decode(TrafficFlow.self, from: Data(json.utf8))
            XCTAssertEqual(flow.mapLocal, mapped)
            XCTAssertEqual(try JSONDecoder().decode(TrafficFlow.self, from: JSONEncoder().encode(flow)), flow)
        }
    }

    func testBodyStatesDriveMapLocalPrefillAndInspectorPresentation() {
        let flow = TrafficFlow(id: "f", method: "GET", url: "https://t.test/", host: "t.test", status: 200,
                               state: "complete", started: 1, duration: 0.1, size: 2, error: nil)
        let states: [(BodyCaptureState?, Bool)] = [(.complete, true), (.truncated, false), (.streamed, false),
                                                   (.encoded, false), (.binary, false), (nil, false)]
        for (state, prefills) in states {
            let message = FlowMessage(headers: [], body: "{\"a\":1}", truncated: state == .truncated,
                                      streamed: state == .streamed, httpVersion: "HTTP/1.1", captureState: state)
            XCTAssertEqual(MapLocalPrefill.captured(flow, response: message).body != nil, prefills, "\(String(describing: state))")
            XCTAssertEqual(MessagePreview.render(message).copyText, state == .truncated || state == .streamed ? "{\"a\":1}" : "{\n  \"a\": 1\n}")
        }
    }
}
