import Foundation
import Darwin

enum HTTPSDecryption {
    static func normalizedHost(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        var address = in6_addr()
        if inet_pton(AF_INET6, host, &address) == 1 { return host }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !host.isEmpty, host.utf8.count <= 253,
              labels.allSatisfy({ $0.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", options: .regularExpression) != nil }) else {
            throw AppFailure("Enter an exact hostname or IP address, without a scheme, port, path, or wildcard.")
        }
        return host
    }
}
