import Security
import XCTest
@testable import Reqnivo

final class MacCATrustTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMissingAndInvalidCAAreNotReportedAsTrusted() throws {
        let file = try directory().appendingPathComponent("ca.pem")
        XCTAssertEqual(MacCATrust.check(file), .notGenerated)
        try "invalid certificate".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(MacCATrust.check(file), .unavailable)
    }

    func testSSLTrustEvaluationUsesExistingTrustAndDetectsTrustedAnchor() throws {
        let root = try directory()
        let file = root.appendingPathComponent("ca.pem")
        let config = root.appendingPathComponent("openssl.cnf")
        try """
        [req]
        distinguished_name = dn
        x509_extensions = ca
        prompt = no
        [dn]
        CN = Reqnivo temporary trust test
        [ca]
        basicConstraints = critical, CA:true
        keyUsage = critical, keyCertSign, cRLSign
        extendedKeyUsage = serverAuth
        """.write(to: config, atomically: true, encoding: .utf8)
        _ = try SystemProxy.command("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-config", config.path, "-keyout", root.appendingPathComponent("key.pem").path, "-out", file.path])
        XCTAssertEqual(MacCATrust.check(file), .notTrusted, "A generated CA must not be implicitly trusted")
        let result = MacCATrust.check(file) { trust in
            // Emulate a trusted store for this evaluation only; do not modify Keychain.
            _ = SecTrustEvaluateWithError(trust, nil)
            guard let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
                XCTFail("Missing test CA in evaluation chain")
                return false
            }
            XCTAssertEqual(SecTrustSetAnchorCertificates(trust, [certificate] as CFArray), errSecSuccess)
            var error: CFError?
            let trusted = SecTrustEvaluateWithError(trust, &error)
            XCTAssertTrue(trusted, "\(String(describing: error))")
            return trusted
        }
        XCTAssertEqual(result, .trusted)
        XCTAssertEqual(MacCATrust.check(file), .notTrusted, "The test must not change system trust")
    }

    @MainActor
    func testModelRefreshUpdatesTrustAndDetectsWithdrawalWithoutRestart() async throws {
        let state = try directory().appendingPathComponent("status")
        let model = CaptureModel(caTrustCheck: { _ in
            (try? String(contentsOf: state)) == "trusted" ? .trusted : .notTrusted
        })
        func waitForStatus(_ expected: MacCATrustStatus) async throws {
            for _ in 0..<40 {
                if model.caTrustStatus == expected { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(model.caTrustStatus, expected)
        }
        try await waitForStatus(.notTrusted)
        XCTAssertEqual(model.caStatusText, "CA certificate ready · HTTPS not trusted on this Mac")
        try "trusted".write(to: state, atomically: true, encoding: .utf8)
        try await waitForStatus(.trusted)
        XCTAssertEqual(model.caStatusText, "CA certificate ready · HTTPS trusted on this Mac")
        try "not trusted".write(to: state, atomically: true, encoding: .utf8)
        try await waitForStatus(.notTrusted)
        XCTAssertEqual(model.caTrustStatus, .notTrusted)
        XCTAssertFalse(model.running)
    }
}
