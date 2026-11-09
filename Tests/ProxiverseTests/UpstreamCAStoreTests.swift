import XCTest
@testable import Proxiverse

final class UpstreamCAStoreTests: XCTestCase {
    func testImportPersistsCopyRejectsBadReplacementAndRemoves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pem")
        _ = try SystemProxy.command("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=Test CA", "-keyout", root.appendingPathComponent("key.pem").path, "-out", source.path])
        let store = UpstreamCAStore(root: root.appendingPathComponent("managed"))
        let original = try Data(contentsOf: source)
        try store.install(from: source)
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(UpstreamCAStore(root: store.root).isConfigured)
        XCTAssertEqual(try Data(contentsOf: store.file), original)
        for bad in ["", "not a certificate", "-----BEGIN CERTIFICATE-----\nZm9v\n-----END CERTIFICATE-----",
                    String(decoding: original, as: UTF8.self) + "\n-----BEGIN PRIVATE KEY-----\nsecret"] {
            try Data(bad.utf8).write(to: source)
            XCTAssertThrowsError(try store.install(from: source))
            XCTAssertEqual(try Data(contentsOf: store.file), original)
        }
        try (original + original).write(to: source)
        try store.install(from: source)
        XCTAssertEqual(try Data(contentsOf: store.file), original + original)
        try store.remove()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNoThrow(try store.remove())
    }
}
