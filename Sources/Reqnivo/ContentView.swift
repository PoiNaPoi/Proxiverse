import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.openWindow) private var openWindow
    @State private var inspectorVisible = true
    @State private var columnResetRevision = 0
    @State private var showSearchHelp = false
    @FocusState private var searchFocused: Bool

    private var orderedHosts: [String] {
        model.hosts.filter { model.pinnedHosts.contains($0) } + model.hosts.filter { !model.pinnedHosts.contains($0) }
    }

    @ViewBuilder private func domainPinMenu(_ host: String) -> some View {
        Button(model.isHTTPSDecryptionEnabled(host) ? "Disable HTTPS Decryption" : "Enable HTTPS Decryption") {
            Task { await model.setHTTPSDecryption(host, enabled: !model.isHTTPSDecryptionEnabled(host)) }
        }.disabled(model.busy)
        Button(model.pinnedHosts.contains(host) ? "Unpin" : "Pin",
               systemImage: model.pinnedHosts.contains(host) ? "pin.slash" : "pin") {
            if model.pinnedHosts.contains(host) { model.pinnedHosts.remove(host) }
            else { model.pinnedHosts.insert(host) }
        }
    }

    private var scopeTitle: (title: String, icon: String) {
        switch model.sidebarSelection {
        case .all:
            return ("All Traffic", "network")
        case .domain(let host):
            return (host, "globe")
        case .domainPath(let host, let pathPrefix):
            return ("\(host) › \(pathPrefix)", "arrow.triangle.branch")
        case .client(let client):
            return ("Client: \(client)", "desktopcomputer")
        }
    }

    private var captureToolbar: some View {
        HStack(spacing: 6) {
            Button(action: model.toggle) {
                ToolbarLabel(model.busy ? "Please wait…" : (model.running ? "Stop" : "Start Capture"),
                      systemImage: model.running ? "stop.fill" : "record.circle")
                    .foregroundStyle(model.running ? Color.red : Color.accentColor)
            }
            .disabled(model.busy)
            .keyboardShortcut("r", modifiers: [.command])
            .help(model.running ? "Stop capture" : "Start capture")
            .accessibilityLabel(model.busy ? "Please wait" : (model.running ? "Stop capture" : "Start capture"))
            Button { model.clearDisplay() } label: { ToolbarLabel("Clear", systemImage: "trash") }
                .help("Clear Display")
                .accessibilityLabel("Clear display")
            Divider().frame(height: 30).padding(.horizontal, 6)
            Button { model.showMapLocalRules = true } label: { ToolbarLabel("Map Local", systemImage: "arrow.triangle.branch") }
                .accessibilityLabel("Map Local")
            Button { model.showBreakpoints = true } label: {
                ToolbarLabel(model.paused.isEmpty ? "Breakpoints" : "Breakpoints (\(model.paused.count))", systemImage: "pause.circle")
            }
            .accessibilityLabel(model.paused.isEmpty ? "Breakpoints" : "Breakpoints, \(model.paused.count) paused")
            Spacer(minLength: 12)
            Button { model.showHTTPSDecryption = true } label: { ToolbarLabel("HTTPS", systemImage: "lock.open") }
                .help("Choose domains to decrypt")
                .accessibilityLabel("HTTPS decryption")
            Button { model.showSetup = true } label: { ToolbarLabel("Settings", systemImage: "slider.horizontal.3") }
                .help("Capture Settings and device setup")
                .accessibilityLabel("Capture settings and device setup")
            Button { openWindow(id: "install-certificate") } label: { ToolbarLabel("Certificate", systemImage: "checkmark.seal") }
                .help("Install Certificate")
                .accessibilityLabel("Install certificate")
            Menu {
                Toggle("Inspector on Right", isOn: $model.inspectorOnRight)
                Toggle("Stack Request and Response", isOn: $model.messagesStacked)
                Button("Reset Traffic Columns") { columnResetRevision += 1 }
                Button("Focus Traffic Filter") { searchFocused = true }.keyboardShortcut("f")
            } label: {
                ToolbarLabel("Layout", systemImage: "rectangle.split.2x2")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Workspace Layout")
            .accessibilityLabel("Workspace layout")
        }
        .buttonStyle(ToolbarButtonStyle())
        .fixedSize()
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $model.sidebarSelection) {
                    Section("Capture") {
                        HStack {
                            Label("All Traffic", systemImage: "network")
                            Spacer()
                            Text(model.retainedCount.formatted()).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .tag(SidebarFilter.all)
                        .accessibilityLabel("All Traffic, \(model.retainedCount) requests")
                    }
                    if !model.hosts.isEmpty {
                        Section("Domains") {
                            ForEach(orderedHosts, id: \.self) { host in
                                let paths = model.hostPaths[host] ?? []
                                if paths.isEmpty {
                                    HStack {
                                        Label(host, systemImage: "globe").lineLimit(1)
                                        if model.pinnedHosts.contains(host) { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                                        Spacer()
                                        Text((model.hostCounts[host] ?? 0).formatted())
                                            .foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    .tag(SidebarFilter.domain(host))
                                    .help(host)
                                    .contextMenu { domainPinMenu(host) }
                                    .accessibilityLabel("Domain \(host), \(model.hostCounts[host] ?? 0) requests")
                                } else {
                                    DisclosureGroup {
                                        ForEach(paths) { item in
                                            HStack {
                                                Label(item.pathPrefix, systemImage: "arrow.turn.down.right").lineLimit(1)
                                                Spacer()
                                                Text(item.count.formatted())
                                                    .foregroundStyle(.secondary).monospacedDigit()
                                            }
                                            .tag(SidebarFilter.domainPath(host: host, pathPrefix: item.pathPrefix))
                                            .help("\(host)\(item.pathPrefix)")
                                            .accessibilityLabel("Path \(item.pathPrefix) on \(host), \(item.count) requests")
                                        }
                                    } label: {
                                        HStack {
                                            Label(host, systemImage: "globe").lineLimit(1)
                                            if model.pinnedHosts.contains(host) { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                                            Spacer()
                                            Text((model.hostCounts[host] ?? 0).formatted())
                                                .foregroundStyle(.secondary).monospacedDigit()
                                        }
                                        .tag(SidebarFilter.domain(host))
                                        .help(host)
                                        .contextMenu { domainPinMenu(host) }
                                        .accessibilityLabel("Domain \(host), \(model.hostCounts[host] ?? 0) requests")
                                    }
                                }
                            }
                        }
                    }
                    if !model.clients.isEmpty {
                        Section("Clients") {
                            ForEach(model.clients, id: \.self) { client in
                                HStack {
                                    Label(client, systemImage: client == "127.0.0.1" || client == "localhost" ? "desktopcomputer" : "laptopcomputer.and.ipad").lineLimit(1)
                                    Spacer()
                                    Text((model.clientCounts[client] ?? 0).formatted())
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }
                                .tag(SidebarFilter.client(client))
                                .help("Traffic from \(client)")
                                .accessibilityLabel("Client \(client), \(model.clientCounts[client] ?? 0) requests")
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.captureStatusText, systemImage: model.running ? "record.circle" : "stop.circle")
                        .accessibilityLabel("Capture engine: \(model.captureStatusText)")
                    Label(model.lanStatusText, systemImage: "wifi")
                        .accessibilityLabel("Network access: \(model.lanStatusText)")
                    ProxyConnectionView(port: model.proxyPort, allowLAN: model.allowLAN)
                    MacCaptureToggle(model: model)
                    Label(model.macProxyStatusText, systemImage: "desktopcomputer")
                        .accessibilityLabel("Mac system proxy: \(model.macProxyStatusText)")
                    Label(model.caStatusText, systemImage: model.caTrustStatus == .trusted ? "lock.shield" : "exclamationmark.shield")
                        .accessibilityLabel("CA certificate: \(model.caStatusText)")
                    Button("Set Up Capture & HTTPS…") { model.showSetup = true }
                        .buttonStyle(.link)
                        .help("Trust is checked on this Mac only. Phones, emulators, and apps with their own trust stores require separate CA setup.")
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Label(scopeTitle.title, systemImage: scopeTitle.icon)
                        .font(.headline).lineLimit(1)
                    Spacer()
                    Button { inspectorVisible.toggle() } label: {
                        Label(inspectorVisible && model.selectedID != nil ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
                    }
                    .disabled(model.selectedID == nil)
                    .help("Select a request to inspect its details")
                    Text("\(model.rows.count.formatted()) of \(model.retainedCount.formatted()) retained")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search traffic…", text: $model.search)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityLabel("Filter traffic")
                        .help("AND filters: host, path, method, status, type, state. Prefix - to exclude. Quote values containing spaces.")
                        .onSubmit { model.applySearch() }
                        .onExitCommand {
                            if !model.search.isEmpty { model.search = "" }
                            else { searchFocused = false }
                        }
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Clear traffic filter")
                    }
                    Button { showSearchHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Traffic search help")
                        .popover(isPresented: $showSearchHelp) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Search traffic").font(.headline)
                                Text("Combine text with filters, for example:")
                                Text("host:api.test method:GET status:400-499").monospaced()
                                Text("Use host, path, method, status, type or state. Filters use AND. Prefix - to exclude; quote values containing spaces.")
                            }.padding().frame(width: 360)
                        }
                }.padding(.horizontal, 14).padding(.vertical, 10)
                TrafficFilterControls(model: model)
                Divider()
                WorkspaceSplit(vertical: model.inspectorOnRight, autosaveName: "Reqnivo.Workspace",
                               firstMinimum: model.inspectorOnRight ? 320 : 180,
                               secondMinimum: model.inspectorOnRight ? 380 : 260,
                               secondCollapsed: model.selectedID == nil || !inspectorVisible) {
                    TrafficTable(rows: model.rows, selectedID: $model.selectedID,
                                 selectedIDs: model.selectedIDs, pinnedIDs: model.pinnedIDs,
                                 filterRevision: model.filterRevision, columnResetRevision: columnResetRevision,
                                 onSelection: model.selectTraffic, onSortChanged: model.updateTrafficSort,
                                 onPin: model.setPinned,
                                 onFilter: { _ = model.addFilter(field: $0, value: $1, excluded: $2) },
                                 canEditFilters: model.queryError == nil, onMapLocal: model.openMapLocal,
                                 onBreakpoint: model.openBreakpointRules,
                                 onReloaded: model.markTableReloaded)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            if model.rows.isEmpty {
                                ContentUnavailableView(model.retainedCount > 0 ? "No matching traffic" : (model.running ? "Waiting for requests" : "Your traffic, in view"),
                                                       systemImage: "network",
                                                       description: Text(model.retainedCount > 0 ? "Change the filter or select All Traffic." : (model.running ? "Route a browser or test device through port \(model.proxyPort)." : "Start capture, then tick Capture Mac Traffic or configure a client.")))
                                    .allowsHitTesting(false)
                            }
                        }
                } second: {
                    VStack(spacing: 0) {
                        if let flow = model.detail?.flow.summary, flow.tlsPassthrough == true {
                            EncryptedTrafficView(host: flow.host,
                                                 decryptionEnabled: model.isHTTPSDecryptionEnabled(flow.host),
                                                 busy: model.busy,
                                                 onEnable: { Task { await model.setHTTPSDecryption(flow.host, enabled: true) } },
                                                 onSettings: { model.showHTTPSDecryption = true })
                        } else {
                            InspectorView(detail: model.detail, loading: model.loadingDetail, messagesStacked: model.messagesStacked,
                                          onRendered: { model.markSelectionRendered(flowID: $0) })
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack(spacing: 12) {
                    Circle().fill(model.running ? .green : .secondary).frame(width: 7, height: 7)
                    Text(model.status).lineLimit(1)
                    Spacer()
                    Text("\(model.total.formatted()) captured")
                    Button { model.showMetrics = true } label: {
                        Text("RAM \(model.memory) · CPU \(model.cpu)").monospacedDigit()
                    }.buttonStyle(.plain).help("UI + engine process tree; CPU is a decaying average sampled by ps")
                    Text((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                         .map { "v\($0)" } ?? "Development build")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .frame(minWidth: 1050, minHeight: 700)
        .navigationTitle("Reqnivo")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                captureToolbar
            }
        }
        .sheet(isPresented: $model.showSetup) { SetupView(model: model) }
        .sheet(isPresented: $model.showHTTPSDecryption) { HTTPSDecryptionView(model: model) }
        .onChange(of: model.showCertificateInstaller) { _, show in
            if show { openWindow(id: "install-certificate"); model.showCertificateInstaller = false }
        }
        .onChange(of: model.showMapLocalRules) { _, show in
            if show { openWindow(id: "map-local"); model.showMapLocalRules = false }
        }
        .onChange(of: model.showBreakpoints) { _, show in
            if show { openWindow(id: "breakpoint-rules"); model.showBreakpoints = false }
        }
        .onChange(of: model.showPausedTraffic) { _, show in
            if show { openWindow(id: "paused-traffic"); model.showPausedTraffic = false }
        }
        .sheet(isPresented: $model.showMetrics) { MetricsView(model: model) }
        .alert("Reqnivo", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task {
            await model.startOnLaunch()
        }
    }
}

private struct ToolbarLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .frame(height: 18)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 72, height: 42)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(configuration.isPressed ? 0.12 : (isHovered && isEnabled ? 0.06 : 0)))
            }
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

private struct ProxyConnectionView: View {
    let port: Int
    let allowLAN: Bool
    @State private var addresses: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Proxy IP : Port").fontWeight(.medium)
            if allowLAN {
                ForEach(addresses, id: \.self) { address in
                    connectionRow(address)
                }
                if addresses.isEmpty {
                    Text("No LAN IP available").font(.caption2)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                addresses = DeviceCertificate.lanAddresses()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    private func connectionRow(_ address: String) -> some View {
        let endpoint = "\(address):\(port)"
        return HStack(spacing: 6) {
            Text(endpoint)
                .monospaced().textSelection(.enabled).lineLimit(1)
                .help("Connect from a device on the same network")
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(endpoint, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(endpoint)")
            .accessibilityLabel("Copy proxy address \(endpoint)")
        }
    }
}

struct InspectorView: View {
    let detail: InspectorDetail?
    let loading: Bool
    var messagesStacked = false
    var onRendered: (String) -> Void = { _ in }
    @State private var requestSection = 1
    @State private var responseSection = 1
    @State private var requestFoldedBody: String?
    @State private var requestCollapsed: Set<Int> = []
    @State private var responseFoldedBody: String?
    @State private var responseCollapsed: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let content = detail {
                let flowDetail = content.flow
                HStack {
                    if let number = flowDetail.summary.number {
                        Text("#\(number)").font(.caption.monospaced()).foregroundStyle(.secondary).help(flowDetail.summary.id)
                    }
                    Text(flowDetail.summary.method).font(.caption.bold()).foregroundStyle(.blue)
                    Text(flowDetail.summary.url).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                    Spacer()
                    ZStack {
                        if loading { ProgressView().controlSize(.mini) }
                    }.frame(width: 12, height: 12).help("Loading selected request…")
                    if let status = flowDetail.summary.status {
                        Text(String(status)).font(.caption.bold().monospacedDigit())
                            .foregroundStyle(status >= 400 ? .red : .green)
                    }
                }.padding(10)
                Divider()
                WorkspaceSplit(vertical: !messagesStacked, autosaveName: "Reqnivo.Messages",
                               firstMinimum: messagesStacked ? 100 : 170,
                               secondMinimum: messagesStacked ? 100 : 170) {
                    MessagePane(title: "Request", accent: .blue, message: flowDetail.request,
                                presentation: content.request, loading: loading, placeholder: "No request body",
                                onRendered: { onRendered(flowDetail.summary.id) },
                                section: $requestSection, foldedBody: $requestFoldedBody, collapsedRegions: $requestCollapsed)
                } second: {
                    MessagePane(title: "Response", accent: .green, message: flowDetail.response,
                                presentation: content.response, loading: loading,
                                placeholder: flowDetail.summary.error ?? "Waiting for response…",
                                onRendered: { onRendered(flowDetail.summary.id) },
                                section: $responseSection, foldedBody: $responseFoldedBody, collapsedRegions: $responseCollapsed)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Inspect a request", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Select a row to view request and response."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

private struct MessagePane: View {
    let title: String
    let accent: Color
    let message: FlowMessage?
    let presentation: MessagePresentation?
    let loading: Bool
    let placeholder: String
    var onRendered: () -> Void = {}
    @Binding var section: Int
    @State private var copied = false
    @Binding var foldedBody: String?
    @Binding var collapsedRegions: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title).font(.headline)
                Spacer()
                Button {
                    guard let presentation else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(presentation.copyText, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : copyLabel, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .font(.caption)
                .disabled(loading || presentation?.copyText.isEmpty != false || message?.streamed == true)
                .help("Copy the displayed body as plain text")
                .accessibilityLabel("Copy \(title.lowercased()) body")
            }.padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            Picker("\(title) content", selection: $section) {
                Text("Headers").tag(0)
                Text(presentation?.isJSON == true ? "JSON" : "Body").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.bottom, 10)
            Divider()
            if let message, let presentation {
                if section == 1 && (message.truncated || message.streamed) {
                    Label(message.streamed ? "Streamed body · preview unavailable" : "Preview limited to 256 KiB · incomplete body",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(8)
                }
                if section == 1 && message.body.isEmpty && !message.streamed {
                    Text(title == "Request" ? "No request body" : "No response body")
                        .font(.callout).foregroundStyle(.secondary).padding(12)
                    Spacer()
                } else {
                    PreviewText(content: section == 0 ? presentation.headers : presentation.body,
                                scrollsHorizontally: true,
                                accessibilityLabel: "\(title) \(section == 0 ? "headers" : "body")",
                                folds: section == 1 ? presentation.folds : [],
                                collapsed: Binding(
                                    get: { foldedBody == presentation.copyText ? collapsedRegions : [] },
                                    set: { foldedBody = presentation.copyText; collapsedRegions = $0 }
                                ),
                                onRendered: onRendered)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text(placeholder).font(.callout).foregroundStyle(.secondary).padding(12)
                Spacer()
            }
        }
        .frame(minWidth: 160, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: message) { previous, next in
            copied = false
            if previous?.body != next?.body {
                foldedBody = nil
                collapsedRegions = []
            }
        }
        .onChange(of: section) { _, _ in copied = false }
    }

    private var copyLabel: String {
        if message?.truncated == true { return "Copy Preview" }
        return presentation?.isJSON == true ? "Copy JSON" : "Copy Body"
    }
}

struct PreviewText: NSViewRepresentable {
    let content: NSAttributedString
    var scrollsHorizontally = false
    var accessibilityLabel: String? = nil
    var folds: [JSONFoldRegion] = []
    var collapsed: Binding<Set<Int>>? = nil
    var onRendered: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> JSONPreviewContainer {
        let container = JSONPreviewContainer(frame: .zero)
        let scroll = container.scrollView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        let view = container.textView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.backgroundColor = .textBackgroundColor
        if let accessibilityLabel {
            view.setAccessibilityLabel(accessibilityLabel)
        }
        scroll.documentView = view
        let gutter = container.gutter
        gutter.onToggle = { [weak coordinator = context.coordinator] id in coordinator?.toggle(id) }
        context.coordinator.gutter = gutter
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak gutter] _ in gutter?.needsLayout = true }
        return container
    }

    func updateNSView(_ view: JSONPreviewContainer, context: Context) {
        if let accessibilityLabel {
            view.textView.setAccessibilityLabel(accessibilityLabel)
        }
        context.coordinator.parent = self
        context.coordinator.update(view)
    }

    final class Coordinator {
        var parent: PreviewText
        weak var gutter: JSONFoldGutter?
        var observer: NSObjectProtocol?
        private var source: NSAttributedString?
        private var regions: [JSONFoldRegion] = []
        private var collapsed: Set<Int> = []

        init(parent: PreviewText) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        func toggle(_ id: Int) {
            guard let binding = parent.collapsed else { return }
            var next = binding.wrappedValue
            if !next.insert(id).inserted { next.remove(id) }
            binding.wrappedValue = next
        }

        func update(_ container: JSONPreviewContainer) {
            let scroll = container.scrollView
            let textView = container.textView
            let horizontal = parent.scrollsHorizontally
            scroll.hasHorizontalScroller = horizontal
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = horizontal
            textView.autoresizingMask = horizontal ? [] : [.width]
            textView.textContainer?.widthTracksTextView = !horizontal
            textView.textContainer?.containerSize = NSSize(
                width: horizontal ? .greatestFiniteMagnitude : scroll.contentSize.width,
                height: .greatestFiniteMagnitude)
            let nextCollapsed = parent.collapsed?.wrappedValue ?? []
            let changedDocument = source?.isEqual(to: parent.content) != true
            guard changedDocument || regions != parent.folds || collapsed != nextCollapsed else {
                parent.onRendered?()
                return
            }
            source = parent.content
            regions = parent.folds
            collapsed = nextCollapsed
            let display = JSONFolding.display(parent.content, regions: regions, collapsed: collapsed)
            let position = scroll.contentView.bounds.origin
            textView.textStorage?.setAttributedString(display.content)
            textView.sizeToFit()
            container.setFoldControls(display.controls)
            if changedDocument { textView.scrollToBeginningOfDocument(nil) }
            else {
                scroll.contentView.scroll(to: position)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            gutter?.needsLayout = true
            // Force glyph generation/layout so selection-to-render includes real text layout cost.
            if let manager = textView.layoutManager, let textContainer = textView.textContainer {
                manager.ensureLayout(for: textContainer)
            }
            parent.onRendered?()
        }
    }
}

struct MacCaptureToggle: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        Toggle("Capture Mac Traffic", isOn: Binding(
            get: { model.setMacProxy },
            set: { enabled in Task { await model.setMacCaptureEnabled(enabled) } }
        ))
        .toggleStyle(.checkbox)
        .disabled(model.busy || model.ruleOperation || model.recoveryNeeded)
        .help("Capture HTTP/HTTPS from apps using the selected Mac network service (\(model.service)). Changes require administrator approval. HTTPS requires trusting the Reqnivo CA. When stopped, applies on the next capture start.")
    }
}

struct SetupView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var showHTTPSDecryption = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture Settings").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Get started") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("1. Connect your client").font(.headline)
                            Text("For this Mac, enable Capture Mac Traffic. For a phone or emulator, allow local network access below and configure its proxy to this Mac’s LAN IP and port \(model.proxyPort).")
                            Text("2. Install and trust the certificate").font(.headline)
                            Button("Install Certificate on Mac / Device…") { dismiss(); openWindow(id: "install-certificate") }
                            Text("3. Choose HTTPS domains").font(.headline)
                            Text("Only selected domains are decrypted. Other HTTPS connections remain encrypted.")
                            Button("Choose Domains…") { showHTTPSDecryption = true }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    Form {
                        TextField("Proxy port", value: $model.proxyPort, format: .number.grouping(.never))
                        TextField("Control port (localhost only)", value: $model.apiPort, format: .number.grouping(.never))
                        Toggle("Allow test devices on local network", isOn: $model.allowLAN)
                        Picker("Mac network service", selection: $model.service) {
                            ForEach(model.services, id: \.self) { Text($0).tag($0) }
                        }.disabled(!model.setMacProxy)
                    }.disabled(model.running || model.busy)
                    MacCaptureToggle(model: model)
                    Group {
                        Text("Upstream HTTPS").font(.headline)
                        Toggle("Skip server certificate verification (debug only)", isOn: $model.skipUpstreamVerification)
                            .disabled(model.running || model.busy)
                        if model.skipUpstreamVerification {
                            Text("Server certificate and hostname checks will be skipped for all HTTPS hosts in this capture. A custom CA is not required. Enabled by default on each app launch. Changes apply on the next capture start.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("Organization CA").font(.subheadline)
                        Text(model.hasUpstreamCA ? "Custom CA bundle installed" : "Using standard trusted CAs")
                            .font(.callout)
                        HStack {
                            Button(model.hasUpstreamCA ? "Replace CA File…" : "Choose CA File…", action: model.chooseUpstreamCA)
                            if model.hasUpstreamCA { Button("Remove Custom CA", action: model.removeUpstreamCA) }
                        }.disabled(model.running || model.busy || model.skipUpstreamVerification)
                        Text("Select a PEM CA bundle provided by your organization. It is added to the standard CAs for server verification. Certificate and hostname checks stay enabled when the skip option is off. Stop capture before changing it; changes apply on the next start.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Mac proxy changes require administrator approval. Stop restores the previous settings. A saved recovery record is checked on the next launch after an unexpected exit.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.recoveryNeeded {
                        Button("Restore Mac Proxy", action: model.restoreProxy).disabled(model.busy)
                    }
                    Divider()
                    Text("Device trust notes").font(.headline)
                    Text("Start capture once to create this Mac’s CA. On iOS, enable full trust in Certificate Trust Settings. Android/debug apps must trust the CA separately; disable pinning only in the debug build.")
                        .font(.callout).textSelection(.enabled)
                    HStack {
                        Button("Show Public CA Certificate", action: model.openCertificate)
                        Button("Open Setup Guide") {
                            if let url = URL(string: "https://docs.mitmproxy.org/stable/concepts/certificates/") { NSWorkspace.shared.open(url) }
                        }
                    }
                    Text("CA private keys stay on this Mac. Body previews are temporary (128 MiB disk budget), capped at 256 KiB; bodies over 1 MiB are streamed. Compressed/binary previews are omitted in this baseline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600, height: 650)
        .sheet(isPresented: $showHTTPSDecryption) { HTTPSDecryptionView(model: model) }
    }
}

struct MetricsView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss

    private static func percentiles(_ samples: LatencySamples, target: Double) -> String {
        guard samples.count > 0 else { return "no samples yet" }
        return String(format: "%.1f / %.1f ms (n=%d, target p95 ≤ %.0f)", samples.percentile(0.5), samples.percentile(0.95),
                      samples.totalCount, target)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Performance Baseline").font(.title2.bold())
            Group {
                LabeledContent("UI RSS · CPU", value: String(format: "%.0f MB · %.1f%%", model.usage.uiMB, model.usage.uiCPU))
                LabeledContent("Engine RSS · CPU", value: String(format: "%.0f MB · %.1f%%", model.usage.engineMB, model.usage.engineCPU))
                LabeledContent("Preview storage", value: "\(ByteCountFormatter.string(fromByteCount: Int64(model.previewDiskBytes), countStyle: .binary)) · \(model.retainedPreviewFiles.formatted()) files")
                LabeledContent("UI + engine RSS (total)", value: model.memory)
                LabeledContent("Captured requests", value: model.total.formatted())
            }
            Divider()
            Group {
                LabeledContent("Last batch apply", value: String(format: "%.2f ms", model.lastBatchMilliseconds))
                LabeledContent("Filter, model only (last)", value: String(format: "%.2f ms", model.filterMilliseconds))
                LabeledContent("Filter end-to-end p50 / p95", value: Self.percentiles(model.filterEndToEndSamples, target: 100))
                LabeledContent("Detail fetch + prepare (last)", value: String(format: "%.2f ms", model.detailMilliseconds))
                LabeledContent("Selection-to-render p50 / p95", value: Self.percentiles(model.selectionRenderSamples, target: 250))
            }
            Text("RSS includes the UI and engine descendants and may double count shared pages. CPU comes from ps as a decaying average. Selection-to-render ends when text layout finishes in every visible inspector pane; filter end-to-end ends when the table finishes reloading. Neither measures scroll/frame hitches — use Instruments for those.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Initial targets (to be confirmed against the baseline): p95 filter ≤ 100 ms at 10,000 rows, p95 selection-to-render ≤ 250 ms for previews ≤ 256 KiB. Workload: 1–2 clients, 10 requests/second, 10,000 retained rows.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Export Snapshot…", action: model.exportMetrics)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
    }
}
