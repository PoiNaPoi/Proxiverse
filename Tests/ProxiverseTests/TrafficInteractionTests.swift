import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class TrafficInteractionTests: XCTestCase {
    func testResetColumnsRestoresReadableOrderWithoutChangingTrafficSelectionOrSort() {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let scroll = NSScrollView(frame: table.frame)
        scroll.documentView = table
        for spec in TrafficTable.columns.reversed() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.minWidth = 45
            column.width = 1000
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let coordinator = TrafficTable.Coordinator(parent: TrafficTable(rows: [flow(1)], selectedID: .constant("flow-1")))
        coordinator.sourceRows = [flow(1)]
        coordinator.rows = [flow(1)]
        table.dataSource = coordinator
        table.reloadData()
        table.sortDescriptors = [NSSortDescriptor(key: "status", ascending: true)]
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(table.selectedRow, 0)

        coordinator.resetColumns(table)

        XCTAssertEqual(table.tableColumns.map { $0.identifier.rawValue }, TrafficTable.columns.map(\.id))
        XCTAssertLessThanOrEqual(table.tableColumns.reduce(0) { $0 + $1.width }, scroll.contentSize.width + 8)
        XCTAssertGreaterThanOrEqual(table.tableColumns[4].width, 100)
        XCTAssertEqual(table.selectedRow, 0)
        XCTAssertEqual(table.sortDescriptors.first?.key, "status")
    }

    private func flow(_ number: Int) -> TrafficFlow {
        TrafficFlow(id: "flow-\(number)", method: "POST", url: "https://api.test/items/\(number)?page=2", host: "api.test",
                    status: 201, state: "complete", started: Double(number), duration: 0.1, size: 30, error: nil, number: number)
    }

    func testNewTableStartsWithDescendingNumericIDsAndStillAllowsChangingSort() async throws {
        let parent = TrafficTable(rows: [flow(2), flow(10), flow(1)], selectedID: .constant(nil))
        let host = NSHostingController(rootView: parent)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.setContentSize(NSSize(width: 900, height: 400))
        defer { window.contentViewController = nil }
        host.view.layoutSubtreeIfNeeded()
        await drainMainQueue()
        func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { findTable($0) }.first
        }
        let table = try XCTUnwrap(findTable(host.view))
        XCTAssertEqual(table.sortDescriptors.first?.key, "id")
        XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
        func displayedIDs() -> [String] {
            (0..<table.numberOfRows).compactMap {
                (table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
            }
        }
        XCTAssertEqual(displayedIDs(), ["10", "2", "1"])
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        XCTAssertEqual(displayedIDs(), ["1", "2", "10"])
    }

    func testMissingSortDescriptorFallsBackToNewestIDFirst() {
        let parent = TrafficTable(rows: [], selectedID: .constant(nil))
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.sourceRows = [flow(2), flow(10), flow(1)]
        coordinator.sortAndReload(NSTableView())
        XCTAssertEqual(coordinator.rows.map(\.number), [10, 2, 1])
    }

    func testSourceCellShowsMapLocalAndClearsAttributionForOtherRows() throws {
        let coordinator = TrafficTable.Coordinator(parent: TrafficTable(rows: [], selectedID: .constant(nil)))
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        var mapped = flow(1)
        mapped.mapLocal = true
        var remote = flow(2)
        remote.mapLocal = false
        coordinator.rows = [mapped, remote, flow(3)]
        for (row, label, tooltip) in [
            (0, "Map Local", "Response served by Map Local"),
            (1, "—", "Response not served by Map Local"),
            (2, "—", "Response source unknown")
        ] {
            let cell = try XCTUnwrap(coordinator.tableView(table, viewFor: column, row: row) as? NSTableCellView)
            XCTAssertEqual(cell.textField?.stringValue, label)
            XCTAssertEqual(cell.textField?.accessibilityLabel(), tooltip)
            XCTAssertEqual(cell.toolTip, tooltip)
        }
    }

    func testMapLocalDefaultsUseClickedFlowAndResponseHeaders() {
        let response = FlowMessage(headers: [["Content-Type", "application/json"], ["X-Test", "one"], ["X-Test", "two"],
                                             ["Content-Length", "500"], ["Content-Encoding", "gzip"], ["Connection", "keep-alive"]],
                                   body: "{}", truncated: false, streamed: false, httpVersion: "HTTP/2")
        let rule = DebugRule.mapLocal(from: flow(7), response: response)
        XCTAssertEqual(rule.host, "api.test")
        XCTAssertEqual(rule.path, "/items/7?page=2")
        XCTAssertEqual(rule.method, "POST")
        XCTAssertEqual(rule.status, 201)
        XCTAssertEqual(rule.headers, "Content-Type: application/json\nX-Test: one\nX-Test: two")
        XCTAssertTrue(rule.file.isEmpty)
    }

    func testContextMenuUsesSnapshotRatherThanCurrentSelectionOrReorderedRows() {
        var selected: String? = "flow-1"
        var received: TrafficFlow?
        let parent = TrafficTable(rows: [flow(1), flow(2)], selectedID: Binding(get: { selected }, set: { selected = $0 }),
                                  onMapLocal: { received = $0 })
        let coordinator = TrafficTable.Coordinator(parent: parent)
        let item = NSMenuItem()
        item.representedObject = flow(2)
        coordinator.rows = [flow(3), flow(1)]
        coordinator.mapLocal(item)
        XCTAssertEqual(received?.id, "flow-2")
        XCTAssertEqual(selected, "flow-1")
    }

    func testBreakpointMenuUsesClickedSnapshotWithoutChangingSelection() throws {
        final class ClickedTable: NSTableView {
            override var clickedRow: Int { 0 }
        }
        var selected: String? = "flow-1"
        var received: TrafficFlow?
        let coordinator = TrafficTable.Coordinator(parent: TrafficTable(
            rows: [], selectedID: Binding(get: { selected }, set: { selected = $0 }),
            onBreakpoint: { received = $0 }))
        let table = ClickedTable()
        coordinator.table = table
        coordinator.rows = [flow(2), flow(1)]
        let menu = NSMenu()
        coordinator.menuNeedsUpdate(menu)
        let item = try XCTUnwrap(menu.items.first { $0.title == "Breakpoint…" })
        XCTAssertEqual((item.representedObject as? TrafficFlow)?.id, "flow-2")
        coordinator.rows = [flow(3), flow(1)]
        coordinator.addBreakpoint(item)
        XCTAssertEqual(received?.id, "flow-2")
        XCTAssertEqual(selected, "flow-1")
    }

    func testFirstRowFollowsNewRequestInDescendingSort() async {
        var selected: String? = "flow-2"
        let table = NSTableView()
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let parent = TrafficTable(rows: [], selectedID: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.rows = [flow(2), flow(1)]
        coordinator.sourceRows = [flow(1), flow(2), flow(3)]
        coordinator.sortAndReload(table, followFirstOnInsert: true)
        await drainMainQueue()
        XCTAssertEqual(selected, "flow-3")
    }

    func testOtherRowStaysSelectedAndSortingAloneDoesNotEnableFollowing() async {
        var selected: String? = "flow-1"
        let table = NSTableView()
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let parent = TrafficTable(rows: [], selectedID: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.rows = [flow(2), flow(1)]
        coordinator.sourceRows = [flow(1), flow(2), flow(3)]
        coordinator.sortAndReload(table, followFirstOnInsert: true)
        await drainMainQueue()
        XCTAssertEqual(selected, "flow-1")
        selected = "flow-3"
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        coordinator.sortAndReload(table)
        await drainMainQueue()
        XCTAssertEqual(selected, "flow-3")
    }

    func testQueuedFollowCannotOverrideNewUserSelection() async {
        var selected: String? = "flow-2"
        let table = NSTableView()
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let parent = TrafficTable(rows: [], selectedID: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.rows = [flow(2), flow(1)]
        coordinator.sourceRows = [flow(1), flow(2), flow(3)]
        coordinator.sortAndReload(table, followFirstOnInsert: true)
        selected = "flow-1"
        await drainMainQueue()
        XCTAssertEqual(selected, "flow-1")
    }

    func testFirstRowContinuesAfterRetentionEvictsSelectedFlow() async {
        var selected: String? = nil // CaptureModel clears the evicted ID before updating the table.
        let table = NSTableView()
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        let parent = TrafficTable(rows: [], selectedID: Binding(get: { selected }, set: { selected = $0 }))
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.rows = [flow(1), flow(2)]
        table.dataSource = coordinator
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.sourceRows = [flow(2), flow(3)]
        coordinator.sortAndReload(table, followFirstOnInsert: true)
        await drainMainQueue()
        XCTAssertEqual(selected, "flow-2")
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
