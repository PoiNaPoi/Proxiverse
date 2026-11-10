import XCTest
@testable import Proxiverse

final class MapLocalTransferTests: XCTestCase {
    func testPortableRoundTripKeepsDraftTextBinaryMetadataAndOrder() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(root: root)
        try FileManager.default.createDirectory(at: store.assets, withIntermediateDirectories: true)
        let binary = Data([0, 255, 13, 10, 1])
        try binary.write(to: store.assets.appendingPathComponent("binary.mock"))
        var text = DebugRule()
        text.bodySource = .text
        text.status = 503
        text.delayMilliseconds = 123
        text.enabled = false
        text.headers = "Content-Type: application/json\nSet-Cookie: a=1\nSet-Cookie: b=2"
        var file = DebugRule()
        file.file = "binary.mock"
        file.bodySource = .file
        var draft = RuleWorkspaceDraft()
        draft.add(text)
        draft.setBody("{\"draft\":true}", for: text.id)
        draft.add(file)
        let data = try MapLocalTransfer.export(draft, store: store)
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(archive["format"] as? String, "Proxiverse.MapLocal")
        let entries = try MapLocalTransfer.decode(data)
        XCTAssertEqual(entries.map(\.body), [Data("{\"draft\":true}".utf8), binary])
        XCTAssertTrue(entries.allSatisfy { $0.rule.file.isEmpty })
        let destination = RuleStore(root: root.appendingPathComponent("other-machine"))
        let imported = try MapLocalTransfer.append(entries, to: RuleWorkspaceDraft(), store: destination, otherRuleCount: 1)
        XCTAssertEqual(imported.rules.map(\.status), [503, 200])
        XCTAssertFalse(imported.rules[0].enabled)
        XCTAssertEqual(imported.rules[0].headers, text.headers)
        XCTAssertEqual(imported.rules[0].delayMilliseconds, 123)
        XCTAssertNotEqual(imported.rules[0].id, text.id)
        XCTAssertEqual(try Data(contentsOf: destination.assets.appendingPathComponent(imported.rules[1].file)), binary)
        XCTAssertNoThrow(try destination.validate(imported.rules))
    }

    func testExportSelectedRulesPreservesOrderAndPendingBodies() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(root: root)
        var draft = RuleWorkspaceDraft()
        for name in ["First", "Unselected", "Third"] {
            var rule = DebugRule()
            rule.name = name
            rule.bodySource = .text
            draft.add(rule)
            draft.setBody("body of " + name, for: rule.id)
        }
        let selected: Set<String> = [draft.rules[2].id, draft.rules[0].id]
        let entries = try MapLocalTransfer.decode(MapLocalTransfer.export(draft, store: store, selectedIDs: selected))
        XCTAssertEqual(entries.map(\.rule.name), ["First", "Third"])
        XCTAssertEqual(entries.map(\.body), [Data("body of First".utf8), Data("body of Third".utf8)])
        XCTAssertEqual(try MapLocalTransfer.decode(MapLocalTransfer.export(draft, store: store)).count, 3)
        XCTAssertThrowsError(try MapLocalTransfer.export(draft, store: store, selectedIDs: []))
    }

    func testConfigBackupAndSingleToolTreePreserveFolderStateHTTPResponseAndMethods() throws {
        let node = mapLocalNode(response: Data("HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\nContent-Length: 2\r\n\r\n{}".utf8))
        let tree: [[String: Any]] = [["nodeType": ["folder": ["_0": ["isEnabled": false, "entries": [node]]]]]]
        let treeData = try JSONSerialization.data(withJSONObject: tree)
        let backup = try JSONSerialization.data(withJSONObject: ["mapLocalData": ["data": treeData.base64EncodedString(), "isEnabled": true]])
        for data in [treeData, backup] {
            let entries = try MapLocalTransfer.decode(data)
            XCTAssertEqual(entries.count, 2)
            XCTAssertEqual(entries.map(\.rule.method), ["GET", "POST"])
            XCTAssertTrue(entries.allSatisfy { !$0.rule.enabled })
            XCTAssertEqual(entries[0].rule.urlPattern, "https://api.example.test:8443/items?x=1")
            XCTAssertEqual(entries[0].rule.includeSubpaths, true)
            XCTAssertEqual(entries[0].rule.status, 201)
            XCTAssertEqual(entries[0].rule.headers, "Content-Type: application/json\nSet-Cookie: a=1\nSet-Cookie: b=2")
            XCTAssertEqual(entries[0].body, Data("{}".utf8))
        }
    }

    func testRawBinaryAndLFResponseAndAnyMethod() throws {
        for bytes in [Data([0, 255, 0]), Data("HTTP/1.1 404 Not Found\nContent-Type: text/plain\n\nmissing\n".utf8)] {
            var source = mapLocalSource(response: bytes)
            source["method"] = ["any": [:]]
            let entries = try MapLocalTransfer.decode(JSONSerialization.data(withJSONObject: [["nodeType": ["node": ["_0": source]]]]))
            XCTAssertEqual(entries[0].rule.method, "*")
            XCTAssertEqual(entries[0].body, bytes.first == 0 ? bytes : Data("missing\n".utf8))
        }
    }

    func testRejectsUnsupportedRulesAndMissingEmbeddedFile() throws {
        for change: [String: Any] in [["regex": "useRegex"], ["isDirectoryFileEnable": true],
                                     ["graphQLQueryName": "GetUser"], ["localFile": ["path": "/private/secret"]]] {
            var source = mapLocalSource(response: Data("{}".utf8))
            source.merge(change) { _, value in value }
            let data = try JSONSerialization.data(withJSONObject: [["nodeType": ["node": ["_0": source]]]])
            XCTAssertThrowsError(try MapLocalTransfer.decode(data))
        }
        let external = mapLocalNode(response: Data("HTTP/1.1 200 OK\n\n<FILE_URL=\"/private/secret\">".utf8))
        XCTAssertThrowsError(try MapLocalTransfer.decode(JSONSerialization.data(withJSONObject: [external])))
    }

    func testFailedBatchLeavesDraftAndAssetsUntouchedAndHonorsTotalRuleLimit() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(root: root)
        var draft = RuleWorkspaceDraft()
        draft.add(DebugRule())
        var invalid = DebugRule()
        invalid.status = 999
        let entries = [MapLocalTransfer.Entry(rule: DebugRule(), body: Data()), .init(rule: invalid, body: Data())]
        XCTAssertThrowsError(try MapLocalTransfer.append(entries, to: draft, store: store, otherRuleCount: 0))
        XCTAssertEqual(draft.rules.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.assets.path), [])
        XCTAssertThrowsError(try MapLocalTransfer.append(entries, to: draft, store: store, otherRuleCount: 198))
    }

    func testActualMapLocalExportWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["PROXIVERSE_TEST_MAP_LOCAL_EXPORT"] else {
            throw XCTSkip("Optional local compatibility check")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let backup = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let map = try XCTUnwrap(backup["mapLocalData"] as? [String: Any])
        let encoded = try XCTUnwrap(map["data"] as? String)
        let treeData = try XCTUnwrap(Data(base64Encoded: encoded))
        let tree = try XCTUnwrap(JSONSerialization.jsonObject(with: treeData) as? [[String: Any]])
        // External FILE_URL content is intentionally rejected rather than reading arbitrary local paths.
        func embeddedNodes(_ nodes: [[String: Any]]) -> [[String: Any]] {
            nodes.compactMap { node in
                let type = node["nodeType"] as? [String: Any] ?? [:]
                if var folder = (type["folder"] as? [String: Any])?["_0"] as? [String: Any] {
                    folder["entries"] = embeddedNodes(folder["entries"] as? [[String: Any]] ?? [])
                    return ["nodeType": ["folder": ["_0": folder]]]
                }
                guard let source = (type["node"] as? [String: Any])?["_0"] as? [String: Any],
                      let local = source["localFile"] as? [String: Any],
                      let encoded = local["importFileData"] as? String,
                      let body = Data(base64Encoded: encoded),
                      body.range(of: Data("<FILE_URL=".utf8)) == nil else { return nil }
                return node
            }
        }
        let supportedTree = try JSONSerialization.data(withJSONObject: embeddedNodes(tree))
        let supportedBackup = try JSONSerialization.data(withJSONObject: ["mapLocalData": ["data": supportedTree.base64EncodedString()]])
        let entries = try MapLocalTransfer.decode(supportedBackup)
        print("Verified \(entries.count) embedded rules from provided Map Local export")
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(root: root)
        let draft = try MapLocalTransfer.append(entries, to: RuleWorkspaceDraft(), store: store, otherRuleCount: 0)
        XCTAssertFalse(draft.rules.isEmpty)
        XCTAssertNoThrow(try store.validate(draft.rules))
        XCTAssertEqual(try MapLocalTransfer.decode(MapLocalTransfer.export(draft, store: store)).map(\.body), entries.map(\.body))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func mapLocalNode(response: Data) -> [String: Any] {
        ["nodeType": ["node": ["_0": mapLocalSource(response: response)]]]
    }

    private func mapLocalSource(response: Data) -> [String: Any] {
        ["name": "Fixture", "url": "https://api.example.test:8443/items?x=1", "regex": "useWildcard",
         "isEnabled": true, "isLocalFileEnable": true, "isDirectoryFileEnable": false, "isIncludingPaths": true,
         "method": ["exact": [["name": "GET"], ["name": "POST"]]],
         "localFile": ["importFileData": response.base64EncodedString(), "path": "/unused/response.json"]]
    }
}
