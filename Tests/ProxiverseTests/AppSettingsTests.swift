import XCTest
@testable import Proxiverse

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
        model.allowLAN = false
        model.setMacProxy = true
        model.skipUpstreamVerification = false
        model.inspectorOnRight = true
        model.messagesStacked = true
        model.pinnedHosts.insert("api.test")
        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.proxyPort, 8181)
        XCTAssertEqual(saved.apiPort, 8182)
        XCTAssertFalse(saved.allowLAN)
        XCTAssertTrue(saved.setMacProxy)
        XCTAssertFalse(saved.skipUpstreamVerification)
        XCTAssertEqual(saved.pinnedHosts, ["api.test"])

        let reopened = CaptureModel(settingsStore: store)
        XCTAssertEqual(reopened.proxyPort, 8181)
        XCTAssertEqual(reopened.apiPort, 8182)
        XCTAssertFalse(reopened.allowLAN)
        XCTAssertTrue(reopened.setMacProxy)
        XCTAssertFalse(reopened.skipUpstreamVerification)
        XCTAssertTrue(reopened.inspectorOnRight)
        XCTAssertTrue(reopened.messagesStacked)
        XCTAssertEqual(reopened.pinnedHosts, ["api.test"])
        XCTAssertEqual(reopened.service, model.service)
        XCTAssertFalse(reopened.running)
        XCTAssertTrue(reopened.pinnedIDs.isEmpty)
        reopened.pinnedHosts.remove("api.test")
        XCTAssertEqual(try store.load()?.pinnedHosts, [])
    }

    func testFirstLaunchMigratesExistingLayoutPreferences() throws {
        let store = temporaryStore()
        XCTAssertNil(try store.load())
        let model = CaptureModel(settingsStore: store)
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
