import XCTest
@testable import Reqnivo

final class RuleWorkspaceDraftTests: XCTestCase {
    private func withStore(_ check: (RuleStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try check(RuleStore(root: root))
    }

    private func inlineRule() -> DebugRule {
        var rule = DebugRule()
        rule.bodySource = .text
        return rule
    }

    func testBodiesSurviveSwitchingSelectionAndDuplicatesAreIndependent() {
        var draft = RuleWorkspaceDraft()
        let first = inlineRule()
        let second = inlineRule()
        draft.add(first)
        draft.setBody(#"{"value":1}"#, for: first.id)
        draft.add(second)
        draft.setBody("second response", for: second.id)
        draft.selectedID = first.id
        draft.duplicateSelected()
        let copyID = draft.selectedID!
        XCTAssertNotEqual(copyID, first.id)
        XCTAssertEqual(draft.textBodies[copyID], #"{"value":1}"#)
        draft.setBody("changed copy", for: copyID)
        XCTAssertEqual(draft.textBodies[first.id], #"{"value":1}"#)
        XCTAssertEqual(draft.textBodies[second.id], "second response")
        XCTAssertEqual(draft.rules.map(\.id), [first.id, copyID, second.id])
        draft.removeSelected()
        XCTAssertNil(draft.textBodies[copyID])
        XCTAssertEqual(draft.rules.map(\.id), [first.id, second.id])
    }

    func testRemoveMultipleRulesKeepsUnselectedOrderAndBodies() {
        var draft = RuleWorkspaceDraft()
        let rules = (0..<4).map { _ in inlineRule() }
        for (index, rule) in rules.enumerated() {
            draft.add(rule)
            draft.setBody("body \(index)", for: rule.id)
        }
        draft.selectedID = nil
        draft.removeRules(withIDs: [rules[0].id, rules[2].id])
        XCTAssertEqual(draft.rules.map(\.id), [rules[1].id, rules[3].id])
        XCTAssertEqual(draft.selectedID, rules[1].id)
        XCTAssertEqual(draft.textBodies, [rules[1].id: "body 1", rules[3].id: "body 3"])
        XCTAssertEqual(draft.pendingBodies, draft.textBodies)
        draft.removeRules(withIDs: [])
        XCTAssertEqual(draft.rules.count, 2)
        draft.removeRules(withIDs: Set(draft.rules.map(\.id)))
        XCTAssertTrue(draft.rules.isEmpty)
        XCTAssertTrue(draft.textBodies.isEmpty)
        XCTAssertTrue(draft.pendingBodies.isEmpty)
        XCTAssertNil(draft.selectedID)
    }

    func testSearchDoesNotChangePriorityOrDiscardBodies() {
        var draft = RuleWorkspaceDraft()
        var rule = inlineRule()
        rule.host = "api.test"
        rule.path = "/items"
        draft.add(rule)
        draft.setBody("unsaved", for: rule.id)
        XCTAssertEqual(draft.filtered("API.TEST").map(\.id), [rule.id])
        XCTAssertEqual(draft.filtered("/items").map(\.id), [rule.id])
        XCTAssertTrue(draft.filtered("missing").isEmpty)
        XCTAssertEqual(draft.rules.first?.id, rule.id)
        XCTAssertEqual(draft.pendingBodies[rule.id], "unsaved")
    }

    func testInlineBodyRoundTripsWithoutEmbeddingBodyInControlPayload() throws {
        try withStore { store in
            let rule = inlineRule()
            let text = #"{"message":"สวัสดี","id":123456789012345678901}"#
            let prepared = try store.prepareRules([rule], inlineBodies: [rule.id: text])
            try store.save(prepared)
            let saved = try store.load()
            XCTAssertEqual(saved[0].bodySource, .text)
            XCTAssertEqual(try store.readTextAsset(saved[0].file), text)
            let payload = try JSONEncoder().encode(saved)
            XCTAssertLessThan(payload.count, 2048)
            XCTAssertFalse(String(decoding: payload, as: UTF8.self).contains("สวัสดี"))
            var reopened = RuleWorkspaceDraft(rules: saved)
            try reopened.loadBody(for: rule.id, store: store)
            XCTAssertEqual(reopened.textBodies[rule.id], MessagePreview.prettyJSON(text))
            XCTAssertEqual(reopened.pendingBodies[rule.id], MessagePreview.prettyJSON(text))
        }
    }

    func testEmptyExactLimitAndOversizedUTF8Bodies() throws {
        try withStore { store in
            let empty = inlineRule()
            let maximum = inlineRule()
            let limitBody = String(repeating: "a", count: RuleStore.maximumMockBytes)
            let prepared = try store.prepareRules([empty, maximum], inlineBodies: [empty.id: "", maximum.id: limitBody])
            XCTAssertEqual(try store.readTextAsset(prepared[0].file), "")
            XCTAssertEqual(try Data(contentsOf: store.assets.appendingPathComponent(prepared[1].file)).count,
                           RuleStore.maximumMockBytes)
            XCTAssertLessThan(try JSONEncoder().encode(prepared).count, 4096)
            let before = try FileManager.default.contentsOfDirectory(atPath: store.assets.path).sorted()
            for tooLarge in [limitBody + "x", limitBody + "ก"] {
                XCTAssertThrowsError(try store.prepareRules([maximum], inlineBodies: [maximum.id: tooLarge]))
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.assets.path).sorted(), before)
        }
    }

    func testFailedValidationRollsBackOnlyNewAssets() throws {
        try withStore { store in
            var rule = inlineRule()
            let saved = try store.prepareRules([rule], inlineBodies: [rule.id: "original"])
            let originalFile = saved[0].file
            rule.status = 999
            XCTAssertThrowsError(try store.prepareRules([rule], inlineBodies: [rule.id: "invalid draft"]))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.assets.path), [originalFile])
            XCTAssertEqual(try store.readTextAsset(originalFile), "original")
        }
    }

    func testTooManyRulesAreRejectedBeforeWritingAnyBodies() throws {
        try withStore { store in
            let rules = (0..<201).map { _ in inlineRule() }
            let bodies = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, "draft") })
            XCTAssertThrowsError(try store.prepareRules(rules, inlineBodies: bodies))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.assets.path))
        }
    }

    func testEditingAnAppliedDuplicateDoesNotOverwriteOriginalFile() throws {
        try withStore { store in
            let original = inlineRule()
            let applied = try store.prepareRules([original], inlineBodies: [original.id: "original"])
            var draft = RuleWorkspaceDraft(rules: applied, selectedID: original.id)
            try draft.loadBody(for: original.id, store: store)
            draft.duplicateSelected()
            let copyID = draft.selectedID!
            draft.setBody("copy changed", for: copyID)
            let result = try store.prepareRules(draft.rules, inlineBodies: draft.pendingBodies)
            XCTAssertEqual(try store.readTextAsset(result[0].file), "original")
            XCTAssertEqual(try store.readTextAsset(result[1].file), "copy changed")
            XCTAssertNotEqual(result[0].file, result[1].file)
            draft.acceptSaved(result)
            XCTAssertTrue(draft.pendingBodies.isEmpty)
            XCTAssertEqual(draft.textBodies[copyID], "copy changed")
        }
    }

    func testLegacyFileAndBinaryContentRemainSupported() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
            let source = store.root.appendingPathComponent("binary.bin")
            try Data([0xFF, 0x00, 0xFE]).write(to: source)
            var rule = DebugRule()
            rule.file = try store.importFile(source)
            var draft = RuleWorkspaceDraft(rules: [rule])
            XCTAssertThrowsError(try draft.setSource(.text, for: rule.id, store: store))
            XCTAssertNil(draft.rules[0].bodySource)
            XCTAssertNil(draft.textBodies[rule.id])
            let prepared = try store.prepareRules(draft.rules, inlineBodies: [:])
            XCTAssertEqual(prepared, [rule])
            XCTAssertEqual(try Data(contentsOf: store.assets.appendingPathComponent(rule.file)), Data([0xFF, 0x00, 0xFE]))
        }
    }

    func testSwitchingModesKeepsDraftUntilApplyThenReloadsTheAppliedSource() throws {
        try withStore { store in
            let original = inlineRule()
            let applied = try store.prepareRules([original], inlineBodies: [original.id: "saved body"])
            var draft = RuleWorkspaceDraft(rules: applied, selectedID: original.id)
            try draft.loadBody(for: original.id, store: store)
            draft.setBody("unsaved text", for: original.id)
            try draft.setSource(.file, for: original.id, store: store)
            try draft.setSource(.text, for: original.id, store: store)
            XCTAssertEqual(draft.textBodies[original.id], "unsaved text")
            try draft.setSource(.file, for: original.id, store: store)
            let prepared = try store.prepareRules(draft.rules, inlineBodies: draft.pendingBodies)
            draft.acceptSaved(prepared)
            try draft.setSource(.text, for: original.id, store: store)
            XCTAssertEqual(draft.textBodies[original.id], "saved body")
            XCTAssertTrue(draft.pendingBodies.isEmpty)
        }
    }
}
