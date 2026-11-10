import Combine
import Foundation

@MainActor
final class RuleWorkspace: ObservableObject {
    @Published var draft = RuleWorkspaceDraft() {
        didSet {
            guard !acceptingSaved, loaded,
                  draft.rules != oldValue.rules || draft.pendingBodies != oldValue.pendingBodies else { return }
            scheduleSave()
        }
    }
    @Published var error: String?
    @Published private(set) var notice = "Changes save and apply automatically."
    private let model: CaptureModel
    private let kind: DebugRuleKind
    private var loaded = false
    private var acceptingSaved = false
    private var revision = 0
    private var saveTask: Task<Void, Never>?

    init(model: CaptureModel, kind: DebugRuleKind) {
        self.model = model
        self.kind = kind
    }

    func load() {
        guard !loaded else { return }
        draft.rules = kind.rules(in: model.rules)
        draft.selectedID = draft.rules.first?.id
        loaded = true
    }

    func loadBody(for id: String) throws {
        guard draft.textBodies[id] == nil,
              draft.rules.contains(where: { $0.id == id && $0.bodySource == .text }) else { return }
        acceptingSaved = true
        defer { acceptingSaved = false }
        try draft.loadBody(for: id, store: model.ruleStore)
    }

    private func scheduleSave() {
        revision += 1
        guard saveTask == nil else { return }
        // Keep the task alive after the window closes so the last edit is saved.
        saveTask = Task {
            defer { saveTask = nil }
            while true {
                error = nil
                notice = "Saving…"
                let waitingRevision = revision
                try? await Task.sleep(for: .milliseconds(500))
                guard waitingRevision == revision else { continue }
                while model.ruleOperation || model.busy {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                let savingRevision = revision
                let snapshot = draft
                do {
                    // Merge only after the other editor has finished its save.
                    let merged = try kind.replacingRules(in: model.rules, with: snapshot.rules)
                    let saved = await model.saveRules(merged, inlineBodies: snapshot.pendingBodies, reportError: false)
                    guard savingRevision == revision else { continue }
                    if saved {
                        acceptingSaved = true
                        draft.acceptSaved(kind.rules(in: model.rules))
                        acceptingSaved = false
                        error = nil
                        notice = "Saved · active for new matching traffic."
                    } else {
                        error = model.ruleSaveError ?? "Could not save rules. The last saved rules remain active."
                    }
                } catch {
                    guard savingRevision == revision else { continue }
                    self.error = error.localizedDescription
                }
                return
            }
        }
    }
}
