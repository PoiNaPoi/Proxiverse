import XCTest
@testable import Proxiverse

final class SystemProxyTests: XCTestCase {
    func testNativeProxyUpdatePreservesPACBypassSOCKSAndOtherProtocol() {
        let current: [String: Any] = [
            "HTTPEnable": 0, "HTTPProxy": "old.proxy", "HTTPPort": 8000,
            "HTTPSEnable": 1, "HTTPSProxy": "secure.proxy", "HTTPSPort": 8443,
            "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://test/proxy.pac",
            "ExceptionsList": ["localhost", "*.test"], "ExcludeSimpleHostnames": 1,
            "SOCKSEnable": 1, "SOCKSProxy": "socks.proxy", "SOCKSPort": 1080
        ]
        let endpoint = ProxyEndpoint(enabled: true, server: "127.0.0.1", port: 9090, authenticated: false)
        let updated = SystemProxy.configuration(current, applying: [.init(secure: false, endpoint: endpoint)])
        var expected = current
        expected["HTTPEnable"] = 1
        expected["HTTPProxy"] = "127.0.0.1"
        expected["HTTPPort"] = 9090
        XCTAssertEqual(updated as NSDictionary, expected as NSDictionary)
    }

    func testNativeRecoveryRestoresBothEndpointsIncludingDisabledAddress() throws {
        let http = ProxyEndpoint(enabled: false, server: "old.proxy", port: 8000, authenticated: false)
        let https = ProxyEndpoint(enabled: true, server: "secure.proxy", port: 8443, authenticated: false)
        let owned = ProxyEndpoint(enabled: true, server: "127.0.0.1", port: 9090, authenticated: false)
        let original: [String: Any] = [
            "HTTPEnable": 0, "HTTPProxy": "old.proxy", "HTTPPort": 8000,
            "HTTPSEnable": 1, "HTTPSProxy": "secure.proxy", "HTTPSPort": 8443
        ]
        let captured = SystemProxy.configuration(original, applying: [
            .init(secure: false, endpoint: owned), .init(secure: true, endpoint: owned)
        ])
        let journal = ProxyJournal(service: "Wi-Fi", http: http, https: https, installedPort: 9090)
        let plan = SystemProxy.recoveryPlan(journal: journal, currentHTTP: owned, currentHTTPS: owned)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertEqual(SystemProxy.configuration(captured, applying: plan.changes) as NSDictionary, original as NSDictionary)
    }

    func testEmptyDisabledEndpointOnlyDisablesProxy() {
        let empty = ProxyEndpoint(enabled: false, server: "", port: 0, authenticated: false)
        let current: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9090]
        let updated = SystemProxy.configuration(current, applying: [.init(secure: false, endpoint: empty)])
        XCTAssertEqual(updated as NSDictionary, ["HTTPEnable": 0, "HTTPProxy": "127.0.0.1", "HTTPPort": 9090] as NSDictionary)
    }

    func testLegacyRecoveryJournalRemainsReadableWithoutRequestingAuthorization() throws {
        let data = Data("""
        {"service":"Wi-Fi","installedPort":9090,
         "http":{"enabled":false,"server":"","port":0,"authenticated":false},
         "https":{"enabled":false,"server":"","port":0,"authenticated":false}}
        """.utf8)
        let journal = try JSONDecoder().decode(ProxyJournal.self, from: data)
        let plan = SystemProxy.recoveryPlan(journal: journal, currentHTTP: journal.http, currentHTTPS: journal.https)
        XCTAssertTrue(plan.changes.isEmpty)
        XCTAssertTrue(plan.conflicts.isEmpty)
    }
}
