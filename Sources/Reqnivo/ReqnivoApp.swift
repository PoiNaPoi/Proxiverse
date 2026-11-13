import AppKit
import SwiftUI

@main
struct ReqnivoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = CaptureModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1380, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Privacy & Authorized Use…") {
                    if let url = Bundle.main.resourceURL?.appendingPathComponent("Legal/PRIVACY.md"),
                       FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
                }
                Button("Licenses & Notices…") {
                    if let url = Bundle.main.resourceURL?.appendingPathComponent("Legal"),
                       FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
                }
                Button("Performance Baseline…") { model.showMetrics = true }
                Button("Capture Settings…") { model.showSetup = true }.keyboardShortcut(",")
                Button("Install Certificate…") { model.showCertificateInstaller = true }
            }
        }
        Window("Map Local", id: "map-local") { RulesView(model: model, kind: .mapLocal) }
            .windowResizability(.contentSize)
        Window("Breakpoint Rules", id: "breakpoint-rules") { RulesView(model: model, kind: .breakpoint) }
            .windowResizability(.contentSize)
        Window("Paused Traffic", id: "paused-traffic") { BreakpointsView(model: model) }
            .defaultSize(width: 1100, height: 760)
        Window("Install Certificate", id: "install-certificate") { DeviceCertificateView(model: model) }
            .windowResizability(.contentSize)
    }

}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: CaptureModel?
    private var terminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if let url = AppResources.bundle.url(forResource: "Reqnivo", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !terminating else { return .terminateNow }
        terminating = true
        Task {
            while model.busy { try? await Task.sleep(for: .milliseconds(100)) }
            await model.stop()
            if model.recoveryNeeded {
                let alert = NSAlert()
                alert.messageText = "Mac proxy recovery is still required"
                alert.informativeText = "Reqnivo could not restore the previous proxy settings. Keep the app open to retry, or review System Settings → Network → Proxies. The recovery record will remain available next launch."
                alert.addButton(withTitle: "Keep Open")
                alert.addButton(withTitle: "Quit Anyway")
                if alert.runModal() == .alertFirstButtonReturn {
                    terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            model.engine.discardCapture()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
