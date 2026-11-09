import Foundation

struct BreakpointHeader: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var value: String
}

struct BreakpointDraft {
    static let maximumBodyBytes = 256 * 1024
    var edit: PausedEdit
    var headers: [BreakpointHeader]
    var statusText: String

    init(_ edit: PausedEdit) {
        self.edit = edit
        statusText = String(edit.status)
        headers = edit.headers.components(separatedBy: "\n").filter { !$0.isEmpty }.map { line in
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            return BreakpointHeader(name: String(parts[0]), value: parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "")
        }
        if let body = edit.body, let formatted = MessagePreview.prettyJSON(body, maximumBytes: Self.maximumBodyBytes) {
            self.edit.body = formatted
        }
    }

    var payload: PausedEdit {
        var result = edit
        if edit.phase == "response", let status = Int(statusText) { result.status = status }
        result.headers = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        return result
    }

    var validationError: String? {
        if edit.phase == "request" {
            guard let url = URLComponents(string: edit.url), ["http", "https"].contains(url.scheme),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                return "Use an absolute HTTP or HTTPS URL without credentials."
            }
            if edit.method.range(of: "^[A-Z]+\\z", options: .regularExpression) == nil { return "Use an uppercase HTTP method." }
        } else {
            guard let status = Int(statusText), (200...599).contains(status) else {
                return "Response status must be 200–599."
            }
        }
        for header in headers {
            if header.name.range(of: "^[!#$%&'*+.^_`|~0-9A-Za-z-]+\\z", options: .regularExpression) == nil ||
                header.value.unicodeScalars.contains(where: { $0.value == 13 || $0.value == 10 || $0.value == 0 }) {
                return "Each header needs a valid name and a value without line breaks."
            }
        }
        if let body = edit.body, body.utf8.count > Self.maximumBodyBytes { return "Edited body exceeds 256 KiB." }
        return nil
    }
}

extension TrafficFlow {
    var breakpointKey: String { id + ":" + state }
}

extension CaptureModel {
    func updatePausedTraffic(_ waiting: [TrafficFlow]) {
        let live = waiting.filter { !completedBreakpoints.contains($0.breakpointKey) }
        let keys = Set(live.map(\.breakpointKey))
        let additions = live.filter { !seenBreakpoints.contains($0.breakpointKey) }
        seenBreakpoints = keys
        // Preserve arrival order even when the engine returns a differently ordered snapshot.
        paused = paused.filter { keys.contains($0.breakpointKey) } + live.filter { flow in
            !paused.contains { $0.breakpointKey == flow.breakpointKey }
        }.sorted { $0.started < $1.started }
        breakpointDrafts = breakpointDrafts.filter { keys.contains($0.key) }
        breakpointLoads = breakpointLoads.filter { keys.contains($0.key) }
        breakpointErrors = breakpointErrors.filter { keys.contains($0.key) }
        if let selectedBreakpoint, !keys.contains(selectedBreakpoint) {
            self.selectedBreakpoint = nil
            breakpointNotice = "The selected breakpoint is no longer paused."
        }
        if selectedBreakpoint == nil, let first = paused.first { selectBreakpoint(first.breakpointKey) }
        if !additions.isEmpty { showPausedTraffic = true }
    }

    func selectBreakpoint(_ key: String) {
        guard let flow = paused.first(where: { $0.breakpointKey == key }) else { return }
        selectedBreakpoint = key
        breakpointNotice = nil
        guard breakpointDrafts[key] == nil, breakpointLoads[key] == nil else { return }
        let token = UUID()
        breakpointLoads[key] = token
        breakpointErrors[key] = nil
        Task {
            do {
                let edit: PausedEdit
                if let breakpointLoader { edit = try await breakpointLoader(flow.id) }
                else {
                    guard let api = engine.api else { throw AppFailure("Capture is stopped") }
                    edit = try await api.get("/paused/\(flow.id)", as: PausedEdit.self)
                }
                guard breakpointLoads[key] == token else { return }
                guard edit.id == flow.id, "paused-" + edit.phase == flow.state else {
                    throw AppFailure("This breakpoint is no longer paused; wait for the queue to refresh.")
                }
                breakpointDrafts[key] = BreakpointDraft(edit)
            } catch {
                if breakpointLoads[key] == token { breakpointErrors[key] = error.localizedDescription }
            }
            if breakpointLoads[key] == token { breakpointLoads[key] = nil }
        }
    }

    func continueBreakpoint(_ key: String, cancel: Bool) async -> Bool {
        guard !ruleOperation, !busy, let draft = breakpointDrafts[key],
              paused.contains(where: { $0.breakpointKey == key }) else { return false }
        if !cancel, let error = draft.validationError { breakpointErrors[key] = error; return false }
        ruleOperation = true
        breakpointErrors[key] = nil
        defer { ruleOperation = false }
        do {
            var payload = draft.payload
            payload.cancel = cancel
            if let breakpointResumer { try await breakpointResumer(payload) }
            else {
                guard let api = engine.api else { throw AppFailure("Capture is stopped") }
                _ = try await api.request("/resume", method: "POST", body: JSONEncoder().encode(payload))
            }
            completedBreakpoints.insert(key)
            updatePausedTraffic(paused.filter { $0.breakpointKey != key })
            breakpointNotice = paused.isEmpty ? "All paused traffic has been handled." : nil
            return true
        } catch {
            if paused.contains(where: { $0.breakpointKey == key }) { breakpointErrors[key] = error.localizedDescription }
            return false
        }
    }
}
