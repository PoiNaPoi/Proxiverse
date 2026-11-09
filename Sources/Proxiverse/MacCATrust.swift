import Foundation
import Security

enum MacCATrustStatus: Equatable, Sendable {
    case checking, notGenerated, trusted, notTrusted, unavailable

    var text: String {
        switch self {
        case .checking: return "Checking HTTPS CA trust on this Mac…"
        case .notGenerated: return "CA not generated · start capture first"
        case .trusted: return "CA certificate ready · HTTPS trusted on this Mac"
        case .notTrusted: return "CA certificate ready · HTTPS not trusted on this Mac"
        case .unavailable: return "Could not check HTTPS CA trust on this Mac"
        }
    }
}

enum MacCATrust {
    static func check(_ certificateURL: URL) -> MacCATrustStatus {
        check(certificateURL, evaluate: { SecTrustEvaluateWithError($0, nil) })
    }

    static func check(_ certificateURL: URL, evaluate: (SecTrust) -> Bool) -> MacCATrustStatus {
        guard FileManager.default.fileExists(atPath: certificateURL.path) else { return .notGenerated }
        guard let pem = try? String(contentsOf: certificateURL, encoding: .utf8),
              let start = pem.range(of: "-----BEGIN CERTIFICATE-----"),
              let end = pem.range(of: "-----END CERTIFICATE-----", range: start.upperBound..<pem.endIndex),
              let der = Data(base64Encoded: String(pem[start.upperBound..<end.lowerBound]), options: .ignoreUnknownCharacters),
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return .unavailable }
        var trust: SecTrust?
        // Use the Mac's existing trust settings for SSL; never make this CA an anchor ourselves.
        guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, nil), &trust) == errSecSuccess,
              let trust,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return .unavailable }
        return evaluate(trust) ? .trusted : .notTrusted
    }
}
