import Foundation

struct SavedTrafficFilter: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var query: String
    var scope: SidebarFilter

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure("Enter a saved filter name")
        }
        _ = try TrafficQuery.parse(query)
    }
}

struct SavedTrafficFilterStore {
    let root: URL
    var file: URL { root.appendingPathComponent("traffic-filters.json") }

    private struct Document: Codable {
        var version = 1
        let filters: [SavedTrafficFilter]
    }

    func load() throws -> [SavedTrafficFilter] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        guard document.version == 1 else { throw AppFailure("Unsupported saved filter version \(document.version)") }
        try validate(document.filters)
        return document.filters
    }

    func save(_ filters: [SavedTrafficFilter]) throws {
        try validate(filters)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(Document(filters: filters)).write(to: file, options: .atomic)
    }

    private func validate(_ filters: [SavedTrafficFilter]) throws {
        guard Set(filters.map(\.id)).count == filters.count else { throw AppFailure("Duplicate saved filter IDs") }
        for filter in filters { try filter.validate() }
    }
}
