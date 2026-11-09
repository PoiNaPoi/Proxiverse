import AppKit
import SwiftUI
import XCTest
@testable import Proxiverse

@MainActor
final class WorkspaceTests: XCTestCase {
    func testDividerRestoresWhenRecreatingTheWorkspace() {
        let name = "Proxiverse.Tests.\(UUID().uuidString)"
        let key = "NSSplitView Subview Frames " + name + ".horizontal"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        func makeWindow() -> (NSWindow, WorkspaceSplitController<Text, Text>) {
            let controller = WorkspaceSplitController(first: Text("Traffic"), second: Text("Inspector"))
            controller.configure(vertical: false, autosaveName: name, firstMinimum: 180, secondMinimum: 260)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                                  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 900, height: 640))
            controller.view.layoutSubtreeIfNeeded()
            return (window, controller)
        }
        let (firstWindow, first) = makeWindow()
        first.splitView.setPosition(230, ofDividerAt: 0)
        first.view.layoutSubtreeIfNeeded()
        let height = first.firstHost.view.frame.height
        firstWindow.contentViewController = nil
        let (secondWindow, second) = makeWindow()
        defer { secondWindow.contentViewController = nil }
        XCTAssertEqual(second.firstHost.view.frame.height, height, accuracy: 2)
    }

    func testSplitLayoutFitsInAWindowAndPreservesMinimums() {
        let name = "Proxiverse.Tests.\(UUID().uuidString)"
        defer {
            for axis in ["horizontal", "vertical"] {
                UserDefaults.standard.removeObject(forKey: "NSSplitView Subview Frames \(name).\(axis)")
            }
        }
        let controller = WorkspaceSplitController(
            first: Text("Traffic").frame(maxWidth: .infinity, maxHeight: .infinity),
            second: Text("Inspector").frame(maxWidth: .infinity, maxHeight: .infinity))
        controller.configure(vertical: false, autosaveName: name,
                             firstMinimum: 180, secondMinimum: 260)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 900, height: 640))
        defer { window.contentViewController = nil }
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(240, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(controller.firstHost.view.frame.height, 180)
        XCTAssertGreaterThanOrEqual(controller.secondHost.view.frame.height, 260)
        controller.configure(vertical: true, autosaveName: name,
                             firstMinimum: 320, secondMinimum: 380)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(controller.firstHost.view.frame.width, 320)
        XCTAssertGreaterThanOrEqual(controller.secondHost.view.frame.width, 380)
    }

    func testLayoutChangesKeepTheSameHostedPanes() {
        let controller = WorkspaceSplitController(first: Text("Traffic"), second: Text("Inspector"))
        let first = controller.firstHost
        let second = controller.secondHost
        let name = "Proxiverse.Tests.\(UUID().uuidString)"
        controller.configure(vertical: false, autosaveName: name, firstMinimum: 180, secondMinimum: 260)
        XCTAssertFalse(controller.splitView.isVertical)
        XCTAssertEqual(controller.splitView.autosaveName, name + ".horizontal")
        controller.configure(vertical: true, autosaveName: name, firstMinimum: 320, secondMinimum: 380)
        XCTAssertTrue(controller.splitView.isVertical)
        XCTAssertTrue(controller.firstHost === first)
        XCTAssertTrue(controller.secondHost === second)
        XCTAssertEqual(controller.splitViewItems[0].minimumThickness, 320)
        XCTAssertEqual(controller.splitViewItems[1].minimumThickness, 380)
        XCTAssertEqual(controller.splitView.autosaveName, name + ".vertical")
    }

    func testSetupStatusesReflectActualFileAndEngineState() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CaptureModel(settingsStore: AppSettingsStore(root: root))
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.captureStatusText, "Listener stopped")
        XCTAssertTrue(model.allowLAN)
        XCTAssertEqual(model.lanStatusText, "LAN access enabled")
        model.allowLAN = false
        XCTAssertEqual(model.lanStatusText, "Localhost only")
        XCTAssertFalse(model.setMacProxy)
        XCTAssertEqual(model.macProxyStatusText, "Mac proxy not managed")
        model.recoveryNeeded = true
        XCTAssertEqual(model.macProxyStatusText, "Mac proxy recovery required")
        await model.refreshCATrust()
        XCTAssertEqual(model.caTrustStatus, MacCATrust.check(model.engine.paths.certificate))
        XCTAssertEqual(model.caStatusText, model.caTrustStatus.text)
    }

    func testSidebarHierarchicalStatsAndPathBreakdown() {
        let testModel = CaptureModel()
        XCTAssertEqual(testModel.sidebarSelection, .all)
        testModel.sidebarSelection = .domain("api.test")
        XCTAssertEqual(testModel.selectedHost, "api.test")
        testModel.sidebarSelection = .client("127.0.0.1")
        XCTAssertNil(testModel.selectedHost)
        testModel.selectedHost = "other.test"
        XCTAssertEqual(testModel.sidebarSelection, .domain("other.test"))
    }

    func testAppearanceSwitchUpdatesGutterAndContainer() {
        let container = JSONPreviewContainer(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            container.appearance = NSAppearance(named: appearance)
            container.viewDidChangeEffectiveAppearance()
            XCTAssertEqual(container.textView.backgroundColor, .textBackgroundColor)
        }
    }

    func testTrafficTableAccessibilityLabels() {
        let parent = TrafficTable(rows: [
            TrafficFlow(id: "f1", method: "POST", url: "https://api.test/checkout", host: "api.test",
                        status: 500, state: "error", started: 1, duration: 0.25, size: 50, error: "Gateway Timeout", number: 42, client: "127.0.0.1")
        ], selectedID: .constant("f1"))
        let coordinator = TrafficTable.Coordinator(parent: parent)
        coordinator.sourceRows = parent.rows
        let table = NSTableView()
        for id in ["id", "method", "status", "host", "path", "time", "size"] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            table.addTableColumn(col)
        }
        table.dataSource = coordinator
        table.delegate = coordinator
        coordinator.sortAndReload(table)

        let statusCol = table.tableColumns.first(where: { $0.identifier.rawValue == "status" })
        let statusCell = coordinator.tableView(table, viewFor: statusCol, row: 0) as? NSTableCellView
        XCTAssertEqual(statusCell?.textField?.stringValue, "500")
        XCTAssertEqual(statusCell?.textField?.accessibilityLabel(), "Status 500")

        let idCol = table.tableColumns.first(where: { $0.identifier.rawValue == "id" })
        let idCell = coordinator.tableView(table, viewFor: idCol, row: 0) as? NSTableCellView
        XCTAssertEqual(idCell?.textField?.stringValue, "42")
        XCTAssertEqual(idCell?.textField?.accessibilityLabel(), "Request 42")
    }
}
