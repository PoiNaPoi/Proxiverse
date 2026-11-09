import AppKit
import SwiftUI

struct BreakpointsView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Paused Traffic", systemImage: "pause.circle.fill").font(.headline)
                    Spacer()
                    Text("\(model.paused.count)").monospacedDigit().foregroundStyle(.secondary)
                }.padding(16)
                Divider()
                List(selection: Binding(get: { model.selectedBreakpoint }, set: { key in
                    if let key { Task { @MainActor in model.selectBreakpoint(key) } }
                })) {
                    ForEach(model.paused) { flow in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("#\(flow.number ?? 0)").monospacedDigit()
                                Text(flow.state == "paused-request" ? "Request" : "Response")
                                    .font(.caption.bold()).foregroundStyle(.orange)
                                Spacer()
                                if model.breakpointDrafts[flow.breakpointKey] != nil {
                                    Image(systemName: "pencil").help("Draft retained until Continue")
                                }
                            }
                            Text("\(flow.method) \(flow.host)").font(.callout.bold()).lineLimit(1)
                            Text(flow.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 6).tag(flow.breakpointKey)
                    }
                }.disabled(model.ruleOperation)
                Divider()
                Text("Traffic stays paused until you Continue or Cancel Request.")
                    .font(.caption).foregroundStyle(.secondary).padding(14)
            }.frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            if let key = model.selectedBreakpoint,
               let flow = model.paused.first(where: { $0.breakpointKey == key }) {
                if let snapshot = model.breakpointDrafts[key] {
                    BreakpointEditor(model: model, key: key, flow: flow, draft: Binding(
                        get: { model.breakpointDrafts[key] ?? snapshot },
                        set: { if model.breakpointDrafts[key] != nil { model.breakpointDrafts[key] = $0 } }
                    )).id(key)
                } else {
                    VStack(spacing: 16) {
                        if let error = model.breakpointErrors[key] {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            Button("Retry") { model.selectBreakpoint(key) }
                        } else { ProgressView("Loading breakpoint…") }
                        Button("Close") { dismiss() }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 16) {
                    ContentUnavailableView("No paused traffic", systemImage: "pause.circle",
                        description: Text(model.breakpointNotice ?? "Matching requests and responses will appear here automatically."))
                    Button("Close") { dismiss() }.padding(.bottom, 24)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .onAppear {
            if let key = model.selectedBreakpoint ?? model.paused.first?.breakpointKey { model.selectBreakpoint(key) }
        }
    }
}

private struct BreakpointEditor: View {
    @ObservedObject var model: CaptureModel
    let key: String
    let flow: TrafficFlow
    @Binding var draft: BreakpointDraft
    @Environment(\.dismiss) private var dismiss
    @State private var editorCommand: SyntaxTextEditor.Command?
    @State private var formattingError: String?
    @State private var headersExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Breakpoint #\(flow.number ?? 0)").font(.title2.bold())
                    Text(draft.edit.phase == "request" ? "REQUEST" : "RESPONSE")
                        .font(.caption.bold()).foregroundStyle(.orange)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                    Spacer()
                }
                if draft.edit.phase == "request" {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Method").font(.caption).foregroundStyle(.secondary)
                            TextField("Method", text: $draft.edit.method).frame(width: 90)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL").font(.caption).foregroundStyle(.secondary)
                            TextField("URL", text: $draft.edit.url)
                        }
                    }
                } else {
                    Text("\(draft.edit.method) \(draft.edit.url)").font(.callout).textSelection(.enabled).lineLimit(2)
                    HStack {
                        Text("Status").font(.caption).foregroundStyle(.secondary)
                        TextField("Status", text: $draft.statusText).frame(width: 90)
                    }
                }
            }.textFieldStyle(.roundedBorder).padding(20)
            Divider()
            VSplitView {
                headers.frame(minHeight: headersExpanded ? 140 : 56,
                              idealHeight: headersExpanded ? 200 : 56,
                              maxHeight: headersExpanded ? .infinity : 56)
                bodyEditor.frame(minHeight: 200, maxHeight: .infinity)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let error = model.breakpointErrors[key] ?? draft.validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Button("Cancel Request", role: .destructive) { submit(cancel: true) }
                    Spacer()
                    if model.ruleOperation { ProgressView().controlSize(.small); Text("Please wait…").font(.caption) }
                    Button("Close") { dismiss() }
                    Button("Continue") { submit(cancel: false) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(draft.validationError != nil)
                }
                Text("Edits are sent only when you Continue. Closing keeps this draft and traffic paused.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(model.ruleOperation || model.busy)
    }

    private var headers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { headersExpanded.toggle() } label: {
                    HStack {
                        Image(systemName: headersExpanded ? "chevron.down" : "chevron.right")
                        Label("Headers", systemImage: "list.bullet.rectangle").font(.headline)
                        Text("\(draft.headers.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(headersExpanded ? "Hide Headers" : "Show Headers")
                if headersExpanded {
                    Button { draft.headers.append(BreakpointHeader(name: "", value: "")) } label: {
                        Label("Add Header", systemImage: "plus")
                    }
                }
            }
            if headersExpanded {
                HStack {
                    Text("Name").frame(width: 190, alignment: .leading)
                    Text("Value").frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 26, height: 1)
                }.font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach($draft.headers) { $header in
                            HStack(alignment: .top, spacing: 8) {
                                TextField("Name", text: $header.name).frame(width: 190)
                                    .accessibilityLabel("Header name")
                                TextField("Value", text: $header.value, axis: .vertical)
                                    .lineLimit(1...3).accessibilityLabel("Header value")
                                Button {
                                    draft.headers.removeAll { $0.id == header.id }
                                } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).frame(width: 26).help("Remove Header")
                                    .accessibilityLabel("Remove Header \(header.name)")
                            }.font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder)
                        }
                    }.padding(2)
                }
            }
        }.padding(16)
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Body", systemImage: "curlybraces").font(.headline)
                Spacer()
                if draft.edit.body != nil {
                    Button("Format JSON") { editorCommand = .init(kind: .format) }
                    Button("Collapse All") { editorCommand = .init(kind: .collapseAll) }
                    Button("Expand All") { editorCommand = .init(kind: .expandAll) }
                }
            }
            if draft.edit.body != nil {
                SyntaxTextEditor(text: Binding(get: { draft.edit.body ?? "" }, set: { draft.edit.body = $0 }),
                                 syntax: .json, accessibilityName: "Breakpoint body", command: editorCommand,
                                 onError: { formattingError = $0 }, maximumFormattedBytes: BreakpointDraft.maximumBodyBytes)
                    .border(.quaternary)
                if let formattingError { Text(formattingError).font(.caption).foregroundStyle(.red) }
                Text("\((draft.edit.body ?? "").utf8.count.formatted()) / 262,144 UTF-8 bytes")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Body editing unavailable", systemImage: "doc.lock",
                    description: Text("Streamed, unknown-length, encoded, binary or >256 KiB content cannot be edited. Original bytes are preserved; headers can still be edited."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func submit(cancel: Bool) {
        Task { _ = await model.continueBreakpoint(key, cancel: cancel) }
    }
}
