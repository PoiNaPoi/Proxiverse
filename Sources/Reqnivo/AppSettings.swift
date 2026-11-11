import Foundation

struct LANDevice: Codable, Identifiable, Equatable {
    let ip: String
    let approved: Bool
    var id: String { ip }
}

struct AppSettings: Codable, Equatable {
    var proxyPort = 9090
    var apiPort = 9091
    var allowLAN = false
    var setMacProxy = false
    var service = ""
    var skipUpstreamVerification = false
    var pinnedHosts: Set<String> = []
    var inspectorOnRight = false
    var messagesStacked = false
    // Missing in settings saved before selective HTTPS decryption: start with no enabled hosts.
    var httpsDecryptionHosts: [String: Bool]? = nil
}

struct AppSettingsStore {
    let root: URL
    var file: URL { root.appendingPathComponent("settings.json") }

    func load() throws -> AppSettings? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: file))
    }

    func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(settings).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
