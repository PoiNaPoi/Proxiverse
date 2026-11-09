import XCTest
@testable import Proxiverse

final class SavedTrafficFilterTests: XCTestCase {
    func testRoundTripAndValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedTrafficFilterStore(root: root)
        XCTAssertEqual(try store.load(), [])
        let entries = [SavedTrafficFilter(name: "Errors", query: "status:400-599 -type:image",
                                          scope: .domainPath(host: "api.test", pathPrefix: "/v1"))]
        try store.save(entries)
        XCTAssertEqual(try store.load(), entries)
        XCTAssertThrowsError(try store.save([SavedTrafficFilter(name: " ", query: "", scope: .all)]))
        XCTAssertThrowsError(try store.save([SavedTrafficFilter(name: "Bad", query: "status:999", scope: .all)]))
        XCTAssertEqual(try store.load(), entries)
        XCTAssertThrowsError(try store.save(entries + entries))
        try Data(#"{"version":2,"filters":[]}"#.utf8).write(to: store.file)
        XCTAssertThrowsError(try store.load())
        try Data("broken".utf8).write(to: store.file)
        XCTAssertThrowsError(try store.load())
    }

    @MainActor
    func testModelCRUDAndFailedWriteDoNotPublishSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedTrafficFilterStore(root: root)
        let model = CaptureModel(savedFilterStore: store)
        model.search = "method:POST"
        model.sidebarSelection = .client("127.0.0.1")
        XCTAssertTrue(model.saveFilter(name: "Posts"))
        let saved = try XCTUnwrap(model.savedFilters.first)
        let reopened = CaptureModel(savedFilterStore: store)
        XCTAssertEqual(reopened.savedFilters, [saved])
        XCTAssertTrue(reopened.pinnedIDs.isEmpty)
        XCTAssertTrue(reopened.selectedIDs.isEmpty)
        model.search = "GET"
        model.applySavedFilter(saved)
        XCTAssertEqual(model.search, "method:POST")
        XCTAssertEqual(model.sidebarSelection, .client("127.0.0.1"))
        XCTAssertFalse(model.savedFilterModified)
        model.renameFilter(saved, name: "Renamed")
        XCTAssertEqual(try store.load().first?.name, "Renamed")
        model.search = "status:201"
        XCTAssertTrue(model.saveFilter(name: "Updated", replacingID: saved.id))
        XCTAssertEqual(model.savedFilters.count, 1)
        model.deleteFilter(saved)
        XCTAssertTrue(model.savedFilters.isEmpty)
        try FileManager.default.removeItem(at: root)
        try Data("not a directory".utf8).write(to: root)
        XCTAssertFalse(model.saveFilter(name: "Cannot write"))
        XCTAssertTrue(model.savedFilters.isEmpty)
        XCTAssertNotNil(model.error)
    }

    @MainActor
    func testCorruptStoreIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SavedTrafficFilterStore(root: root)
        try Data("broken".utf8).write(to: store.file)
        let model = CaptureModel(savedFilterStore: store)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.saveFilter(name: "New"))
        XCTAssertEqual(try String(contentsOf: store.file), "broken")
    }
}
