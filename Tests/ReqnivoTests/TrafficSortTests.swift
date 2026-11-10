import XCTest
@testable import Reqnivo

final class TrafficSortTests: XCTestCase {
    private func rows() -> [TrafficFlow] {
        [TrafficFlow(id: "a", method: "POST", url: "https://z.test/b", host: "z.test", status: 500,
                     state: "complete", started: 10, duration: 0.01, size: 10000, error: nil, number: 10),
         TrafficFlow(id: "b", method: "GET", url: "https://a.test/a", host: "a.test", status: 200,
                     state: "complete", started: 2, duration: 1.2, size: 900, error: nil, number: 2),
         TrafficFlow(id: "c", method: "DELETE", url: "https://m.test/c", host: "m.test", status: nil,
                     state: "pending", started: 1, duration: 0, size: nil, error: nil, number: 1)]
    }

    func testSortsEveryColumnUsingUnderlyingValues() {
        let expected: [TrafficColumn: [String]] = [
            .number: ["c", "b", "a"], .method: ["c", "b", "a"], .status: ["b", "a", "c"], .source: ["c", "b", "a"],
            .host: ["b", "c", "a"], .path: ["b", "a", "c"], .duration: ["a", "b", "c"], .size: ["b", "a", "c"]
        ]
        for column in TrafficColumn.allCases {
            XCTAssertEqual(TrafficSort(column: column).sorted(rows()).map(\.id), expected[column], column.rawValue)
        }
    }

    func testDescendingNumericSortKeepsUnknownValuesLast() {
        for column in [TrafficColumn.status, .duration, .size] {
            let result = TrafficSort(column: column, ascending: false).sorted(rows())
            XCTAssertEqual(result.last?.id, "c")
        }

        func testSourceSortUsesActualMapLocalFlagAndKeepsUnknownLast() {
            var flows = rows()
            flows[0].mapLocal = true
            flows[1].mapLocal = false
            XCTAssertEqual(TrafficSort(column: .source).sorted(flows).map(\.id), ["b", "a", "c"])
            XCTAssertEqual(TrafficSort(column: .source, ascending: false).sorted(flows).map(\.id), ["a", "b", "c"])
        }
        XCTAssertEqual(TrafficSort(column: .number, ascending: false).sorted(rows()).map(\.number), [10, 2, 1])
        XCTAssertEqual(TrafficSort(column: .size, ascending: false).sorted(rows()).map(\.size), [10000, 900, nil])
    }

    func testSortingDoesNotChangeRequestIdentityAndHasStableTies() {
        var sameStatus = rows()
        for index in sameStatus.indices {
            // Rebuild the fixture with equal statuses to exercise the capture-order tie break.
            let old = sameStatus[index]
            sameStatus[index] = TrafficFlow(id: old.id, method: old.method, url: old.url, host: old.host, status: 200,
                                           state: old.state, started: old.started, duration: old.duration, size: old.size,
                                           error: old.error, number: old.number)
        }
        let sorted = TrafficSort(column: .status, ascending: false).sorted(sameStatus)
        XCTAssertEqual(sorted.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(sorted.first(where: { $0.id == "a" })?.number, 10)
        XCTAssertEqual(Set(sorted.map(\.id)), Set(sameStatus.map(\.id)))
    }

    func testCanReadOlderFlowWithoutNumber() throws {
        let data = Data(#"{"id":"old","method":"GET","url":"https://a.test/","host":"a.test","status":200,"state":"complete","started":1,"duration":0.1,"size":10}"#.utf8)
        let flow = try JSONDecoder().decode(TrafficFlow.self, from: data)
        XCTAssertNil(flow.number)
        XCTAssertEqual(flow.id, "old")
    }
}
