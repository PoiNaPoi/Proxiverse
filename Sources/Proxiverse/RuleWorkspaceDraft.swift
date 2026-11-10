import Foundation

struct RuleWorkspaceDraft {
    var rules: [DebugRule] = []
    var selectedID: String?
    private(set) var textBodies: [String: String] = [:]
    private var dirtyBodyIDs: Set<String> = []
    private(set) var fileNames: [String: String] = [:]

    init(rules: [DebugRule] = [], selectedID: String? = nil) {
        self.rules = rules
        self.selectedID = selectedID
    }

    var pendingBodies: [String: String] {
        textBodies.filter { dirtyBodyIDs.contains($0.key) }
    }

    func filtered(_ search: String) -> [DebugRule] {
        guard !search.isEmpty else { return rules }
        return rules.filter {
            "\($0.name) \($0.method) \($0.host) \($0.path) \($0.urlPattern ?? "") \($0.status)"
                .localizedCaseInsensitiveContains(search)
        }
    }

    mutating func add(_ rule: DebugRule) {
        rules.append(rule)
        selectedID = rule.id
        if rule.bodySource == .text && rule.file.isEmpty { setBody("", for: rule.id) }
    }

    mutating func setBody(_ body: String, for id: String) {
        textBodies[id] = body
        dirtyBodyIDs.insert(id)
    }

    mutating func loadBody(for id: String, store: RuleStore) throws {
        guard let rule = rules.first(where: { $0.id == id }), rule.bodySource == .text,
              textBodies[id] == nil else { return }
        try loadTextBody(rule.file, for: id, store: store)
    }

    mutating func setSource(_ source: MockBodySource, for id: String, store: RuleStore) throws {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { throw AppFailure("Rule no longer exists") }
        if source == .text, textBodies[id] == nil {
            if rules[index].file.isEmpty { setBody("", for: id) }
            else { try loadTextBody(rules[index].file, for: id, store: store) }
        }
        rules[index].bodySource = source
    }

    private mutating func loadTextBody(_ name: String, for id: String, store: RuleStore) throws {
        let original = try store.readTextAsset(name)
        let body = MessagePreview.prettyJSON(original, maximumBytes: RuleStore.maximumMockBytes) ?? original
        textBodies[id] = body
        if body != original { dirtyBodyIDs.insert(id) }
    }

    mutating func chooseFile(_ url: URL, for id: String, store: RuleStore) throws {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { throw AppFailure("Rule no longer exists") }
        let name = try store.importFile(url)
        rules[index].file = name
        rules[index].bodySource = .file
        fileNames[id] = url.lastPathComponent
        textBodies.removeValue(forKey: id)
        dirtyBodyIDs.remove(id)
    }

    mutating func duplicateSelected() {
        guard let index = rules.firstIndex(where: { $0.id == selectedID }) else { return }
        let original = rules[index]
        var copy = original
        copy.id = UUID().uuidString
        copy.name += " Copy"
        rules.insert(copy, at: index + 1)
        if let body = textBodies[original.id] {
            textBodies[copy.id] = body
            if dirtyBodyIDs.contains(original.id) { dirtyBodyIDs.insert(copy.id) }
        }
        fileNames[copy.id] = fileNames[original.id]
        selectedID = copy.id
    }

    mutating func removeSelected() {
        guard let selectedID else { return }
        removeRules(withIDs: [selectedID])
    }

    mutating func removeRules(withIDs ids: Set<String>) {
        guard let index = rules.firstIndex(where: { ids.contains($0.id) }) else { return }
        rules.removeAll { ids.contains($0.id) }
        textBodies = textBodies.filter { !ids.contains($0.key) }
        dirtyBodyIDs.subtract(ids)
        fileNames = fileNames.filter { !ids.contains($0.key) }
        if selectedID.map({ ids.contains($0) }) ?? true {
            selectedID = rules.isEmpty ? nil : rules[min(index, rules.count - 1)].id
        }
    }

    mutating func acceptSaved(_ saved: [DebugRule]) {
        rules = saved
        let textIDs = Set(saved.filter { $0.bodySource == .text }.map(\.id))
        textBodies = textBodies.filter { textIDs.contains($0.key) }
        dirtyBodyIDs.removeAll()
    }
}
