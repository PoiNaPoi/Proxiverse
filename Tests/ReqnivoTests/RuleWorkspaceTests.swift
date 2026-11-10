import XCTest
@testable import Reqnivo

@MainActor
final class RuleWorkspaceTests: XCTestCase {
    private func makeModel() throws -> CaptureModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previous = ProcessInfo.processInfo.environment["REQNIVO_DATA_DIR"]
        setenv("REQNIVO_DATA_DIR", root.path, 1)
        defer {
            if let previous { setenv("REQNIVO_DATA_DIR", previous, 1) }
            else { unsetenv("REQNIVO_DATA_DIR") }
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return CaptureModel()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Autosave did not finish")
    }

    func testRapidBodyEditsPersistLatestValueAndInvalidEditKeepsSavedRules() async throws {
        let model = try makeModel()
        let workspace = RuleWorkspace(model: model, kind: .mapLocal)
        workspace.load()
        var rule = DebugRule()
        rule.bodySource = .text
        workspace.draft.add(rule)
        workspace.draft.setBody("first", for: rule.id)
        workspace.draft.setBody("latest", for: rule.id)
        try await waitUntil { model.rules.count == 1 && workspace.draft.pendingBodies.isEmpty }
        XCTAssertEqual(try model.ruleStore.readTextAsset(model.rules[0].file), "latest")
        workspace.draft.rules[0].status = 999
        try await waitUntil { workspace.error != nil }
        XCTAssertEqual(model.rules[0].status, 200)
        XCTAssertNil(model.error, "Autosave validation must not block traffic with a modal alert")
        workspace.draft.rules[0].status = 201
        workspace.draft.setBody("repaired", for: rule.id)
        try await waitUntil { model.rules[0].status == 201 && workspace.draft.pendingBodies.isEmpty }
        let reopened = try model.ruleStore.load()
        XCTAssertEqual(reopened[0].status, 201)
        XCTAssertEqual(try model.ruleStore.readTextAsset(reopened[0].file), "repaired")
    }

    func testDeletingMultipleMapLocalRulesAutosavesAndPreservesBreakpoints() async throws {
        let model = try makeModel()
        let rules = (0..<3).map { _ in
            var rule = DebugRule()
            rule.bodySource = .text
            return rule
        }
        var pause = DebugRule()
        pause.kind = "breakpoint"
        model.rules = try model.ruleStore.prepareRules(rules + [pause], inlineBodies: Dictionary(uniqueKeysWithValues: rules.map { ($0.id, "body") }))
        let workspace = RuleWorkspace(model: model, kind: .mapLocal)
        workspace.load()
        workspace.draft.selectedID = nil
        workspace.draft.removeRules(withIDs: [rules[0].id, rules[2].id])
        try await waitUntil { model.rules.count == 2 }
        XCTAssertEqual(model.rules.map(\.id), [rules[1].id, pause.id])
        XCTAssertEqual(try model.ruleStore.load(), model.rules)
        XCTAssertEqual(try model.ruleStore.readTextAsset(model.rules[0].file), "body")
        workspace.draft.removeRules(withIDs: [rules[1].id])
        try await waitUntil { model.rules.count == 1 }
        XCTAssertEqual(model.rules, [pause])
        XCTAssertEqual(try model.ruleStore.load(), [pause])
    }

    func testBothEditorsWaitForBusyModelAndPreserveEachOthersRules() async throws {
        let model = try makeModel()
        let local = RuleWorkspace(model: model, kind: .mapLocal)
        let breakpoint = RuleWorkspace(model: model, kind: .breakpoint)
        local.load()
        breakpoint.load()
        model.busy = true
        var rule = DebugRule()
        rule.bodySource = .text
        local.draft.add(rule)
        local.draft.setBody("response", for: rule.id)
        var pause = DebugRule()
        pause.kind = "breakpoint"
        breakpoint.draft.add(pause)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(model.rules.isEmpty)
        local.draft.setBody("newest while waiting", for: rule.id)
        model.busy = false
        try await waitUntil { model.rules.count == 2 && local.draft.pendingBodies.isEmpty }
        XCTAssertEqual(Set(model.rules.map(\.id)), Set([rule.id, pause.id]))
        let savedLocal = try XCTUnwrap(model.rules.first { $0.id == rule.id })
        XCTAssertEqual(try model.ruleStore.readTextAsset(savedLocal.file), "newest while waiting")
        breakpoint.draft.rules[0].enabled = false
        local.draft.rules[0].host = "api.test"
        try await waitUntil {
            model.rules.first { $0.id == pause.id }?.enabled == false &&
            model.rules.first { $0.id == rule.id }?.host == "api.test"
        }
        XCTAssertEqual(try model.ruleStore.load(), model.rules)
    }

    func testAutosaveUpdatesRunningEngineWithoutRestart() async throws {
        let model = try makeModel()
        let ports = try SystemProxy.command("/usr/bin/python3", ["-c", """
        import socket
        a, b = socket.socket(), socket.socket()
        a.bind(('127.0.0.1', 0)); b.bind(('127.0.0.1', 0))
        print(a.getsockname()[1], b.getsockname()[1])
        """]).split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        try await model.engine.start(proxyPort: ports[0], apiPort: ports[1], lan: false)
        do {
            let workspace = RuleWorkspace(model: model, kind: .mapLocal)
            workspace.load()
            var rule = DebugRule()
            rule.host = "autosave.test"
            rule.path = "/response"
            rule.bodySource = .text
            workspace.draft.add(rule)
            workspace.draft.setBody("first response", for: rule.id)
            try await waitUntil { model.rules.count == 1 && workspace.draft.pendingBodies.isEmpty }
            func fetch() throws -> String {
                try SystemProxy.command("/usr/bin/curl", ["--noproxy", "", "--proxy", "http://127.0.0.1:\(ports[0])",
                    "--max-time", "5", "-sS", "http://autosave.test/response"])
            }
            XCTAssertEqual(try fetch(), "first response")
            workspace.draft.setBody("changed response", for: rule.id)
            try await waitUntil { workspace.draft.pendingBodies.isEmpty }
            XCTAssertEqual(try fetch(), "changed response")
            workspace.draft.rules[0].enabled = false
            try await waitUntil { model.rules.first?.enabled == false }
            await model.engine.stop()
        } catch {
            await model.engine.stop()
            throw error
        }
    }

    func testClosingEditorDoesNotDiscardPendingSave() async throws {
        let model = try makeModel()
        var workspace: RuleWorkspace? = RuleWorkspace(model: model, kind: .breakpoint)
        workspace?.load()
        var rule = DebugRule()
        rule.kind = "breakpoint"
        workspace?.draft.add(rule)
        workspace = nil
        try await waitUntil { model.rules.count == 1 }
        XCTAssertEqual(try model.ruleStore.load().first?.id, rule.id)
    }
}
