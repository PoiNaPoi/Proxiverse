import XCTest
@testable import Reqnivo

@MainActor
final class AppSettingsTests: XCTestCase {
    private func temporaryStore() -> AppSettingsStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppSettingsStore(root: root)
    }

    func testSettingsAndDomainPinsSurviveRelaunch() throws {
        let store = temporaryStore()
        let model = CaptureModel(settingsStore: store)
        model.proxyPort = 8181
        model.apiPort = 8182
        model.allowLAN = true
        model.setMacProxy = true
        model.skipUpstreamVerification = true
        model.inspectorOnRight = true
        model.messagesStacked = true
        model.pinnedHosts.insert("api.test")
        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.proxyPort, 8181)
        XCTAssertEqual(saved.apiPort, 8182)
        XCTAssertTrue(saved.allowLAN)
        XCTAssertTrue(saved.setMacProxy)
        XCTAssertTrue(saved.skipUpstreamVerification)
        XCTAssertEqual(saved.pinnedHosts, ["api.test"])

        let reopened = CaptureModel(settingsStore: store)
        XCTAssertEqual(reopened.proxyPort, 8181)
        XCTAssertEqual(reopened.apiPort, 8182)
        XCTAssertTrue(reopened.allowLAN)
        XCTAssertTrue(reopened.setMacProxy)
        XCTAssertTrue(reopened.skipUpstreamVerification)
        XCTAssertTrue(reopened.inspectorOnRight)
        XCTAssertTrue(reopened.messagesStacked)
        XCTAssertEqual(reopened.pinnedHosts, ["api.test"])
        XCTAssertEqual(reopened.service, model.service)
        XCTAssertFalse(reopened.running)
        XCTAssertTrue(reopened.pinnedIDs.isEmpty)
        reopened.pinnedHosts.remove("api.test")
        XCTAssertEqual(try store.load()?.pinnedHosts, [])
    }

    func testLegacyPasswordSettingsAreRemovedWithoutLosingOtherSettings() throws {
        for mode in ["password", "approvedDevices"] {
            let store = temporaryStore()
            var legacy = AppSettings()
            legacy.allowLAN = true
            legacy.proxyPort = 8181
            legacy.pinnedHosts = ["api.test"]
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            json["lanAccessMode"] = mode
            json["lanProxyPassword"] = "old-test-password"
            try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: json).write(to: store.file)
            let model = CaptureModel(settingsStore: store)
            XCTAssertTrue(model.allowLAN)
            XCTAssertEqual(model.proxyPort, 8181)
            XCTAssertEqual(model.pinnedHosts, ["api.test"])
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any])
            XCTAssertNil(saved["lanProxyPassword"])
            XCTAssertNil(saved["lanAccessMode"])
        }
    }

    func testLANDeviceApprovalsDoNotSurviveRelaunch() throws {
        let store = temporaryStore()
        let model = CaptureModel(settingsStore: store)
        model.allowLAN = true
        model.lanDevices = [LANDevice(ip: "192.0.2.10", approved: true)]
        let reopened = CaptureModel(settingsStore: store)
        XCTAssertTrue(reopened.allowLAN)
        XCTAssertTrue(reopened.lanDevices.isEmpty)
    }

    func testFirstLaunchMigratesExistingLayoutPreferences() throws {
        let store = temporaryStore()
        XCTAssertNil(try store.load())
        let model = CaptureModel(settingsStore: store)
        XCTAssertFalse(model.allowLAN)
        XCTAssertFalse(model.skipUpstreamVerification)
        XCTAssertFalse(try XCTUnwrap(store.load()).allowLAN)
        XCTAssertFalse(try XCTUnwrap(store.load()).skipUpstreamVerification)
        XCTAssertEqual(model.inspectorOnRight, UserDefaults.standard.bool(forKey: "workspace.inspectorOnRight"))
        XCTAssertEqual(model.messagesStacked, UserDefaults.standard.bool(forKey: "workspace.messagesStacked"))
        XCTAssertNotNil(try store.load())
    }

    func testCorruptSettingsAreNotOverwritten() throws {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: store.file)
        let model = CaptureModel(settingsStore: store)
        XCTAssertNotNil(model.error)
        model.pinnedHosts.insert("api.test")
        model.proxyPort = 8181
        XCTAssertEqual(try String(contentsOf: store.file), "broken")
    }

    func testWriteFailureIsReported() throws {
        let store = temporaryStore()
        let model = CaptureModel(settingsStore: store)
        try FileManager.default.removeItem(at: store.root)
        try Data("not a directory".utf8).write(to: store.root)
        model.pinnedHosts.insert("api.test")
        XCTAssertTrue(model.error?.hasPrefix("Could not save settings:") == true)
    }
}
