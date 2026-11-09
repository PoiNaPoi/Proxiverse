import XCTest
@testable import Proxiverse

final class HTTPSDecryptionTests: XCTestCase {
    func testExactHostInputRejectsPatternsAndURLs() throws {
        XCTAssertEqual(try HTTPSDecryption.normalizedHost(" API.Example.COM. "), "api.example.com")
        XCTAssertEqual(try HTTPSDecryption.normalizedHost("127.0.0.1"), "127.0.0.1")
        XCTAssertEqual(try HTTPSDecryption.normalizedHost("::1"), "::1")
        for invalid in ["", "*", "*.example.com", "https://api.test", "api.test:443", "api.test/a", "a..test", "-bad.test", ".api.test", "api.test.."] {
            XCTAssertThrowsError(try HTTPSDecryption.normalizedHost(invalid), invalid)
        }
    }

    @MainActor
    func testSelectionPersistsIncludingDisabledHostsAndMatchesExactly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppSettingsStore(root: root)
        let model = CaptureModel(settingsStore: store)
        XCTAssertFalse(model.isHTTPSDecryptionEnabled("api.test"))
        await model.setHTTPSDecryption("API.test", enabled: true)
        await model.setHTTPSDecryption("other.test", enabled: true)
        await model.setHTTPSDecryption("other.test", enabled: false)
        let reopened = CaptureModel(settingsStore: store)
        XCTAssertTrue(reopened.isHTTPSDecryptionEnabled("api.test"))
        XCTAssertFalse(reopened.isHTTPSDecryptionEnabled("sub.api.test"))
        XCTAssertEqual(reopened.httpsDecryptionHosts["other.test"], false)
        await reopened.setHTTPSDecryption("api.test", enabled: false)
        XCTAssertEqual(try store.load()?.httpsDecryptionHosts?["api.test"], false)
        await reopened.setHTTPSDecryption("*.test", enabled: true)
        XCTAssertNotNil(reopened.error)
        XCTAssertNil(reopened.httpsDecryptionHosts["*.test"])
    }

    @MainActor
    func testObservedHostsStayOutAndDeletedHostsDoNotReappear() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppSettingsStore(root: root)
        let model = CaptureModel(settingsStore: store)
        model.hosts = ["observed.test", "api.test", "keep.test"]
        XCTAssertTrue(model.availableHTTPSHosts.isEmpty)
        await model.setHTTPSDecryption("observed.test", enabled: false)
        XCTAssertTrue(model.availableHTTPSHosts.isEmpty)
        await model.setHTTPSDecryption("api.test", enabled: true)
        await model.setHTTPSDecryption("keep.test", enabled: true)
        await model.setHTTPSDecryption("api.test", enabled: false)
        XCTAssertEqual(model.availableHTTPSHosts, ["api.test", "keep.test"])
        await model.removeHTTPSDecryption("API.TEST")
        XCTAssertEqual(model.availableHTTPSHosts, ["keep.test"])
        XCTAssertFalse(model.isHTTPSDecryptionEnabled("api.test"))
        XCTAssertTrue(model.isHTTPSDecryptionEnabled("keep.test"))
        let reopened = CaptureModel(settingsStore: store)
        reopened.hosts = model.hosts
        XCTAssertEqual(reopened.availableHTTPSHosts, ["keep.test"])
        await reopened.removeHTTPSDecryption("keep.test")
        XCTAssertTrue(reopened.availableHTTPSHosts.isEmpty)
        XCTAssertFalse(reopened.isHTTPSDecryptionEnabled("keep.test"))
        XCTAssertEqual(try store.load()?.httpsDecryptionHosts, [:])
    }

    func testLegacySettingsKeepExistingPreferencesWithNoDecryptionEnabled() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
        object.removeValue(forKey: "httpsDecryptionHosts")
        object["proxyPort"] = 8181
        let legacy = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.proxyPort, 8181)
        XCTAssertNil(legacy.httpsDecryptionHosts)
    }

    func testEncryptedConnectionCanBeFilteredAndDecoded() throws {
        let flow = TrafficFlow(id: "tls", method: "CONNECT", url: "https://api.test:443/", host: "api.test",
                               status: nil, state: "tls-passthrough", started: 1, duration: 0, size: nil, error: nil,
                               tlsPassthrough: true)
        XCTAssertTrue(try TrafficQuery.parse("state:tls-passthrough").matches(flow))
        XCTAssertFalse(try TrafficQuery.parse("state:complete").matches(flow))
        XCTAssertEqual(try JSONDecoder().decode(TrafficFlow.self, from: JSONEncoder().encode(flow)), flow)
    }
}
