import AppKit
import Combine

struct SidebarPathItem: Hashable, Identifiable {
    let pathPrefix: String
    let count: Int
    var id: String { pathPrefix }
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published var rows: [TrafficFlow] = []
    @Published var hosts: [String] = []
    @Published private(set) var hostCounts: [String: Int] = [:]
    @Published private(set) var hostPaths: [String: [SidebarPathItem]] = [:]
    @Published private(set) var clients: [String] = []
    @Published private(set) var clientCounts: [String: Int] = [:]
    @Published private(set) var retainedCount = 0
    @Published var selectedID: String? {
        didSet {
            if let selectedID {
                if !selectedIDs.contains(selectedID) { selectedIDs = [selectedID] }
            } else { selectedIDs = [] }
            if oldValue != selectedID {
                pendingRender = selectedID.map { PendingRender(id: $0, started: CFAbsoluteTimeGetCurrent(), detailReady: nil) }
                loadSelection()
            }
        }
    }
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var pinnedIDs: Set<String> = []
    @Published private(set) var filterRevision = 0
    @Published private(set) var queryError: String?
    @Published private(set) var effectiveQuery = TrafficQuery()
    @Published private(set) var savedFilters: [SavedTrafficFilter] = []
    @Published private(set) var activeSavedFilterID: String?
    private var savedFilterLoadFailed = false
    private let savedFilterStore: SavedTrafficFilterStore
    private var trafficSort = TrafficSort(column: .number, ascending: false)
    @Published var sidebarSelection: SidebarFilter = .all {
        didSet {
            switch sidebarSelection {
            case .domain(let host):
                if selectedHost != host { selectedHost = host }
            case .domainPath(let host, _):
                if selectedHost != host { selectedHost = host }
            default:
                if selectedHost != nil { selectedHost = nil }
            }
            rebuildRows(userInitiated: true)
        }
    }
    @Published var selectedHost: String? {
        didSet {
            if case .domain(let current) = sidebarSelection, current == selectedHost { return }
            if case .domainPath(let current, _) = sidebarSelection, current == selectedHost { return }
            if selectedHost == nil {
                if case .domain = sidebarSelection { sidebarSelection = .all }
                else if case .domainPath = sidebarSelection { sidebarSelection = .all }
            } else if let selectedHost {
                sidebarSelection = .domain(selectedHost)
            }
            rebuildRows(userInitiated: true)
        }
    }
    @Published var detail: InspectorDetail?
    @Published private(set) var loadingDetail = false
    @Published var search = "" {
        didSet {
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                applySearch()
            }
        }
    }
    @Published var running = false
    @Published var busy = false
    @Published var status = "Ready to capture"
    @Published var error: String?
    private let settingsStore: AppSettingsStore
    private var settingsReady = false
    @Published private var settings = AppSettings() {
        didSet {
            guard settingsReady else { return }
            do { try settingsStore.save(settings) }
            catch { self.error = "Could not save settings: \(error.localizedDescription)" }
        }
    }
    var proxyPort: Int {
        get { settings.proxyPort }
        set { settings.proxyPort = newValue }
    }
    var apiPort: Int {
        get { settings.apiPort }
        set { settings.apiPort = newValue }
    }
    @Published private(set) var caTrustStatus = MacCATrustStatus.checking
    var skipUpstreamVerification: Bool {
        get { settings.skipUpstreamVerification }
        set { settings.skipUpstreamVerification = newValue }
    }
    @Published private(set) var hasUpstreamCA = false
    var upstreamCAStore: UpstreamCAStore { UpstreamCAStore(root: engine.paths.root) }
    @Published var lanDevices: [LANDevice] = []
    @Published private(set) var lanApprovalBusy = false
    func setLANDeviceApproval(_ device: LANDevice, approved: Bool) async {
        guard running, !busy, !lanApprovalBusy, let api = engine.api else { return }
        lanApprovalBusy = true
        defer { lanApprovalBusy = false }
        do {
            let updated = try JSONDecoder().decode([LANDevice].self, from: await api.request(
                "/lan-devices", method: "POST", body: JSONEncoder().encode(LANDevice(ip: device.ip, approved: approved))))
            guard running, engine.api === api else { return }
            lanDevices = updated
        } catch {
            if engine.api === api { self.error = error.localizedDescription }
        }
    }

    var allowLAN: Bool {
        get { settings.allowLAN }
        set { settings.allowLAN = newValue }
    }
    var setMacProxy: Bool {
        get { settings.setMacProxy }
        set { settings.setMacProxy = newValue }
    }
    var pinnedHosts: Set<String> {
        get { settings.pinnedHosts }
        set { settings.pinnedHosts = newValue }
    }
    var inspectorOnRight: Bool {
        get { settings.inspectorOnRight }
        set { settings.inspectorOnRight = newValue }
    }
    var messagesStacked: Bool {
        get { settings.messagesStacked }
        set { settings.messagesStacked = newValue }
    }
    @Published var showHTTPSDecryption = false
    var httpsDecryptionHosts: [String: Bool] { settings.httpsDecryptionHosts ?? [:] }
    var availableHTTPSHosts: [String] { httpsDecryptionHosts.keys.sorted() }

    func isHTTPSDecryptionEnabled(_ host: String) -> Bool {
        guard let normalized = try? HTTPSDecryption.normalizedHost(host) else { return false }
        return httpsDecryptionHosts[normalized] == true
    }

    func setHTTPSDecryption(_ host: String, enabled: Bool) async {
        await updateHTTPSDecryption(host, enabled: enabled)
    }

    func removeHTTPSDecryption(_ host: String) async {
        await updateHTTPSDecryption(host, enabled: nil)
    }

    private func updateHTTPSDecryption(_ host: String, enabled: Bool?) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let host = try HTTPSDecryption.normalizedHost(host)
            var updated = httpsDecryptionHosts
            guard enabled != false || updated[host] != nil else { return }
            updated[host] = enabled
            if let api = engine.api {
                let enabledHosts = updated.filter { $0.value }.map(\.key).sorted()
                _ = try await api.request("/https-decryption", method: "POST", body: JSONEncoder().encode(enabledHosts))
            }
            settings.httpsDecryptionHosts = updated
        } catch { self.error = error.localizedDescription }
    }
    @Published var services: [String] = []
    var service: String {
        get { settings.service }
        set { settings.service = newValue }
    }
    @Published var recoveryNeeded = false
    @Published var total = 0
    @Published var memory = "—"
    @Published var cpu = "—"
    @Published var lastBatchMilliseconds = 0.0
    @Published var detailMilliseconds = 0.0
    @Published var filterMilliseconds = 0.0
    @Published var enginePID: Int32 = 0
    @Published private(set) var usage = ResourceUsage()
    @Published private(set) var previewDiskBytes = 0
    @Published private(set) var retainedPreviewFiles = 0
    @Published private(set) var selectionRenderSamples = LatencySamples()
    @Published private(set) var selectionToDetailSamples = LatencySamples()
    @Published private(set) var detailToRenderSamples = LatencySamples()
    @Published private(set) var filterEndToEndSamples = LatencySamples()
    @Published private(set) var filterModelSamples = LatencySamples()
    @Published private(set) var benchmarkComplete = false
    private struct PendingRender { let id: String; let started: Double; var detailReady: Double?; var panes = 0 }
    private var pendingRender: PendingRender?
    private var pendingFilterStart: Double?
    private var benchmarkStarted = false
    private var benchmarkTimeouts = 0
    private let benchmarkExpectedFlows: Int? = CaptureModel.argument("--benchmark-expected-flows").flatMap(Int.init)
    @Published var showSetup = false
    @Published var showCertificateInstaller = false
    @Published var showMetrics = false
    @Published var showMapLocalRules = false
    @Published var pendingMapLocal: MapLocalPrefill?
    @Published var showBreakpoints = false
    @Published var pendingBreakpoint: DebugRule?
    @Published var rules: [DebugRule] = []
    @Published var paused: [TrafficFlow] = []
    @Published var showPausedTraffic = false
    @Published var selectedBreakpoint: String?
    @Published var breakpointDrafts: [String: BreakpointDraft] = [:]
    @Published var breakpointErrors: [String: String] = [:]
    @Published var breakpointNotice: String?
    @Published var breakpointLoads: [String: UUID] = [:]
    var seenBreakpoints: Set<String> = []
    var completedBreakpoints: Set<String> = []
    var breakpointLoader: ((String) async throws -> PausedEdit)?
    var breakpointResumer: ((PausedEdit) async throws -> Void)?
    @Published var ruleOperation = false
    private var didLaunch = false
    let engine = EngineRuntime()
    var ruleStore: RuleStore { RuleStore(root: engine.paths.root) }
    private var buffer = TrafficBuffer()
    private var pollTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var cursor = 0
    private let detailLoader: ((String) async throws -> FlowDetail)?
    private let caTrustCheck: @Sendable (URL) -> MacCATrustStatus
    private let macProxyChange: ((Bool) async throws -> Void)?

    init(detailLoader: ((String) async throws -> FlowDetail)? = nil, savedFilterStore: SavedTrafficFilterStore? = nil,
         macProxyChange: ((Bool) async throws -> Void)? = nil,
         settingsStore: AppSettingsStore? = nil,
         caTrustCheck: @escaping @Sendable (URL) -> MacCATrustStatus = { MacCATrust.check($0) }) {
        self.caTrustCheck = caTrustCheck
        self.macProxyChange = macProxyChange
        self.detailLoader = detailLoader
        self.savedFilterStore = savedFilterStore ?? SavedTrafficFilterStore(root: RuntimePaths().root)
        self.settingsStore = settingsStore ?? AppSettingsStore(root: RuntimePaths().root)
        do {
            if let saved = try self.settingsStore.load() {
                settings = saved
            } else {
                settings.inspectorOnRight = UserDefaults.standard.bool(forKey: "workspace.inspectorOnRight")
                settings.messagesStacked = UserDefaults.standard.bool(forKey: "workspace.messagesStacked")
            }
            settingsReady = true
        } catch { self.error = "Could not load settings: \(error.localizedDescription). The existing file will not be overwritten." }
        if let port = Self.environmentPort("REQNIVO_PROXY_PORT") { settings.proxyPort = port }
        if let port = Self.environmentPort("REQNIVO_API_PORT") { settings.apiPort = port }
        do { savedFilters = try self.savedFilterStore.load() }
        catch {
            savedFilterLoadFailed = true
            self.error = "Could not load saved filters: \(error.localizedDescription)"
        }
        do { rules = try ruleStore.load() }
        catch { self.error = "Could not load saved rules: \(error.localizedDescription)" }
        hasUpstreamCA = upstreamCAStore.isConfigured
        services = (try? SystemProxy.services()) ?? []
        if !services.contains(service) {
            service = services.contains("Wi-Fi") ? "Wi-Fi" : (services.first ?? "")
        }
        if settingsReady {
            do { try self.settingsStore.save(settings) }
            catch { self.error = "Could not save settings: \(error.localizedDescription)" }
        }
        recoveryNeeded = FileManager.default.fileExists(atPath: SystemProxy.journalURL(engine.paths).path)
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCATrust()
                let uiPID = ProcessInfo.processInfo.processIdentifier
                let enginePID = self.enginePID
                if let usage = await Task.detached(priority: .utility, operation: { Self.sample(uiPID: uiPID, enginePID: enginePID) }).value {
                    self.usage = usage
                    self.memory = String(format: "%.0f MB", usage.totalMB)
                    self.cpu = String(format: "%.1f%%", usage.totalCPU)
                } else {
                    self.memory = "—"
                    self.cpu = "—"
                }
                if let api = self.engine.api, let health = try? await api.get("/health", as: EngineHealth.self) {
                    self.previewDiskBytes = health.previewBytes ?? 0
                    self.retainedPreviewFiles = health.retained
                }
                self.writeBenchmarkMetricsIfRequested()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func chooseUpstreamCA() {
        guard !running, !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Organization CA (PEM)"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try upstreamCAStore.install(from: url)
            hasUpstreamCA = true
        } catch { self.error = error.localizedDescription }
    }

    func removeUpstreamCA() {
        guard !running, !busy else { return }
        do {
            try upstreamCAStore.remove()
            hasUpstreamCA = false
        } catch { self.error = error.localizedDescription }
    }

    func startOnLaunch() async {
        guard !didLaunch else { return }
        didLaunch = true
        await start()
    }

    func openBreakpointRules(_ flow: TrafficFlow) {
        pendingBreakpoint = DebugRule.breakpoint(from: flow)
        showBreakpoints = true
    }

    func openMapLocal(_ flow: TrafficFlow) {
        Task {
            do {
                let captured = try await readDetail(id: flow.id)
                pendingMapLocal = MapLocalPrefill.captured(captured.summary, response: captured.response)
            } catch {
                var prefill = MapLocalPrefill.captured(flow, response: nil)
                prefill.notice = "Could not load captured headers/body: \(error.localizedDescription). Matching fields are filled from the clicked row; enter the response manually."
                pendingMapLocal = prefill
            }
            showMapLocalRules = true
        }
    }

    private(set) var ruleSaveError: String?

    func saveRules(_ draft: [DebugRule], inlineBodies: [String: String] = [:], reportError: Bool = true) async -> Bool {
        guard !ruleOperation, !busy else { return false }
        ruleOperation = true
        ruleSaveError = nil
        defer { ruleOperation = false }
        do {
            let store = ruleStore
            let prepared = try await Task.detached {
                try store.prepareRules(draft, inlineBodies: inlineBodies)
            }.value
            if let api = engine.api {
                _ = try await api.request("/rules", method: "POST", body: JSONEncoder().encode(prepared))
            } else {
                try ruleStore.save(prepared)
            }
            rules = prepared
            return true
        } catch {
            ruleSaveError = error.localizedDescription
            if reportError { self.error = error.localizedDescription }
            return false
        }
    }

    func toggle() {
        Task { if running { await stop() } else { await start() } }
    }

    func setMacCaptureEnabled(_ enabled: Bool) async {
        guard !busy, !ruleOperation, !recoveryNeeded, enabled != setMacProxy else { return }
        guard running else {
            setMacProxy = enabled
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await changeMacProxy(enabled)
            setMacProxy = enabled
        } catch {
            self.error = error.localizedDescription
            recoveryNeeded = FileManager.default.fileExists(atPath: SystemProxy.journalURL(engine.paths).path)
        }
    }

    private func changeMacProxy(_ enabled: Bool) async throws {
        if enabled && service.isEmpty { throw AppFailure("Select a Mac network service in Capture Settings") }
        if let macProxyChange {
            try await macProxyChange(enabled)
            return
        }
        let paths = engine.paths
        let selectedService = service
        let port = proxyPort
        try await Task.detached {
            if enabled { try SystemProxy.enable(service: selectedService, port: port, paths: paths) }
            else { try SystemProxy.restore(paths: paths) }
        }.value
    }

    func start() async {
        guard !busy, !ruleOperation, !running else { return }
        busy = true
        defer { busy = false }
        do {
            if recoveryNeeded { throw AppFailure("Restore Mac Proxy before starting a new capture") }
            status = "Starting engine…"
            engine.discardCapture()
            buffer = TrafficBuffer()
            cursor = 0
            rows = []
            hosts = []
            hostCounts = [:]
            hostPaths = [:]
            clients = []
            clientCounts = [:]
            retainedCount = 0
            total = 0
            detail = nil
            selectedID = nil
            selectedIDs = []
            pinnedIDs = []
            lanDevices = []
            if allowLAN {
                guard settingsReady else { throw AppFailure("Repair the settings file before starting LAN capture") }
                try settingsStore.save(settings)
            }
            try await engine.start(proxyPort: proxyPort, apiPort: apiPort, lan: allowLAN,
                                   skipUpstreamVerification: skipUpstreamVerification,
                                   httpsDecryptionHosts: httpsDecryptionHosts.filter { $0.value }.map(\.key).sorted())
            enginePID = engine.process?.processIdentifier ?? 0
            if setMacProxy {
                status = "Setting Mac proxy…"
                try await changeMacProxy(true)
            }
            running = true
            status = "Capturing on \(allowLAN ? "LAN" : "localhost"):\(proxyPort)"
            if skipUpstreamVerification { status += " · server certificate checks skipped" }
            pollTask = Task { [weak self] in await self?.poll() }
        } catch {
            self.error = error.localizedDescription
            await engine.stop()
            enginePID = 0
            recoveryNeeded = FileManager.default.fileExists(atPath: SystemProxy.journalURL(engine.paths).path)
            status = "Capture failed"
        }
    }

    func stop() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        status = "Stopping…"
        pollTask?.cancel()
        pollTask = nil
        do {
            try await changeMacProxy(false)
        } catch { self.error = error.localizedDescription }
        recoveryNeeded = FileManager.default.fileExists(atPath: SystemProxy.journalURL(engine.paths).path)
        await engine.stop()
        lanDevices = []
        if let directory = engine.captureDirectory {
            let finished = paused.compactMap { flow -> FlowEvent? in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent(flow.id + ".json")),
                      let detail = try? JSONDecoder().decode(FlowDetail.self, from: data) else { return nil }
                return FlowEvent(sequence: 0, flow: detail.summary)
            }
            buffer.apply(finished)
            rebuildRows()
            loadSelection()
        }
        enginePID = 0
        running = false
        updatePausedTraffic([])
        seenBreakpoints = []
        completedBreakpoints = []
        showPausedTraffic = false
        breakpointNotice = "Capture stopped. Paused requests were cancelled."
        status = recoveryNeeded ? "Stopped · proxy recovery required" : "Stopped · capture previews available until next start"
    }

    func restoreProxy() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await changeMacProxy(false)
                if running { setMacProxy = false }
                recoveryNeeded = false
            } catch { self.error = error.localizedDescription }
        }
    }

    private func poll() async {
        var failures = 0
        while !Task.isCancelled, let api = engine.api {
            do {
                if allowLAN {
                    let devices = try await api.get("/lan-devices", as: [LANDevice].self)
                    guard !Task.isCancelled, engine.api === api else { return }
                    if devices != lanDevices { lanDevices = devices }
                }
                let waiting = try await api.get("/paused", as: [TrafficFlow].self)
                guard !Task.isCancelled else { return }
                // A serial engine poll has now observed which completed phases have disappeared.
                completedBreakpoints.formIntersection(Set(waiting.map(\.breakpointKey)))
                updatePausedTraffic(waiting)
                let batch = try await api.get("/events?after=\(cursor)", as: EventBatch.self)
                guard !Task.isCancelled else { return }
                let began = CFAbsoluteTimeGetCurrent()
                if batch.gap { status = "Capture updates were skipped; showing retained recent events" }
                cursor = batch.cursor
                total = batch.total
                if !batch.events.isEmpty {
                    buffer.apply(batch.events)
                    rebuildRows()
                    if let selectedID, batch.events.contains(where: { $0.flow.id == selectedID }) { loadSelection() }
                } else if let expected = benchmarkExpectedFlows, !benchmarkStarted, total >= expected {
                    benchmarkStarted = true
                    Task { [weak self] in await self?.runBenchmark() }
                }
                lastBatchMilliseconds = (CFAbsoluteTimeGetCurrent() - began) * 1000
                failures = 0
                try await Task.sleep(for: .milliseconds(batch.events.count == 1000 ? 10 : 250))
            } catch {
                if Task.isCancelled { return }
                failures += 1
                if failures >= 3 {
                    self.error = "Lost contact with the capture engine. \(error.localizedDescription)"
                    await stop()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    var caCertificateExists: Bool {
        FileManager.default.fileExists(atPath: engine.paths.certificate.path)
    }

    var captureStatusText: String {
        running ? "Listening on port \(proxyPort)" : "Listener stopped"
    }

    var lanStatusText: String {
        allowLAN ? "LAN access enabled" : "Localhost only"
    }

    var macProxyStatusText: String {
        if recoveryNeeded { return "Mac proxy recovery required" }
        if running && setMacProxy { return "Mac proxy configured" }
        return "Mac proxy not managed"
    }

    func refreshCATrust() async {
        let certificate = engine.paths.certificate
        let check = caTrustCheck
        caTrustStatus = await Task.detached(priority: .utility) { check(certificate) }.value
    }

    var caStatusText: String {
        caTrustStatus.text
    }

    func applySearch() {
        searchTask?.cancel()
        do {
            let query = try TrafficQuery.parse(search)
            queryError = nil
            effectiveQuery = query
            rebuildRows(userInitiated: true)
        } catch { queryError = error.localizedDescription }
    }

    func editQuery(_ change: (inout TrafficQuery) -> Void) {
        guard queryError == nil else { return }
        do {
            var query = try TrafficQuery.parse(search)
            guard query == effectiveQuery else { applySearch(); return }
            change(&query)
            search = query.text
            applySearch()
        } catch { queryError = error.localizedDescription }
    }

    @discardableResult
    func addFilter(field: TrafficQuery.Field, value: String, excluded: Bool = false) -> Bool {
        let term: TrafficQuery.Term
        do { term = try TrafficQuery.Term(field: field, value: value, excluded: excluded) }
        catch { self.error = "Could not add filter: \(error.localizedDescription)"; return false }
        do {
            var query = try TrafficQuery.parse(search)
            query.terms.append(term)
            search = query.text
            applySearch()
            return true
        } catch { queryError = error.localizedDescription; return false }
    }

    var savedFilterModified: Bool {
        guard let entry = savedFilters.first(where: { $0.id == activeSavedFilterID }) else { return false }
        return entry.query != search || entry.scope != sidebarSelection
    }

    func applySavedFilter(_ entry: SavedTrafficFilter) {
        search = entry.query
        applySearch()
        sidebarSelection = entry.scope
        activeSavedFilterID = entry.id
    }

    @discardableResult
    func saveFilter(name: String, replacingID: String? = nil) -> Bool {
        applySearch()
        guard queryError == nil else { return false }
        var entries = savedFilters
        let entry = SavedTrafficFilter(id: replacingID ?? UUID().uuidString,
                                       name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                       query: search, scope: sidebarSelection)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
        else { entries.append(entry) }
        guard persistFilters(entries) else { return false }
        activeSavedFilterID = entry.id
        return true
    }

    func renameFilter(_ entry: SavedTrafficFilter, name: String) {
        var entries = savedFilters
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = persistFilters(entries)
    }

    func deleteFilter(_ entry: SavedTrafficFilter) {
        if persistFilters(savedFilters.filter { $0.id != entry.id }), activeSavedFilterID == entry.id {
            activeSavedFilterID = nil
        }
    }

    private func persistFilters(_ entries: [SavedTrafficFilter]) -> Bool {
        do {
            guard !savedFilterLoadFailed else {
                throw AppFailure("Saved filters could not be loaded. Repair the saved filter file and relaunch before saving; the existing file has not been overwritten.")
            }
            try savedFilterStore.save(entries)
            savedFilters = entries
            return true
        } catch { self.error = "Could not save filters: \(error.localizedDescription)"; return false }
    }

    func selectTraffic(_ ids: Set<String>, primary: String?) {
        let retained = ids.intersection(Set(buffer.rows.map(\.id)))
        selectedIDs = retained
        selectedID = primary.flatMap { retained.contains($0) ? $0 : nil } ??
            fallbackPrimary(in: retained)
    }

    func updateTrafficSort(_ sort: TrafficSort) {
        trafficSort = sort
    }

    private func fallbackPrimary(in ids: Set<String>) -> String? {
        let visible = trafficSort.sorted(rows.filter { ids.contains($0.id) })
        return visible.first(where: { pinnedIDs.contains($0.id) })?.id ?? visible.first?.id ??
            buffer.rows.first(where: { ids.contains($0.id) })?.id
    }

    func setPinned(_ ids: Set<String>, pinned: Bool) {
        let retained = Set(buffer.rows.map(\.id))
        if pinned { pinnedIDs.formUnion(ids.intersection(retained)) }
        else { pinnedIDs.subtract(ids) }
        filterRevision += 1
    }

    var hiddenSelectionCount: Int { selectedIDs.subtracting(Set(rows.map(\.id))).count }

    func applyTrafficEvents(_ events: [FlowEvent]) {
        buffer.apply(events)
        rebuildRows()
    }

    private func rebuildRows(userInitiated: Bool = false) {
        let began = CFAbsoluteTimeGetCurrent()
        // Completed by TrafficTable once the table has applied rows (see markTableReloaded).
        if userInitiated {
            pendingFilterStart = began
            filterRevision += 1
        }
        rows = buffer.filtered(query: effectiveQuery, sidebar: sidebarSelection)
        if !userInitiated { refreshRetainedState() }
        filterMilliseconds = (CFAbsoluteTimeGetCurrent() - began) * 1000
        if userInitiated { filterModelSamples.add(filterMilliseconds) }
    }

    private func refreshRetainedState() {
        hosts = Array(Set(buffer.rows.map(\.host))).sorted()
        hostCounts = buffer.rows.reduce(into: [:]) { $0[$1.host, default: 0] += 1 }

        // Group path items per host
        var pathsMap: [String: [SidebarPathItem]] = [:]
        for host in hosts {
            let flowsForHost = buffer.rows.filter { $0.host == host }
            let pathGroups = Dictionary(grouping: flowsForHost, by: \.cleanPath)
            let items = pathGroups.map { SidebarPathItem(pathPrefix: $0.key, count: $0.value.count) }
                .sorted { $0.pathPrefix < $1.pathPrefix }
            pathsMap[host] = items
        }
        hostPaths = pathsMap

        // Group clients
        var clientsMap: [String: Int] = [:]
        for flow in buffer.rows {
            let c = flow.client?.isEmpty == false ? (flow.client ?? "Unknown") : "Unknown"
            clientsMap[c, default: 0] += 1
        }
        clientCounts = clientsMap
        clients = clientsMap.keys.sorted { a, b in
            if a == "Unknown" { return false }
            if b == "Unknown" { return true }
            return a < b
        }

        retainedCount = buffer.rows.count
        let retained = Set(buffer.rows.map(\.id))
        selectedIDs.formIntersection(retained)
        pinnedIDs.formIntersection(retained)
        if let selectedID, !retained.contains(selectedID) {
            self.selectedID = fallbackPrimary(in: selectedIDs)
        }
    }

    /// Called by the traffic table after it applied the latest rows; closes a user-initiated filter measurement.
    func markTableReloaded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let started = self.pendingFilterStart else { return }
            self.pendingFilterStart = nil
            self.filterEndToEndSamples.add((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
    }

    /// Called by each inspector pane after its text has been laid out. A selection is "rendered" once every
    /// visible pane (request, plus response when present) has reported for the same flow.
    func markSelectionRendered(flowID: String) {
        let now = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            guard let self, var pending = self.pendingRender, pending.id == flowID,
                  let shown = self.detail, shown.flow.summary.id == flowID else { return }
            pending.panes += 1
            if pending.panes >= (shown.response == nil ? 1 : 2) {
                self.pendingRender = nil
                self.selectionRenderSamples.add((now - pending.started) * 1000)
                if let ready = pending.detailReady {
                    self.selectionToDetailSamples.add((ready - pending.started) * 1000)
                    self.detailToRenderSamples.add((now - ready) * 1000)
                }
            } else {
                self.pendingRender = pending
            }
        }
    }

    nonisolated static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    nonisolated static func environmentPort(_ name: String) -> Int? {
        ProcessInfo.processInfo.environment[name].flatMap(Int.init).flatMap { (1024...65535).contains($0) ? $0 : nil }
    }

    private func waitFor(timeout: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while !condition() {
            if CFAbsoluteTimeGetCurrent() > deadline { benchmarkTimeouts += 1; return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// Benchmark mode only: drive real filters and real row selections once capture has gone idle.
    private func runBenchmark() async {
        let terms = ["json", "200", "request=1", "zzz-no-match", "",
                     "method:GET status:200-299 -state:error",
                     "type:json -type:image", "path:request=1 -host:excluded.test"]
        for _ in 0..<5 {
            for term in terms {
                let before = filterEndToEndSamples.totalCount
                search = term
                _ = await waitFor { filterEndToEndSamples.totalCount > before }
            }
            if let host = hosts.first {
                for selection in [SidebarFilter.domain(host), .all] {
                    let before = filterEndToEndSamples.totalCount
                    sidebarSelection = selection
                    _ = await waitFor { filterEndToEndSamples.totalCount > before }
                }
            }
        }
        search = ""
        sidebarSelection = .all
        _ = await waitFor { rows.count == retainedCount }
        let candidates = rows
        let step = max(1, candidates.count / 25)
        for index in stride(from: 0, to: candidates.count, by: step).prefix(25) {
            let before = selectionRenderSamples.totalCount
            selectedID = candidates[index].id
            _ = await waitFor { selectionRenderSamples.totalCount > before }
        }
        selectedID = nil
        benchmarkComplete = true
        writeBenchmarkMetricsIfRequested()
    }

    private func writeBenchmarkMetricsIfRequested() {
        if let path = Self.argument("--benchmark-output") { try? writeMetrics(to: URL(fileURLWithPath: path)) }
    }

    private func loadSelection() {
        detailTask?.cancel()
        guard let id = selectedID else {
            detail = nil
            loadingDetail = false
            return
        }
        loadingDetail = true
        // Keep the existing inspector and its pane/tab identity while fetching.
        // Publish headers, formatted bodies and summary together when all are ready.
        detailTask = Task {
            let began = CFAbsoluteTimeGetCurrent()
            defer { if !Task.isCancelled, selectedID == id { loadingDetail = false } }
            do {
                guard !Task.isCancelled else { return }
                let flow = try await readDetail(id: id)
                guard !Task.isCancelled, selectedID == id else { return }
                let prepared = await Task.detached(priority: .userInitiated) { InspectorDetail(flow: flow) }.value
                guard !Task.isCancelled, selectedID == id else { return }
                detail = prepared
                if pendingRender?.id == id, pendingRender?.detailReady == nil { pendingRender?.detailReady = CFAbsoluteTimeGetCurrent() }
                detailMilliseconds = (CFAbsoluteTimeGetCurrent() - began) * 1000
            } catch {
                guard !Task.isCancelled, selectedID == id else { return }
                detail = nil
                self.error = "Could not load the selected request: \(error.localizedDescription)"
            }
        }
    }

    private func readDetail(id: String) async throws -> FlowDetail {
        if let detailLoader { return try await detailLoader(id) }
        if let api = engine.api { return try await api.get("/flow/\(id)", as: FlowDetail.self) }
        guard let directory = engine.captureDirectory else { throw AppFailure("No capture previews are available") }
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(FlowDetail.self, from: Data(contentsOf: directory.appendingPathComponent(id + ".json")))
        }.value
    }

    func clearDisplay() {
        buffer = TrafficBuffer()
        rows = []
        hosts = []
        hostCounts = [:]
        hostPaths = [:]
        clients = []
        clientCounts = [:]
        retainedCount = 0
        selectedID = nil
        pinnedIDs = []
        filterRevision += 1
        selectedHost = nil
        sidebarSelection = .all
    }

    func openCertificate() {
        let cert = engine.paths.certificate
        guard FileManager.default.fileExists(atPath: cert.path) else {
            error = "Start capture once to generate this Mac’s CA certificate."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([cert])
    }

    func exportMetrics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "reqnivo-baseline.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try writeMetrics(to: url) } catch { self.error = error.localizedDescription }
    }

    func writeMetrics(to url: URL) throws {
        let result: [String: Any] = [
            "version": 1, "date": ISO8601DateFormatter().string(from: Date()),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "totalFlows": total, "visibleRows": rows.count,
            "processTreeMemory": memory, "sampledCPU": cpu,
            "lastBatchApplyMilliseconds": lastBatchMilliseconds,
            "lastDetailLoadMilliseconds": detailMilliseconds, "lastFilterMilliseconds": filterMilliseconds,
            "benchmarkComplete": benchmarkComplete, "benchmarkTimeouts": benchmarkTimeouts,
            "ui": ["rssMB": usage.uiMB, "sampledCPUPercent": usage.uiCPU],
            "engine": ["rssMB": usage.engineMB, "sampledCPUPercent": usage.engineCPU],
            "storage": ["previewDiskBytes": previewDiskBytes, "retainedPreviewFiles": retainedPreviewFiles],
            "selectionRender": Self.stats(selectionRenderSamples),
            "selectionToDetailReady": Self.stats(selectionToDetailSamples),
            "detailReadyToRender": Self.stats(detailToRenderSamples),
            "filterEndToEnd": Self.stats(filterEndToEndSamples),
            "filterModelOnly": Self.stats(filterModelSamples),
            "notes": "RSS includes UI and engine descendants; CPU is the ps decaying average, not interval CPU. selectionRender = selection change to text layout complete in all visible inspector panes; filterEndToEnd = user filter to NSTableView reloadData finished (excludes cell drawing); neither is a frame/scroll measurement."
        ]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    private static func stats(_ samples: LatencySamples) -> [String: Any] {
        ["count": samples.totalCount, "lastMilliseconds": samples.last ?? 0,
         "p50Milliseconds": samples.percentile(0.5), "p95Milliseconds": samples.percentile(0.95)]
    }

    nonisolated private static func sample(uiPID: Int32, enginePID: Int32) -> ResourceUsage? {
        guard let output = try? SystemProxy.command("/bin/ps", ["-axo", "pid=,ppid=,rss=,%cpu="]) else { return nil }
        return ResourceUsage.measure(uiPID: uiPID, enginePID: enginePID, processes: ResourceUsage.parse(psOutput: output))
    }
}
