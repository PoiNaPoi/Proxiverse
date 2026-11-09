import SwiftUI
import AppKit

struct RulesView: View {
    @ObservedObject var model: CaptureModel
    let kind: DebugRuleKind
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workspace: RuleWorkspace
    @Environment(\.openWindow) private var openWindow
    private var draft: RuleWorkspaceDraft {
        get { workspace.draft }
        nonmutating set { workspace.draft = newValue }
    }
    private var localError: String? {
        get { workspace.error }
        nonmutating set { workspace.error = newValue }
    }

    init(model: CaptureModel, kind: DebugRuleKind) {
        self.model = model
        self.kind = kind
        _workspace = StateObject(wrappedValue: RuleWorkspace(model: model, kind: kind))
    }
    @State private var search = ""
    @State private var selectedRuleIDs: Set<String> = []
    @State private var loaded = false
    @State private var prefillNotice: (ruleID: String, message: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(kind.title) Rules", systemImage: kind.symbol).font(.title2.bold())
                Text("\(draft.rules.filter(\.enabled).count) enabled / \(draft.rules.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if kind == .mapLocal {
                    Button("Import…", action: importRules)
                    Menu("Export…") {
                        Button("Export Selected (\(selectedRuleIDs.count))…") { exportRules(selectedIDs: selectedRuleIDs) }
                            .disabled(selectedRuleIDs.isEmpty)
                        Button("Export All…") { exportRules() }
                            .disabled(draft.rules.isEmpty)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                if kind == .breakpoint {
                    Button("Paused Traffic (\(model.paused.count))") { openWindow(id: "paused-traffic") }
                }
            }
            Text(kind == .mapLocal
                 ? "Serve a local file instead of the server response. The first enabled matching rule wins."
                 : "Pause matching requests or responses to inspect, edit, continue or cancel them.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 0) {
                sidebar.frame(width: 300).frame(maxHeight: .infinity)
                Divider()
                editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let localError { Text(localError).foregroundStyle(.red).font(.callout) }
            else { Text(workspace.notice).foregroundStyle(.secondary).font(.caption) }
            HStack {
                Text(kind == .mapLocal ? "Only Map Local rules are changed. Breakpoint rules are preserved."
                     : "Only breakpoint rules are changed. Already paused traffic remains paused.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 1040, height: 700)
            .onAppear {
                if !loaded {
                    loaded = true
                    workspace.load()
                    if let id = draft.selectedID { selectedRuleIDs = [id] }
                }
                consumePrefill()
                loadSelectedBody()
            }
            .onChange(of: model.pendingMapLocal?.rule.id) { _, _ in consumePrefill() }
            .onChange(of: model.pendingBreakpoint?.id) { _, _ in consumePrefill() }
            .onChange(of: draft.selectedID) { _, id in
                if let id, !selectedRuleIDs.contains(id) { selectedRuleIDs = [id] }
                loadSelectedBody()
            }
            .onChange(of: draft.rules.map(\.id)) { _, ids in
                selectedRuleIDs.formIntersection(Set(ids))
            }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            TextField("Search name, host, path or method", text: $search)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Search rules")
            if !search.isEmpty {
                HStack {
                    Text("\(draft.filtered(search).count) matches").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { search = "" }.buttonStyle(.link)
                }
            }
            if kind == .mapLocal {
                List(selection: Binding(get: { selectedRuleIDs }, set: { ids in
                    // AppKit selection callbacks can run inside a SwiftUI update.
                    Task { @MainActor in
                        selectedRuleIDs = ids
                        draft.selectedID = ids.count == 1 ? ids.first : nil
                    }
                })) { ruleRows }
                Text("⌘-click or Shift-click to select multiple rules to export or delete.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(selectedRuleIDs.count) selected").font(.caption).foregroundStyle(.secondary)
            } else {
                List(selection: Binding(get: { draft.selectedID }, set: { id in
                    Task { @MainActor in draft.selectedID = id }
                })) { ruleRows }
            }
            HStack {
                Button { add() } label: { Label("Add", systemImage: "plus") }
                Button {
                    draft.duplicateSelected()
                    search = ""
                } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .disabled(draft.selectedID == nil)
                Spacer()
            }
            HStack {
                Button("↑") { move(-1) }.help("Clear search before reordering").disabled(!canMove(-1))
                Button("↓") { move(1) }.help("Clear search before reordering").disabled(!canMove(1))
                Spacer()
                Button("Delete", role: .destructive) {
                    if kind == .mapLocal {
                        draft.removeRules(withIDs: selectedRuleIDs)
                        selectedRuleIDs = Set(draft.selectedID.map { [$0] } ?? [])
                    } else {
                        draft.removeSelected()
                    }
                }.disabled(kind == .mapLocal ? selectedRuleIDs.isEmpty : draft.selectedID == nil)
            }
        }.padding(.trailing, 12)
    }

    private var ruleRows: some View {
        ForEach(draft.filtered(search)) { rule in
            HStack(spacing: 8) {
                Toggle("Enable \(rule.name)", isOn: enabledBinding(for: rule.id))
                    .labelsHidden().toggleStyle(.checkbox)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name).font(.headline).lineLimit(1)
                    Text("\(rule.method) \(rule.urlPattern ?? (rule.host + rule.path))")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    if let index = draft.rules.firstIndex(where: { $0.id == rule.id }) {
                        Text("#\(index + 1) · \(rule.enabled ? "Enabled" : "Disabled")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.padding(.vertical, 4).tag(rule.id)
        }
    }

    @ViewBuilder private var editor: some View {
        if let index = draft.rules.firstIndex(where: { $0.id == draft.selectedID }) {
            let id = draft.rules[index].id
            RuleEditor(rule: $workspace.draft.rules[index], textBody: bodyBinding(for: id),
                       bodyNotice: prefillNotice?.ruleID == id ? prefillNotice?.message : nil,
                       fileName: draft.fileNames[id],
                       onSourceChange: { source in
                           do { try draft.setSource(source, for: id, store: model.ruleStore); localError = nil }
                           catch { localError = error.localizedDescription }
                       },
                       onChooseFile: { chooseFile(for: id) }, onReloadBody: loadSelectedBody)
                .id(id)
        } else if kind == .mapLocal, selectedRuleIDs.count > 1 {
            ContentUnavailableView("\(selectedRuleIDs.count) rules selected", systemImage: "checkmark.circle",
                                   description: Text("Choose Export Selected or Delete to act on these rules, or select one rule to edit."))
        } else {
            ContentUnavailableView("No \(kind.title) rule selected", systemImage: kind.symbol,
                                   description: Text("Select a rule or click Add to create one."))
        }
    }

    private func enabledBinding(for id: String) -> Binding<Bool> {
        Binding(get: { draft.rules.first(where: { $0.id == id })?.enabled ?? false },
                set: { value in
                    if let index = draft.rules.firstIndex(where: { $0.id == id }) { draft.rules[index].enabled = value }
                })
    }

    private func bodyBinding(for id: String) -> Binding<String>? {
        guard draft.textBodies[id] != nil else { return nil }
        return Binding(get: { draft.textBodies[id] ?? "" }, set: { draft.setBody($0, for: id) })
    }

    private func loadSelectedBody() {
        guard let id = draft.selectedID else { return }
        do { try workspace.loadBody(for: id); localError = nil }
        catch { localError = error.localizedDescription }
    }

    private func chooseFile(for id: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try draft.chooseFile(url, for: id, store: model.ruleStore); localError = nil }
        catch { localError = error.localizedDescription }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Import Proxiverse JSON or Proxyman Map Local .config. Rules are appended."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 256 * 1024 * 1024 else { throw AppFailure("Import file exceeds 256 MiB") }
            let entries = try MapLocalTransfer.decode(Data(contentsOf: url))
            draft = try MapLocalTransfer.append(entries, to: draft, store: model.ruleStore,
                                                otherRuleCount: model.rules.filter { $0.kind != "mapLocal" }.count)
            search = ""
            localError = nil
        } catch { localError = error.localizedDescription }
    }

    private func exportRules(selectedIDs: Set<String>? = nil) {
        do {
            let data = try MapLocalTransfer.export(draft, store: model.ruleStore, selectedIDs: selectedIDs)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Map Local.json"
            panel.message = selectedIDs == nil
                ? "Export all Map Local rules with their response bodies."
                : "Export \(selectedIDs?.count ?? 0) selected Map Local rules with their response bodies."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            localError = nil
        } catch { localError = error.localizedDescription }
    }

    private func consumePrefill() {
        if kind == .breakpoint, let pending = model.pendingBreakpoint {
            draft.add(pending)
            search = ""
            model.pendingBreakpoint = nil
            return
        }
        guard kind == .mapLocal, let prefill = model.pendingMapLocal else { return }
        var pending = prefill.rule
        pending.bodySource = .text
        draft.add(pending)
        if let body = prefill.body {
            draft.setBody(MessagePreview.prettyJSON(body, maximumBytes: RuleStore.maximumMockBytes) ?? body, for: pending.id)
        }
        if let notice = prefill.notice { prefillNotice = (pending.id, notice) }
        model.pendingMapLocal = nil
        loadSelectedBody()
    }

    private func add() {
        var rule = DebugRule()
        rule.kind = kind.rawValue
        rule.name = kind == .mapLocal ? "Local response" : "Pause traffic"
        if kind == .mapLocal { rule.bodySource = .text }
        if let flow = model.detail?.flow.summary {
            rule.host = URLComponents(string: flow.url)?.host ?? flow.host
            rule.path = flow.path
            rule.method = flow.method
        }
        draft.add(rule)
        search = ""
    }

    private func move(_ offset: Int) {
        guard canMove(offset), let index = draft.rules.firstIndex(where: { $0.id == draft.selectedID }) else { return }
        draft.rules.swapAt(index, index + offset)
    }

    private func canMove(_ offset: Int) -> Bool {
        guard search.isEmpty, let index = draft.rules.firstIndex(where: { $0.id == draft.selectedID }) else { return false }
        return draft.rules.indices.contains(index + offset)
    }
}

private struct RuleEditor: View {
    @Binding var rule: DebugRule
    let textBody: Binding<String>?
    let bodyNotice: String?
    let fileName: String?
    let onSourceChange: (MockBodySource) -> Void
    let onChooseFile: () -> Void
    let onReloadBody: () -> Void
    @State private var headersExpanded = false
    @State private var editorCommand: SyntaxTextEditor.Command?
    @State private var formattingError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Matching") {
                    Form {
                        Toggle("Enabled", isOn: $rule.enabled)
                        TextField("Name", text: $rule.name)
                        if rule.urlPattern != nil {
                            TextField("URL pattern", text: Binding(get: { rule.urlPattern ?? "" }, set: { rule.urlPattern = $0 }))
                            Toggle("Include subpaths", isOn: Binding(get: { rule.includeSubpaths ?? false }, set: { rule.includeSubpaths = $0 }))
                        } else {
                            TextField("Host", text: $rule.host)
                            TextField("Path + query", text: $rule.path)
                        }
                        Picker("Method", selection: $rule.method) {
                            ForEach(["*", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"], id: \.self) { Text($0).tag($0) }
                        }
                    }.formStyle(.columns).fixedSize(horizontal: false, vertical: true).padding(8)
                }
                Text("Host and path include query matching. * matches any text; ? matches one character.")
                    .font(.caption).foregroundStyle(.secondary)
                if rule.kind == "mapLocal" {
                    GroupBox("Response") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                LabeledContent("Status") {
                                    TextField("Status", value: $rule.status, format: .number.grouping(.never)).labelsHidden()
                                }
                                LabeledContent("Delay (ms)") {
                                    TextField("Delay", value: $rule.delayMilliseconds, format: .number.grouping(.never)).labelsHidden()
                                }
                            }
                            DisclosureGroup("Response headers", isExpanded: $headersExpanded) {
                                SyntaxTextEditor(text: $rule.headers, syntax: .headers, accessibilityName: "Mock response headers")
                                    .frame(height: 120).border(.quaternary)
                                Text("One Name: value per line. Use Content-Type: application/json for JSON.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(8)
                    }
                    GroupBox("Body") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let bodyNotice {
                                Label(bodyNotice, systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Picker("Body source", selection: Binding(get: { rule.bodySource ?? .file }, set: onSourceChange)) {
                                Text("Text / JSON").tag(MockBodySource.text)
                                Text("File").tag(MockBodySource.file)
                            }.pickerStyle(.segmented).frame(maxWidth: 260)
                            if rule.bodySource == .text {
                                if let textBody {
                                    HStack {
                                        Button("Format JSON") { editorCommand = .init(kind: .format) }
                                        Spacer()
                                        Button("Collapse All") { editorCommand = .init(kind: .collapseAll) }
                                        Button("Expand All") { editorCommand = .init(kind: .expandAll) }
                                    }
                                    SyntaxTextEditor(text: textBody, syntax: .json, accessibilityName: "Mock response body",
                                                     command: editorCommand, onError: { formattingError = $0 })
                                        .frame(minHeight: 240).border(.quaternary)
                                    if let formattingError { Text(formattingError).font(.caption).foregroundStyle(.red) }
                                    let count = textBody.wrappedValue.utf8.count
                                    Text("\(count.formatted()) / \(RuleStore.maximumMockBytes.formatted()) UTF-8 bytes")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(count > RuleStore.maximumMockBytes ? Color.red : Color.secondary)
                                    if textBody.wrappedValue.utf16.count > SyntaxTextEditor.maximumHighlightedCharacters {
                                        Text("Syntax colors cover the first 256K UTF-16 characters. The entire body is saved.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Body could not be loaded. Your saved file has not been changed.")
                                        .foregroundStyle(.secondary)
                                    Button("Reload Body", action: onReloadBody)
                                }
                            } else {
                                HStack {
                                    Button("Choose Response File…", action: onChooseFile)
                                    Text(fileName ?? (rule.file.isEmpty ? "No file selected" : "Saved response file"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Text("Text and files support up to 8 MiB. Changes save and apply automatically after you stop editing.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    Text("Matching streaming uploads are cancelled; request body must have a known size up to 1 MiB.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    GroupBox("Pause") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Pause request before forwarding", isOn: $rule.request)
                            Toggle("Pause response before returning", isOn: $rule.response)
                            Text("Paused Traffic opens automatically to edit and continue. Stop cancels paused items. At most 32 items can wait; additional matches are cancelled.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

