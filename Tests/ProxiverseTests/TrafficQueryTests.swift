import XCTest
@testable import Proxiverse

final class TrafficQueryTests: XCTestCase {
    private var flow: TrafficFlow {
        TrafficFlow(id: "a", method: "GET", url: "https://api.test/v1/cards?active=true", host: "api.test",
                    status: 404, state: "complete", started: 1, duration: 0.1, size: 2, error: nil,
                    contentType: "application/json; charset=utf-8")
    }

    func testFieldsCombineWithANDAndNegation() throws {
        XCTAssertTrue(try TrafficQuery.parse("host:API.TEST path:ACTIVE method:get status:400-499 type:JSON -state:pending").matches(flow))
        XCTAssertFalse(try TrafficQuery.parse("host:api.test method:POST").matches(flow))
        XCTAssertFalse(try TrafficQuery.parse("-status:404").matches(flow))
        XCTAssertFalse(try TrafficQuery.parse("host:test").matches(flow))
        XCTAssertTrue(try TrafficQuery.parse("method:GET active=true").matches(flow))
    }

    func testStatusBoundariesAndMissingMetadata() throws {
        for value in ["100", "599", "100-599", "404-404"] {
            XCTAssertNoThrow(try TrafficQuery.parse("status:\(value)"))
        }
        for query in ["status:99", "status:600", "status:499-400", "status:200-", "status:2xx",
                      "status:100-200-300", "status:٢٠٠", "state:paused", "host:", "typo:one",
                      "host:\"unterminated", #"host:"bad\q""#] {
            XCTAssertThrowsError(try TrafficQuery.parse(query), query)
        }
        var pending = flow
        pending = TrafficFlow(id: "p", method: "GET", url: pending.url, host: pending.host,
                              status: nil, state: "pending", started: 1, duration: 0, size: nil, error: nil)
        XCTAssertFalse(try TrafficQuery.parse("status:100-599").matches(pending))
        XCTAssertFalse(try TrafficQuery.parse("type:json").matches(pending))
        XCTAssertTrue(try TrafficQuery.parse("-status:404 -type:json state:pending").matches(pending))
    }

    func testPlainTextCompatibilityAndQuotedRoundTrip() throws {
        for text in ["GET https://api.test", "ACTIVE=TRUE", "404", "https://api.test/v1", ""] {
            let query = try TrafficQuery.parse(text)
            XCTAssertEqual(query.freeText, text)
            XCTAssertTrue(query.matches(flow))
        }
        let query = TrafficQuery(terms: [try .init(field: .path, value: "/a \"b\"\\c", excluded: true)],
                                 freeText: "error: detail \"quoted\"")
        XCTAssertEqual(try TrafficQuery.parse(query.text), query)
        let unicode = TrafficQuery(terms: [try .init(field: .path, value: "/ค้นหา?text=hello world")],
                                   freeText: "ข้อความ \"UTF-8\"")
        XCTAssertEqual(try TrafficQuery.parse(unicode.text), unicode)
        XCTAssertEqual(try TrafficQuery.parse("GET  https://api.test").freeText, "GET  https://api.test")
    }

    func testLegacyAndNewContentTypeContract() throws {
        let data = try JSONEncoder().encode(flow)
        XCTAssertEqual(try JSONDecoder().decode(TrafficFlow.self, from: data).contentType, flow.contentType)
        let legacy = #"{"id":"a","method":"GET","url":"https://t.test","host":"t.test","state":"pending","started":1,"duration":0}"#
        XCTAssertNil(try JSONDecoder().decode(TrafficFlow.self, from: Data(legacy.utf8)).contentType)
    }
}
