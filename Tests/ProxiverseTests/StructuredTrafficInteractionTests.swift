import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class StructuredTrafficInteractionTests: XCTestCase {
    private func flow(_ n: Int, host: String = "api.test") -> TrafficFlow {
        TrafficFlow(id: "\(n)", method: "GET", url: "https://\(host)/v1/\(n)", host: host,
                    status: 200, state: "complete", started: Double(n), duration: 0.1, size: 2, error: nil, number: n)
    }

    private func model() -> CaptureModel {
        CaptureModel(detailLoader: { flowID in
            let message = FlowMessage(headers: [], body: "", truncated: false, streamed: false, httpVersion: "HTTP/1.1")
            return FlowDetail(summary: self.flow(Int(flowID) ?? 0), request: message, response: message)
        })
    }

    func testInvalidQueryKeepsEffectivePredicateForNewEventsAndRecovers() {
        let model = model()
        model.applyTrafficEvents([FlowEvent(sequence: 1, flow: flow(1)), FlowEvent(sequence: 2, flow: flow(2, host: "other.test"))])
        model.search = "host:api.test"
        model.applySearch()
        XCTAssertEqual(model.rows.map(\.id), ["1"])
        model.search = "status:999"
        model.applySearch()
        XCTAssertNotNil(model.queryError)
        model.applyTrafficEvents([FlowEvent(sequence: 3, flow: flow(3))])
        XCTAssertEqual(model.rows.map(\.id), ["1", "3"])
        XCTAssertFalse(model.saveFilter(name: "Invalid"))
        model.search = ""
        model.applySearch()
        XCTAssertNil(model.queryError)
        XCTAssertEqual(model.rows.count, 3)
    }

    func testHiddenSelectionIsPreservedAndPinsArePrunedByRetentionAndClear() {
        let model = model()
        model.applyTrafficEvents([FlowEvent(sequence: 1, flow: flow(1)), FlowEvent(sequence: 2, flow: flow(2, host: "other.test"))])
        model.selectTraffic(["1", "2"], primary: "2")
        model.setPinned(["1", "2", "missing"], pinned: true)
        XCTAssertEqual(model.pinnedIDs, ["1", "2"])
        model.search = "host:api.test"
        model.applySearch()
        XCTAssertEqual(model.selectedID, "2")
        XCTAssertEqual(model.selectedIDs, ["1", "2"])
        XCTAssertEqual(model.hiddenSelectionCount, 1)
        model.search = ""
        model.applySearch()
        XCTAssertEqual(model.hiddenSelectionCount, 0)
        model.applyTrafficEvents((3...10_002).map { FlowEvent(sequence: $0, flow: flow($0)) })
        XCTAssertNil(model.selectedID)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertTrue(model.pinnedIDs.isEmpty)
        model.clearDisplay()
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testClearDisplayResetsPinsWithoutDeletingSavedFiltersOrQuery() {
        let model = model()
        model.applyTrafficEvents([FlowEvent(sequence: 1, flow: flow(1))])
        model.setPinned(["1"], pinned: true)
        model.selectTraffic(["1"], primary: "1")
        model.search = "method:GET"
        model.applySearch()
        model.clearDisplay()
        XCTAssertTrue(model.pinnedIDs.isEmpty)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.search, "method:GET")
    }

    func testNativeSelectionChangeRetainsHiddenIDsAndPrimaryTracksNewSelection() {
        let table = NSTableView()
        table.allowsMultipleSelection = true
        var received: Set<String> = []
        var primary: String?
        let parent = TrafficTable(rows: [], selectedID: .constant("1"), selectedIDs: ["1", "hidden"],
                                  onSelection: { received = $0; primary = $1 })
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.table = table
        table.dataSource = coordinator
        coordinator.rows = [flow(1), flow(2), flow(3)]
        table.reloadData()
        table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        XCTAssertEqual(received, ["1", "2", "hidden"])
        XCTAssertEqual(primary, "2")
        table.deselectAll(nil)
        coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        XCTAssertEqual(received, ["hidden"])
        XCTAssertNil(primary, "The model chooses a hidden primary using retained capture order")
    }

    func testPrimaryEvictionChoosesOnlyRemainingSelection() {
        let model = model()
        model.applyTrafficEvents((1...10_000).map { FlowEvent(sequence: $0, flow: flow($0)) })
        model.selectTraffic(["1", "10", "200"], primary: "1")
        model.applyTrafficEvents([FlowEvent(sequence: 10_001, flow: flow(10_001))])
        XCTAssertEqual(model.selectedID, "200", "Fallback follows the displayed descending sort")
        XCTAssertEqual(model.selectedIDs, ["10", "200"])
        model.setPinned(["10"], pinned: true)
        model.selectTraffic(["10", "200"], primary: nil)
        XCTAssertEqual(model.selectedID, "10", "Pinned group comes first")
        model.setPinned(["10"], pinned: false)
        model.updateTrafficSort(TrafficSort(column: .number, ascending: true))
        model.selectTraffic(["10", "200"], primary: nil)
        XCTAssertEqual(model.selectedID, "10")
        model.search = "host:hidden.test"
        model.applySearch()
        model.updateTrafficSort(TrafficSort(column: .number, ascending: false))
        model.selectTraffic(["10", "200"], primary: nil)
        XCTAssertEqual(model.selectedID, "10", "Hidden fallback uses capture order, not visible sort")
    }

    func testChipEditWhileQueryIsPendingDoesNotUseStaleIndexAndBuilderRecovers() {
        let model = model()
        model.search = "host:api.test status:200"
        model.applySearch()
        model.search = "method:POST"
        var changed = false
        model.editQuery { _ in changed = true }
        XCTAssertFalse(changed)
        XCTAssertEqual(model.effectiveQuery.terms.first?.field, .method)
        XCTAssertFalse(model.addFilter(field: .status, value: "999"))
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.queryError)
        XCTAssertTrue(model.addFilter(field: .status, value: "201"))
        XCTAssertNil(model.queryError)
        XCTAssertEqual(model.effectiveQuery.terms.count, 2)
    }

    func testSavedPathScopeDoesNotBecomeDomainOnly() {
        let model = model()
        model.applySavedFilter(SavedTrafficFilter(name: "Path", query: "", scope: .domainPath(host: "api.test", pathPrefix: "/v1")))
        XCTAssertEqual(model.sidebarSelection, .domainPath(host: "api.test", pathPrefix: "/v1"))
    }

    func testSidebarCountsRemainRetainedRatherThanFilteredAndRefreshWithEvents() {
        let model = model()
        model.applyTrafficEvents([FlowEvent(sequence: 1, flow: flow(1)), FlowEvent(sequence: 2, flow: flow(2, host: "other.test"))])
        model.search = "host:api.test"
        model.applySearch()
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.retainedCount, 2)
        XCTAssertEqual(model.hostCounts, ["api.test": 1, "other.test": 1])
        XCTAssertEqual(model.hostPaths["api.test"]?.first?.pathPrefix, "/v1/1")
        model.applyTrafficEvents([FlowEvent(sequence: 3, flow: flow(3))])
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(model.retainedCount, 3)
        XCTAssertEqual(model.hostCounts["api.test"], 2)
        XCTAssertEqual(model.hostPaths["api.test"]?.count, 2)
    }

    func testFilterControlsHostInLightDarkAndNarrowWorkspaceWithoutLosingPrimary() {
        let model = model()
        model.applyTrafficEvents([FlowEvent(sequence: 1, flow: flow(1)), FlowEvent(sequence: 2, flow: flow(2))])
        model.selectTraffic(["1", "2"], primary: "2")
        model.search = "host:api.test method:GET -status:400-599"
        model.applySearch()
        let host = NSHostingController(rootView: TrafficFilterControls(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 240),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = host
        defer { window.contentViewController = nil }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            host.view.appearance = NSAppearance(named: appearance)
            for width in [800.0, 1200.0] {
                window.setContentSize(NSSize(width: width, height: 240))
                host.view.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.view.frame.width, width, accuracy: 1)
                XCTAssertEqual(model.selectedID, "2")
                XCTAssertEqual(model.selectedIDs, ["1", "2"])
            }
        }
    }

    func testPinnedGroupsRespectSortAndDoNotEnableAutoFollow() async {
        var primary: String? = "2"
        let table = NSTableView()
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        let parent = TrafficTable(rows: [], selectedID: Binding(get: { primary }, set: { primary = $0 }),
                                  selectedIDs: ["2"], pinnedIDs: ["1"])
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.rows = [flow(2), flow(1)]
        coordinator.sourceRows = [flow(1), flow(2), flow(3)]
        coordinator.sortAndReload(table, followFirstOnInsert: true)
        await drain()
        XCTAssertEqual(coordinator.rows.map(\.id), ["1", "3", "2"])
        XCTAssertEqual(primary, "2")
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        coordinator.sortAndReload(table)
        XCTAssertEqual(coordinator.rows.map(\.id), ["1", "2", "3"])
    }

    func testMultiSelectionSurvivesSortAndFilterRestore() {
        let table = NSTableView()
        let parent = TrafficTable(rows: [], selectedID: .constant("2"), selectedIDs: ["1", "2"])
        let coordinator = TrafficTable.Coordinator(parent: parent)
        table.dataSource = coordinator
        coordinator.sourceRows = [flow(1), flow(2), flow(3)]
        table.allowsMultipleSelection = true
        coordinator.sortAndReload(table)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet([1, 2]))
        coordinator.sourceRows = [flow(1), flow(3)]
        coordinator.sortAndReload(table)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))
        coordinator.sourceRows = [flow(1), flow(2), flow(3)]
        table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        coordinator.sortAndReload(table)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet([0, 1]))
    }

    func testContextPinAndFilterUseSnapshotsAndDoNotMovePrimary() {
        var pinned: Set<String> = []
        var filtered: String?
        let parent = TrafficTable(rows: [], selectedID: .constant("1"), onPin: { ids, _ in pinned = ids },
                                  onFilter: { _, value, _ in filtered = value })
        let coordinator = TrafficTable.Coordinator(parent: parent)
        let item = NSMenuItem()
        item.representedObject = TrafficTable.Coordinator.PinAction(ids: ["2", "3"], pinned: true)
        coordinator.rows = [flow(9)]
        coordinator.pinTraffic(item)
        XCTAssertEqual(pinned, ["2", "3"])
        item.representedObject = TrafficTable.Coordinator.FilterAction(field: .host, value: "snapshot.test", excluded: true)
        coordinator.filterTraffic(item)
        XCTAssertEqual(filtered, "snapshot.test")
        XCTAssertEqual(coordinator.parent.selectedID, "1")
    }

    func testQueuedFollowCannotOverrideFilterPinSortOrMultipleSelection() async {
        for mutation in 0..<4 {
            var selected: String? = "2"
            let table = NSTableView()
            table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
            let parent = TrafficTable(rows: [], selectedID: Binding(get: { selected }, set: { selected = $0 }))
            let coordinator = TrafficTable.Coordinator(parent: parent)
            coordinator.rows = [flow(2), flow(1)]
            coordinator.sourceRows = [flow(1), flow(2), flow(3)]
            coordinator.sortAndReload(table, followFirstOnInsert: true)
            switch mutation {
            case 0: coordinator.parent.filterRevision += 1
            case 1: coordinator.parent.pinnedIDs = ["2"]
            case 2: table.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            default: coordinator.parent.selectedIDs = ["1", "2"]
            }
            await drain()
            XCTAssertEqual(selected, "2")
        }
    }

    private func drain() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
}
