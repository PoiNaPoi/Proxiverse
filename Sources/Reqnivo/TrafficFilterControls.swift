import SwiftUI

struct TrafficFilterControls: View {
    @ObservedObject var model: CaptureModel
    @State private var adding = false
    @State private var field: TrafficQuery.Field = .host
    @State private var value = ""
    @State private var excluded = false
    @State private var naming = false
    @State private var filterName = ""
    @State private var renaming: SavedTrafficFilter?

    private var active: SavedTrafficFilter? {
        model.savedFilters.first { $0.id == model.activeSavedFilterID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button("Add Filter", systemImage: "line.3.horizontal.decrease.circle") { adding = true }
                    .disabled(model.queryError != nil)
                    .popover(isPresented: $adding) { builder }
                Menu {
                    if model.savedFilters.isEmpty {
                        Text("No saved filters")
                    }
                    ForEach(model.savedFilters) { entry in
                        Menu(entry.name) {
                            Button("Apply") { model.applySavedFilter(entry) }
                            Text("Scope: \(scopeName(entry.scope))")
                            Text(entry.query.isEmpty ? "All text" : entry.query)
                            Button("Rename…") {
                                renaming = entry
                                filterName = entry.name
                                naming = true
                            }
                            Button("Delete", role: .destructive) { model.deleteFilter(entry) }
                        }
                    }
                } label: {
                    Label(active.map { $0.name + (model.savedFilterModified ? " (modified)" : "") } ?? "Saved Filters",
                          systemImage: "line.3.horizontal.decrease.circle")
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: 220)
                .fixedSize(horizontal: true, vertical: false)
                .help(active?.name ?? "Apply or manage saved filters")
                Button("Save…") {
                    renaming = nil
                    filterName = ""
                    naming = true
                }.disabled(model.queryError != nil)
                if let active {
                    Button("Update") { model.saveFilter(name: active.name, replacingID: active.id) }
                        .disabled(model.queryError != nil || !model.savedFilterModified)
                }
                Spacer()
                if !model.selectedIDs.isEmpty {
                    Text("\(model.selectedIDs.count) selected")
                    if model.hiddenSelectionCount > 0 {
                        Text("\(model.hiddenSelectionCount) hidden by filters")
                            .foregroundStyle(.secondary)
                    }
                    if let primary = model.selectedID, !model.rows.contains(where: { $0.id == primary }) {
                        Text("Inspecting hidden request").foregroundStyle(.secondary)
                    }
                    Button("Deselect All") { model.selectTraffic([], primary: nil) }
                }
            }
            .font(.caption)
            if let error = model.queryError {
                Label("\(error). Showing the last valid query.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Invalid traffic query. \(error). Showing the last valid query.")
            }
            if !model.effectiveQuery.terms.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.effectiveQuery.terms.enumerated()), id: \.offset) { index, term in
                            HStack(spacing: 4) {
                                Button {
                                    model.editQuery {
                                        guard $0.terms.indices.contains(index), $0.terms[index] == term else { return }
                                        $0.terms[index].excluded.toggle()
                                    }
                                } label: {
                                    Text("\(term.excluded ? "−" : "+") \(term.field.rawValue): \(term.value)")
                                }
                                .help("Toggle include/exclude")
                                .accessibilityLabel("\(term.excluded ? "Exclude" : "Include") \(term.field.rawValue) \(term.value). Toggle.")
                                Button {
                                    model.editQuery {
                                        guard $0.terms.indices.contains(index), $0.terms[index] == term else { return }
                                        $0.terms.remove(at: index)
                                    }
                                } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Remove \(term.field.rawValue) filter")
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                        }
                    }.font(.caption)
                }
                .disabled(model.queryError != nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .alert(renaming == nil ? "Save Filter" : "Rename Filter", isPresented: $naming) {
            TextField("Filter name", text: $filterName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let entry = renaming { model.renameFilter(entry, name: filterName) }
                else { model.saveFilter(name: filterName) }
            }.disabled(filterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text(renaming == nil ? "Saves the query and current sidebar scope, not traffic or pins." : "Enter a new name.")
        }
    }

    private var builder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Filter · AND").font(.headline)
            Picker("Field", selection: $field) {
                ForEach(TrafficQuery.Field.allCases) { Text($0.rawValue).tag($0) }
            }
            if field == .state {
                Picker("State", selection: $value) {
                    Text("Choose…").tag("")
                    ForEach(["pending", "complete", "error", "paused-request", "paused-response", "tls-passthrough"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
            } else {
                TextField(field == .status ? "100–599 or 400-499" : "Value", text: $value)
                    .onSubmit { add() }
            }
            Toggle("Exclude matching traffic (display only)", isOn: $excluded)
            HStack {
                Spacer()
                Button("Add") { add() }.disabled(value.isEmpty)
            }
        }
        .padding().frame(width: 350)
        .onChange(of: field) { _, _ in value = "" }
    }

    private func add() {
        if model.addFilter(field: field, value: value, excluded: excluded) {
            adding = false
            value = ""
        }
    }

    private func scopeName(_ scope: SidebarFilter) -> String {
        switch scope {
        case .all: return "All Traffic"
        case .domain(let host): return host
        case .domainPath(let host, let path): return host + path
        case .client(let client): return "Client: " + client
        }
    }
}
