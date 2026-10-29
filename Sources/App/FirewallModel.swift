import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FirewallModel: ObservableObject {
    @Published var policy = FirewallPolicy()
    @Published var connections: [ConnectionRecord] = []
    @Published var connected = false
    @Published var preview = false
    @Published var status = "Filter disconnected"
    @Published var updateMessage: String?
    @Published var error: String?
    @Published var activeFlows = 0
    @Published var untracked: UInt64 = 0
    @Published var evicted: UInt64 = 0
    @Published var applicationTraffic: [ApplicationTrafficTotal] = []
    @Published var hasTrafficTotals = false
    @Published var trafficIncomplete = false
    @Published var showingApplicationPicker = false
    let setup = SystemSetup()
    private let client = FilterClient()
    private var pendingPolicy: FirewallPolicy?
    private var saving = false
    private var pollTask: Task<Void, Never>?
    private var savedBeforePreview: FirewallPolicy?
    private var trafficSession = ApplicationTrafficSession()
    private var savedTrafficBeforePreview: (totals: [ApplicationTrafficTotal], available: Bool, incomplete: Bool)?
    private var localURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenFirewall", isDirectory: true).appendingPathComponent("rules.json")
    }

    init() {
        if let data = try? Data(contentsOf: localURL), let saved = try? WireCodec.decode(FirewallPolicy.self, from: data).validated() { policy = saved }
    }
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await setup.load()
            if let saved = await setup.savedPolicy(), saved.revision >= policy.revision { policy = saved }
            while !Task.isCancelled {
                if !preview { await refresh() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func refresh() async {
        do {
            let snapshot = try await client.snapshot()
            guard !preview else { return }
            connected = true; connections = snapshot.connections; activeFlows = snapshot.activeFlowCount
            untracked = snapshot.untrackedFlowCount; evicted = snapshot.evictedHistoryCount
            if let epoch = snapshot.trafficEpoch, let totals = snapshot.applicationTraffic {
                trafficSession.consume(epoch: epoch, totals: totals)
                applicationTraffic = trafficSession.totals; hasTrafficTotals = true
                trafficIncomplete = trafficIncomplete || (snapshot.untrackedTrafficFlowCount ?? 0) > 0
            } else {
                hasTrafficTotals = false
            }
            status = "Filtering"
            if !saving && pendingPolicy == nil && snapshot.policy.revision > policy.revision { policy = snapshot.policy; saveLocal() }
        } catch {
            guard !preview else { return }
            connected = false; status = "Filter disconnected"
        }
    }
    func setRule(_ action: FirewallAction, application: ApplicationIdentity) {
        guard application.canCreateRule else { return }
        policy.set(action, for: application); changed()
    }
    func removeRule(_ id: String) { policy.remove(applicationID: id); changed() }
    func setDefault(_ action: FirewallAction) { policy.defaultAction = action; policy.revision += 1; changed() }
    func explicitAction(_ id: String) -> FirewallAction? { policy.rules.first { $0.id == id }?.action }
    private func changed() {
        if preview {
            let engine = try! RuleEngine(policy: policy)
            for i in connections.indices {
                connections[i].action = engine.decision(for: connections[i].application.id)
                connections[i].state = connections[i].action == .deny ? .blocked : .active
            }
            activeFlows = connections.filter { $0.action == .allow }.count
            updateMessage = "Preview · changes not applied"; return
        }
        saveLocal(); pendingPolicy = policy; updateMessage = "Saving rules…"
        if !saving { Task { await publishPending() } }
    }
    private func publishPending() async {
        guard !saving else { return }
        saving = true; defer { saving = false }
        while let next = pendingPolicy {
            pendingPolicy = nil
            guard !preview else { return }
            if setup.enabled {
                do {
                    try await setup.persist(next)
                    try await client.apply(next)
                    updateMessage = "Rules applied"
                    await refresh()
                } catch { updateMessage = "Saved · filter update unconfirmed"; self.error = error.localizedDescription }
            } else { updateMessage = "Saved · filter disabled" }
        }
    }
    private func saveLocal() {
        do {
            let directory = localURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try WireCodec.encode(policy).write(to: localURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localURL.path)
        } catch { self.error = "Could not save rules: \(error.localizedDescription)" }
    }
    func enable() {
        guard !preview else { return }
        Task { do { try await setup.enable(policy: policy); await refresh() } catch { self.error = error.localizedDescription } }
    }
    func disable() {
        guard !preview else { return }
        Task { do { try await setup.disable(); connected = false; connections = []; status = "Firewall is off" } catch { self.error = error.localizedDescription } }
    }
    func addApplication() {
        showingApplicationPicker = true
    }
    func selectApplication(_ url: URL) {
        showingApplicationPicker = false
        addSelectedApplication(url)
    }
    func browseApplication() {
        let panel = NSOpenPanel()
        // Validate the selection below; UTI filtering can disable valid app packages.
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = true
        panel.canChooseFiles = true; panel.treatsFilePackagesAsDirectories = false
        panel.message = "App or executable"
        panel.prompt = "Add app"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.selectApplication(url) }
        }
        // A blocking nested run loop can strand MainActor work while the monitor polls.
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func addSelectedApplication(_ url: URL) {
        do {
            let isApp = url.pathExtension.lowercased() == "app"
            let isExecutable = !url.hasDirectoryPath && FileManager.default.isExecutableFile(atPath: url.path)
            guard isApp || isExecutable else { throw clientError("Choose an application or an executable file.") }
            setRule(.allow, application: try IdentityResolver.application(at: url))
        }
        catch { self.error = error.localizedDescription }
    }
    func clearHistory() {
        if preview { connections = []; return }
        Task { do { try await client.clear(); await refresh() } catch { self.error = error.localizedDescription } }
    }
    func exportHistory() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "OpenFirewall-connections.json"
        let records = connections
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                    try encoder.encode(records).write(to: url, options: .atomic)
                } catch { self?.error = error.localizedDescription }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func togglePreview() {
        if preview {
            preview = false; policy = savedBeforePreview ?? FirewallPolicy(); savedBeforePreview = nil
            connections = []; connected = false; updateMessage = nil; status = "Filter disconnected"
            if let saved = savedTrafficBeforePreview {
                applicationTraffic = saved.totals; hasTrafficTotals = saved.available; trafficIncomplete = saved.incomplete
            }
            savedTrafficBeforePreview = nil
            Task { await refresh() }; return
        }
        guard !connected && !saving && !setup.enabled else { return }
        savedBeforePreview = policy; preview = true; policy = FirewallPolicy()
        savedTrafficBeforePreview = (applicationTraffic, hasTrafficTotals, trafficIncomplete)
        let apps = [
            ApplicationIdentity(id: "preview:safari", name: "Safari", path: "/Applications/Safari.app", signingIdentifier: "com.apple.Safari", teamIdentifier: "apple-platform", isVerifiedSigner: true),
            ApplicationIdentity(id: "preview:notes", name: "Notes", path: "/System/Applications/Notes.app", signingIdentifier: "com.apple.Notes", teamIdentifier: "apple-platform", isVerifiedSigner: true),
            ApplicationIdentity(id: "preview:terminal", name: "Terminal", path: "/System/Applications/Utilities/Terminal.app", signingIdentifier: "com.apple.Terminal", teamIdentifier: "apple-platform", isVerifiedSigner: true)
        ]
        policy.set(.deny, for: apps[2]); policy.set(.allow, for: apps[0])
        let hosts = ["developer.apple.com", "www.wikipedia.org", "icloud.com", "example.com", "api.github.com"]
        connections = (0..<18).map { i in
            let app = apps[i % apps.count]
            var record = ConnectionRecord(application: app, host: hosts[i % hosts.count], port: "443",
                transport: i % 3 == 0 ? "UDP" : "TCP", direction: "Outgoing",
                action: app.id == apps[2].id ? .deny : .allow, startedAt: Date().addingTimeInterval(Double(-i * 3)))
            if record.action == .allow { record.bytesIn = UInt64((i + 1) * 18_432); record.bytesOut = UInt64((i + 1) * 1024) }
            return record
        }
        connections[0].state = .closed
        var sampleTraffic = ApplicationTrafficSession()
        let epoch = UUID()
        sampleTraffic.consume(epoch: epoch, totals: [])
        let totals = Dictionary(grouping: connections, by: { $0.application.id }).values.map { records in
            ApplicationTrafficTotal(application: records[0].application,
                bytesIn: records.reduce(0) { $0 + $1.bytesIn }, bytesOut: records.reduce(0) { $0 + $1.bytesOut })
        }
        sampleTraffic.consume(epoch: epoch, totals: totals)
        applicationTraffic = sampleTraffic.totals; hasTrafficTotals = true; trafficIncomplete = false
        activeFlows = connections.filter { $0.state == .active }.count
        status = "Sample connections"; updateMessage = "Preview · changes not applied"
    }
}
