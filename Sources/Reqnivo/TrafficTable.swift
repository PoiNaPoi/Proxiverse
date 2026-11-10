import AppKit
import SwiftUI

struct TrafficTable: NSViewRepresentable {
    let rows: [TrafficFlow]
    @Binding var selectedID: String?
    var selectedIDs: Set<String> = []
    var pinnedIDs: Set<String> = []
    var filterRevision = 0
    var columnResetRevision = 0
    var onSelection: ((Set<String>, String?) -> Void)?
    var onSortChanged: (TrafficSort) -> Void = { _ in }
    var onPin: (Set<String>, Bool) -> Void = { _, _ in }
    var onFilter: (TrafficQuery.Field, String, Bool) -> Void = { _, _, _ in }
    var canEditFilters = true
    var onMapLocal: (TrafficFlow) -> Void = { _ in }
    var onBreakpoint: (TrafficFlow) -> Void = { _ in }
    var onReloaded: () -> Void = {}

    static let columns: [(id: String, title: String, width: Double)] = [
        ("id", "ID", 48), ("method", "Method", 68), ("status", "Status", 84),
        ("host", "Host", 160), ("path", "Path", 240), ("time", "Time", 70),
        ("size", "Size", 70), ("source", "Source", 90)
    ]

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .fullWidth
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        table.menu = menu
        for (identifier, title, width) in Self.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "path" ? 100 : (identifier == "host" ? 100 : 45)
            column.maxWidth = identifier == "path" ? 600 : 400
            column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
            table.addTableColumn(column)
        }
        table.autosaveName = "Reqnivo.TrafficTable"
        table.autosaveTableColumns = true
        table.setAccessibilityLabel("Captured traffic")
        let scroll = NSScrollView()
        table.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        table.autoresizingMask = [.width]
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        context.coordinator.table = table
        table.sortDescriptors = [NSSortDescriptor(key: TrafficColumn.number.rawValue, ascending: false)]
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changedFilter = coordinator.parent.filterRevision != filterRevision
        let changedPins = coordinator.parent.pinnedIDs != pinnedIDs
        let resetColumns = coordinator.parent.columnResetRevision != columnResetRevision
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        coordinator.updating = true
        defer { coordinator.updating = false }
        if resetColumns { coordinator.resetColumns(table) }
        if coordinator.sourceRows != rows || changedPins {
            coordinator.sourceRows = rows
            coordinator.sortAndReload(table, followFirstOnInsert: !changedFilter && !changedPins)
        } else {
            coordinator.restoreSelection(table)
        }
        onReloaded()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: TrafficTable
        var sourceRows: [TrafficFlow] = []
        var rows: [TrafficFlow] = []
        weak var table: NSTableView?
        var updating = false
        private var selection: Set<String> {
            parent.selectedIDs.union(parent.selectedID.map { [$0] } ?? [])
        }

        private func publishSelection(_ ids: Set<String>, primary: String?) {
            if let onSelection = parent.onSelection { onSelection(ids, primary) }
            else { parent.selectedID = primary }
        }

        struct PinAction {
            let ids: Set<String>
            let pinned: Bool
        }
        struct FilterAction {
            let field: TrafficQuery.Field
            let value: String
            let excluded: Bool
        }

        init(parent: TrafficTable) { self.parent = parent }
        func resetColumns(_ table: NSTableView) {
            let selectedRows = table.selectedRowIndexes
            let available = table.enclosingScrollView?.contentSize.width ?? table.frame.width
            let scale = min(1, available / TrafficTable.columns.reduce(0) { $0 + $1.width })
            for (index, spec) in TrafficTable.columns.enumerated() {
                let current = table.column(withIdentifier: NSUserInterfaceItemIdentifier(spec.id))
                guard current >= 0 else { continue }
                table.moveColumn(current, toColumn: index)
                let column = table.tableColumns[index]
                column.width = max(column.minWidth, spec.width * scale)
            }
            table.sizeToFit()
            table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating else { return }
            updating = true
            defer { updating = false }
            sortAndReload(tableView)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            let item = NSMenuItem(title: "Map Local…", action: #selector(mapLocal(_:)), keyEquivalent: "")
            item.target = self
            // Snapshot the clicked row: capture updates may reorder rows while the menu is open.
            item.representedObject = rows[table.clickedRow]
            item.isEnabled = rows[table.clickedRow].tlsPassthrough != true
            menu.addItem(item)
            let flow = rows[table.clickedRow]
            let breakpoint = NSMenuItem(title: "Breakpoint…", action: #selector(addBreakpoint(_:)), keyEquivalent: "")
            breakpoint.target = self
            breakpoint.representedObject = flow
            breakpoint.isEnabled = flow.tlsPassthrough != true
            menu.addItem(breakpoint)
            let targets = selection.contains(flow.id) ? selection : [flow.id]
            let pin = NSMenuItem(title: targets.isSubset(of: parent.pinnedIDs) ? "Unpin Selected" : "Pin Selected",
                                 action: #selector(pinTraffic(_:)), keyEquivalent: "")
            pin.target = self
            pin.representedObject = PinAction(ids: targets, pinned: !targets.isSubset(of: parent.pinnedIDs))
            menu.addItem(pin)
            menu.addItem(.separator())
            let fields: [(TrafficQuery.Field, String?)] = [
                (.host, flow.host), (.path, flow.path), (.method, flow.method),
                (.status, flow.status.map(String.init)), (.type, flow.contentType), (.state, flow.state)
            ]
            for excluded in [false, true] {
                let title = excluded ? "Exclude" : "Include"
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                for (field, value) in fields {
                    guard let value, !value.isEmpty else { continue }
                    let action = NSMenuItem(title: "\(field.rawValue.capitalized): \(value)",
                                            action: #selector(filterTraffic(_:)), keyEquivalent: "")
                    action.target = self
                    action.representedObject = FilterAction(field: field, value: value, excluded: excluded)
                    action.isEnabled = parent.canEditFilters
                    submenu.addItem(action)
                }
                let group = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                group.submenu = submenu
                group.isEnabled = parent.canEditFilters && !submenu.items.isEmpty
                menu.addItem(group)
            }
        }

        @objc func pinTraffic(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? PinAction else { return }
            parent.onPin(action.ids, action.pinned)
        }

        @objc func filterTraffic(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? FilterAction else { return }
            parent.onFilter(action.field, action.value, action.excluded)
        }

        @objc func mapLocal(_ sender: NSMenuItem) {
            guard let flow = sender.representedObject as? TrafficFlow else { return }
            parent.onMapLocal(flow)
        }

        @objc func addBreakpoint(_ sender: NSMenuItem) {
            guard let flow = sender.representedObject as? TrafficFlow else { return }
            parent.onBreakpoint(flow)
        }

        func sortAndReload(_ table: NSTableView, followFirstOnInsert: Bool = false) {
            let previousSelection = parent.selectedID
            let previousSelections = selection
            let revision = parent.filterRevision
            let pins = parent.pinnedIDs
            let wasFirst = !rows.isEmpty && (rows.first?.id == previousSelection ||
                (previousSelection == nil && table.selectedRow == 0))
            let previousIDs = Set(rows.map(\.id))
            let descriptor = table.sortDescriptors.first
            let column = descriptor?.key.flatMap(TrafficColumn.init(rawValue:)) ?? .number
            let sort = TrafficSort(column: column, ascending: descriptor?.ascending ?? false)
            parent.onSortChanged(sort)
            let sorted = sort.sorted(sourceRows)
            rows = pins.isEmpty ? sorted : sorted.filter { pins.contains($0.id) } + sorted.filter { !pins.contains($0.id) }
            table.reloadData()
            if followFirstOnInsert, pins.isEmpty, previousSelections.count <= 1, wasFirst,
               rows.contains(where: { !previousIDs.contains($0.id) }),
               let firstID = rows.first?.id, firstID != previousSelection {
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                table.scrollRowToVisible(0)
                // Publish outside updateNSView; reject the update if selection/sort changed meanwhile.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.selectedID == previousSelection,
                          self.selection == previousSelections, self.parent.filterRevision == revision,
                          self.parent.pinnedIDs == pins,
                          table.sortDescriptors.first?.key == descriptor?.key,
                          table.sortDescriptors.first?.ascending == descriptor?.ascending,
                          self.rows.first?.id == firstID else { return }
                    self.publishSelection([firstID], primary: firstID)
                }
            } else {
                restoreSelection(table)
            }
        }

        func restoreSelection(_ table: NSTableView) {
            let selected = selection
            let indexes = selected.isEmpty ? IndexSet() : IndexSet(rows.indices.filter { selected.contains(rows[$0].id) })
            if indexes != table.selectedRowIndexes {
                table.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let column = tableColumn else { return nil }
            let identifier = column.identifier
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? makeCell(identifier)
            let flow = rows[row]
            let value: String
            let accessibilityValue: String
            switch identifier.rawValue {
            case "id":
                value = (parent.pinnedIDs.contains(flow.id) ? "★ " : "") + (flow.number.map(String.init) ?? "—")
                accessibilityValue = (parent.pinnedIDs.contains(flow.id) ? "Pinned, " : "") +
                    (flow.number.map { "Request \($0)" } ?? "Unnumbered request")
            case "method":
                value = flow.method
                accessibilityValue = "Method \(flow.method)"
            case "status":
                if flow.tlsPassthrough == true {
                    value = "Encrypted"
                    accessibilityValue = "HTTPS decryption is off for this captured connection"
                } else if flow.state == "paused-request" {
                    value = "Ⅱ REQ"
                    accessibilityValue = "Paused request breakpoint"
                } else if flow.state == "paused-response" {
                    value = "Ⅱ RES"
                    accessibilityValue = "Paused response breakpoint"
                } else if let status = flow.status {
                    value = String(status)
                    accessibilityValue = "Status \(status)"
                } else if flow.state == "error" {
                    value = "ERR"
                    accessibilityValue = "Error \(flow.error ?? "")"
                } else {
                    value = "…"
                    accessibilityValue = "Pending response"
                }
            case "host":
                value = flow.host
                accessibilityValue = "Host \(flow.host)"
            case "source":
                value = flow.mapLocal == true ? "Map Local" : "—"
                accessibilityValue = flow.mapLocal.map { $0 ? "Response served by Map Local" : "Response not served by Map Local" } ?? "Response source unknown"
            case "path":
                value = flow.path
                accessibilityValue = "Path \(flow.path)"
            case "time":
                value = flow.state == "pending" ? "…" : String(format: "%.0f ms", flow.duration * 1000)
                accessibilityValue = flow.state == "pending" ? "Pending response duration" : String(format: "Duration %.0f milliseconds", flow.duration * 1000)
            default:
                value = flow.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "stream"
                accessibilityValue = flow.size.map { "Size \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))" } ?? "Streaming body size"
            }
            cell.textField?.stringValue = value
            cell.textField?.setAccessibilityLabel(accessibilityValue)
            cell.textField?.textColor = flow.state == "error" || (flow.status ?? 0) >= 400 ? .systemRed : (flow.state.hasPrefix("paused-") ? .systemOrange : .labelColor)
            switch identifier.rawValue {
            case "id": cell.toolTip = flow.id
            case "path": cell.toolTip = flow.url
            case "source": cell.toolTip = accessibilityValue
            default: cell.toolTip = value
            }
            return cell
        }

        private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let visible = Set(rows.map(\.id))
            let chosen = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            let ids = selection.subtracting(visible).union(chosen)
            let added = chosen.subtracting(selection)
            let lead = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil
            let primary = lead.flatMap { added.contains($0) ? $0 : nil } ??
                rows.first(where: { added.contains($0.id) })?.id ??
                parent.selectedID.flatMap { ids.contains($0) ? $0 : nil } ??
                rows.first(where: { chosen.contains($0.id) })?.id
            if let primary, let index = rows.firstIndex(where: { $0.id == primary }) { table.scrollRowToVisible(index) }
            publishSelection(ids, primary: primary)
        }
    }
}
