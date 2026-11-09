import XCTest
@testable import Proxiverse

@MainActor
final class MacCaptureTests: XCTestCase {
    private func makeModel(macProxyChange: @escaping (Bool) async throws -> Void) -> CaptureModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return CaptureModel(macProxyChange: macProxyChange, settingsStore: AppSettingsStore(root: root))
    }

    func testLiveToggleChangesProxyWithoutClearingTrafficOrStoppingCapture() async {
        var changes: [Bool] = []
        let model = makeModel(macProxyChange: { changes.append($0) })
        model.recoveryNeeded = false
        model.service = "Wi-Fi"
        model.running = true
        model.total = 42

        await model.setMacCaptureEnabled(true)
        XCTAssertTrue(model.setMacProxy)
        XCTAssertEqual(model.macProxyStatusText, "Mac proxy configured")
        await model.setMacCaptureEnabled(false)

        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(model.setMacProxy)
        XCTAssertTrue(model.running)
        XCTAssertEqual(model.total, 42)
        XCTAssertFalse(model.busy)
    }

    func testStopRestoresMacProxyAndKeepsPreferenceForNextCapture() async {
        var changes: [Bool] = []
        let model = makeModel(macProxyChange: { changes.append($0) })
        model.recoveryNeeded = false
        model.service = "Wi-Fi"
        model.running = true
        await model.setMacCaptureEnabled(true)
        await model.stop()
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(model.running)
        XCTAssertTrue(model.setMacProxy)
        XCTAssertFalse(model.busy)
    }

    func testStoppedToggleOnlyConfiguresNextCapture() async {
        var changes: [Bool] = []
        let model = makeModel(macProxyChange: { changes.append($0) })
        model.recoveryNeeded = false
        await model.setMacCaptureEnabled(true)
        XCTAssertTrue(model.setMacProxy)
        XCTAssertFalse(model.running)
        XCTAssertTrue(changes.isEmpty)
    }

    func testAuthorizationFailurePreservesPreviousCheckboxState() async {
        for previous in [false, true] {
            let model = makeModel(macProxyChange: { _ in throw AppFailure("Authorization cancelled") })
            model.recoveryNeeded = false
            model.service = "Wi-Fi"
            model.running = true
            model.setMacProxy = previous
            await model.setMacCaptureEnabled(!previous)
            XCTAssertEqual(model.setMacProxy, previous)
            XCTAssertTrue(model.running)
            XCTAssertFalse(model.busy)
            XCTAssertEqual(model.error, "Authorization cancelled")
        }
    }

    func testToggleIsIgnoredDuringOtherOperationsOrRecovery() async {
        var changes: [Bool] = []
        let model = makeModel(macProxyChange: { changes.append($0) })
        model.running = true
        model.recoveryNeeded = false
        model.busy = true
        await model.setMacCaptureEnabled(true)
        model.busy = false
        model.ruleOperation = true
        await model.setMacCaptureEnabled(true)
        model.ruleOperation = false
        model.recoveryNeeded = true
        await model.setMacCaptureEnabled(true)
        XCTAssertFalse(model.setMacProxy)
        XCTAssertTrue(changes.isEmpty)
    }

    func testMissingNetworkServiceDoesNotEnableMacCapture() async {
        var changes: [Bool] = []
        let model = makeModel(macProxyChange: { changes.append($0) })
        model.recoveryNeeded = false
        model.running = true
        model.service = ""
        await model.setMacCaptureEnabled(true)
        XCTAssertFalse(model.setMacProxy)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertNotNil(model.error)
    }
}
