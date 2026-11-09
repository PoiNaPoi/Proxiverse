import XCTest
@testable import Proxiverse

final class TrafficTests: XCTestCase {
    func flow(_ id: String, status: Int? = nil, host: String = "api.test") -> TrafficFlow {
        TrafficFlow(id: id, method: "GET", url: "https://\(host)/cards?active=true", host: host,
                    status: status, state: status == nil ? "pending" : "complete", started: 1,
                    duration: 0.1, size: 12, error: nil)
    }

    func testUpdatesReplaceExistingRowAndRetentionEvictsOldest() {
        var buffer = TrafficBuffer(limit: 2)
        buffer.apply([FlowEvent(sequence: 1, flow: flow("a")), FlowEvent(sequence: 2, flow: flow("b"))])
        buffer.apply([FlowEvent(sequence: 3, flow: flow("a", status: 200))])
        XCTAssertEqual(buffer.rows.map(\.id), ["a", "b"])
        XCTAssertEqual(buffer.rows[0].status, 200)
        buffer.apply([FlowEvent(sequence: 4, flow: flow("c"))])
        XCTAssertEqual(buffer.rows.map(\.id), ["b", "c"])
        buffer.apply([FlowEvent(sequence: 5, flow: flow("b", status: 404))])
        XCTAssertEqual(buffer.rows[0].status, 404)
    }

    func testFilterCombinesHostWithCaseInsensitiveMethodURLAndStatus() {
        var buffer = TrafficBuffer()
        buffer.apply([FlowEvent(sequence: 1, flow: flow("a", status: 200)),
                      FlowEvent(sequence: 2, flow: flow("b", status: 404, host: "other.test"))])
        XCTAssertEqual(buffer.filtered(search: "ACTIVE=TRUE", host: "api.test").map(\.id), ["a"])
        XCTAssertEqual(buffer.filtered(search: "404", host: nil).map(\.id), ["b"])
        XCTAssertTrue(buffer.filtered(search: "404", host: "api.test").isEmpty)
    }

    func testSidebarFilterMatchesDomainsPathsAndClients() {
        let f1 = TrafficFlow(id: "1", method: "GET", url: "https://api.test/v1/cards?limit=10", host: "api.test",
                             status: 200, state: "complete", started: 1, duration: 0.1, size: 100, error: nil, number: 1, client: "127.0.0.1")
        let f2 = TrafficFlow(id: "2", method: "POST", url: "https://api.test/v1/users", host: "api.test",
                             status: 201, state: "complete", started: 2, duration: 0.1, size: 50, error: nil, number: 2, client: "192.168.1.50")
        let f3 = TrafficFlow(id: "3", method: "GET", url: "https://auth.test/oauth/token", host: "auth.test",
                             status: 200, state: "complete", started: 3, duration: 0.1, size: 80, error: nil, number: 3, client: nil)

        var buffer = TrafficBuffer()
        buffer.apply([FlowEvent(sequence: 1, flow: f1), FlowEvent(sequence: 2, flow: f2), FlowEvent(sequence: 3, flow: f3)])

        XCTAssertEqual(buffer.filtered(search: "", sidebar: .all).count, 3)
        XCTAssertEqual(buffer.filtered(search: "", sidebar: .domain("API.TEST")).map(\.id), ["1", "2"])
        XCTAssertEqual(buffer.filtered(search: "", sidebar: .domainPath(host: "api.test", pathPrefix: "/v1/cards")).map(\.id), ["1"])
        XCTAssertEqual(buffer.filtered(search: "", sidebar: .domainPath(host: "api.test", pathPrefix: "/v1")).count, 2)
        XCTAssertEqual(buffer.filtered(search: "", sidebar: .client("127.0.0.1")).map(\.id), ["1"])
        XCTAssertEqual(buffer.filtered(search: "", sidebar: .client("192.168.1.50")).map(\.id), ["2"])
        XCTAssertEqual(buffer.filtered(search: "", sidebar: .client("Unknown")).map(\.id), ["3"])
    }

    func testProxySnapshotPreservesDisabledSettings() throws {
        let snapshot = try ProxyEndpoint(output: "Enabled: No\nServer: old.proxy\nPort: 8888\nAuthenticated Proxy Enabled: 0\n")
        XCTAssertFalse(snapshot.enabled)
        XCTAssertEqual(snapshot.server, "old.proxy")
        XCTAssertEqual(snapshot.port, 8888)
        XCTAssertFalse(snapshot.authenticated)
        XCTAssertThrowsError(try ProxyEndpoint(output: "permission denied"))
    }

    func testRecoveryRestoresOwnedHTTPSWhenHTTPWasChangedElsewhere() throws {
        let disabled = try ProxyEndpoint(output: "Enabled: No\nServer: \nPort: 0\nAuthenticated Proxy Enabled: 0")
        let owned = try ProxyEndpoint(output: "Enabled: Yes\nServer: 127.0.0.1\nPort: 9090\nAuthenticated Proxy Enabled: 0")
        let external = try ProxyEndpoint(output: "Enabled: Yes\nServer: other.proxy\nPort: 8000\nAuthenticated Proxy Enabled: 0")
        let journal = ProxyJournal(service: "Wi-Fi", http: disabled, https: disabled, installedPort: 9090)
        let plan = SystemProxy.recoveryPlan(journal: journal, currentHTTP: external, currentHTTPS: owned)
        XCTAssertEqual(plan.conflicts, ["HTTP"])
        XCTAssertEqual(plan.changes, [SystemProxy.Change(secure: true, endpoint: disabled)])
    }

    func testRecoveryPreservesExistingProxyEndpointAndState() throws {
        let previous = try ProxyEndpoint(output: "Enabled: Yes\nServer: old.proxy\nPort: 8000\nAuthenticated Proxy Enabled: 0")
        let owned = try ProxyEndpoint(output: "Enabled: Yes\nServer: 127.0.0.1\nPort: 9090\nAuthenticated Proxy Enabled: 0")
        let journal = ProxyJournal(service: "Wi-Fi", http: previous, https: previous, installedPort: 9090)
        let plan = SystemProxy.recoveryPlan(journal: journal, currentHTTP: owned, currentHTTPS: owned)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertEqual(plan.changes, [SystemProxy.Change(secure: false, endpoint: previous),
                                      SystemProxy.Change(secure: true, endpoint: previous)])
    }

    func testTenThousandRowsUpdateAndFilterBaseline() {
        var buffer = TrafficBuffer()
        buffer.apply((0..<10_000).map { FlowEvent(sequence: $0, flow: flow(String($0))) })
        measure {
            XCTAssertEqual(buffer.filtered(search: "active", host: "api.test").count, 10_000)
        }
    }
}
