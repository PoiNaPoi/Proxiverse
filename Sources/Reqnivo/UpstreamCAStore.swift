import Foundation
import Security

struct UpstreamCAStore {
    let root: URL
    var file: URL { root.appendingPathComponent("upstream-ca.pem") }
    var isConfigured: Bool { FileManager.default.fileExists(atPath: file.path) }

    func install(from source: URL) throws {
        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8),
              !text.contains("PRIVATE KEY") else {
            throw AppFailure("Choose a PEM CA certificate bundle without private keys.")
        }
        let pattern = "-----BEGIN CERTIFICATE-----([\\s\\S]*?)-----END CERTIFICATE-----"
        let expression = try NSRegularExpression(pattern: pattern)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { throw AppFailure("No PEM certificates found in this file.") }
        for match in matches {
            let encoded = (text as NSString).substring(with: match.range(at: 1))
                .components(separatedBy: .whitespacesAndNewlines).joined()
            guard let der = Data(base64Encoded: encoded),
                  SecCertificateCreateWithData(nil, der as CFData) != nil else {
                throw AppFailure("The CA bundle contains an invalid certificate.")
            }
        }
        let remainder = expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        guard remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure("Choose a PEM file containing only CA certificates.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove() throws {
        if isConfigured { try FileManager.default.removeItem(at: file) }
    }
}
