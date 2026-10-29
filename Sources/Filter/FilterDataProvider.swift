import Foundation
import NetworkExtension
import Network
import OSLog

@objc(FilterDataProvider)
final class FilterDataProvider: NEFilterDataProvider {
    private let stateQueue = DispatchQueue(label: "org.openfirewall.filter.state")
    private var engine = try! RuleEngine()
    private var history = ConnectionHistory()
    private var traffic = ApplicationTrafficLedger()
    private var flows: [UUID: (flow: NEFilterSocketFlow, identity: ApplicationIdentity)] = [:]
    private let identityCache = NSCache<NSData, IdentityBox>()
    private var untracked: UInt64 = 0
    private var startedAt = Date()
    private var control: ControlListener?
    private var configurationObservation: NSKeyValueObservation?
    private let logger = Logger(subsystem: "org.openfirewall.filter", category: "lifecycle")

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        identityCache.countLimit = 2048
        stateQueue.sync { traffic = ApplicationTrafficLedger(); startedAt = Date() }
        do {
            if let data = filterConfiguration.vendorConfiguration?[ProductConfiguration.policyKey] as? Data {
                let policy = try WireCodec.decode(FirewallPolicy.self, from: data)
                engine = try RuleEngine(policy: policy)
            }
        } catch {
            // A corrupted stored policy must not silently turn a deny policy into allow.
            completionHandler(error); return
        }
        configurationObservation = observe(\.filterConfiguration, options: [.new]) { [weak self] _, _ in
            guard let self, let data = self.filterConfiguration.vendorConfiguration?[ProductConfiguration.policyKey] as? Data else { return }
            self.stateQueue.async { try? self.installPolicy(data) }
        }
        // NEFilterSettings' defaultAction only covers non-loopback traffic.
        // Explicit rules are required so a local HTTP/SOCKS proxy cannot bypass
        // the originating app's policy. The proxy keeps its own separate identity.
        let localRules = [("127.0.0.0", 8), ("::1", 128)].map { address, prefix in
            NEFilterRule(networkRule: NENetworkRule(
                remoteNetwork: NWHostEndpoint(hostname: address, port: "0"), remotePrefix: prefix,
                localNetwork: nil, localPrefix: 0, protocol: .any, direction: .any), action: .filterData)
        }
        let settings = NEFilterSettings(rules: localRules, defaultAction: .filterData)
        apply(settings) { [weak self] error in
            guard let self else { completionHandler(error); return }
            if error == nil {
                self.control = ControlListener(provider: self)
                self.control?.start()
                self.logger.notice("Filter started")
            }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        control?.stop(); control = nil; configurationObservation = nil
        stateQueue.sync { flows.removeAll(); identityCache.removeAllObjects() }
        logger.notice("Filter stopped: \(reason.rawValue)")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        stateQueue.sync {
            let identity = resolve(flow.sourceAppAuditToken)
            let action = engine.decision(for: identity.id)
            let socket = flow as? NEFilterSocketFlow
            let endpoint = socket?.remoteEndpoint as? NWHostEndpoint
            let direction = flow.direction == .inbound ? "Incoming" : "Outgoing"
            let transport: String
            switch socket?.socketProtocol { case 6: transport = "TCP"; case 17: transport = "UDP"; default: transport = "Other" }
            let record = ConnectionRecord(id: flow.identifier, application: identity,
                host: socket?.remoteHostname ?? endpoint?.hostname ?? "Unknown destination",
                port: endpoint?.port ?? "", transport: transport, direction: direction, action: action)
            history.insert(record)
            traffic.register(record)
            if let socket, action == .allow {
                if flows.count < 16_384 { flows[flow.identifier] = (socket, identity) }
                else { untracked += 1 }
            }
            let verdict: NEFilterNewFlowVerdict = action == .deny ? .drop() : .allow()
            verdict.shouldReport = true
            verdict.statisticsReportFrequency = .low
            return verdict
        }
    }

    override func handle(_ report: NEFilterReport) {
        stateQueue.sync {
            guard let flow = report.flow else { return }
            let closed = report.event == .flowClosed
            traffic.report(id: flow.identifier, bytesIn: UInt64(report.bytesInboundCount),
                           bytesOut: UInt64(report.bytesOutboundCount), closed: closed)
            history.report(id: flow.identifier, bytesIn: UInt64(report.bytesInboundCount),
                           bytesOut: UInt64(report.bytesOutboundCount), closed: closed)
            if closed { flows.removeValue(forKey: flow.identifier) }
        }
    }

    func snapshotData() throws -> Data {
        try stateQueue.sync {
            try WireCodec.encode(ProviderSnapshot(policy: engine.policy, connections: history.newestFirst,
                startedAt: startedAt, activeFlowCount: flows.count, untrackedFlowCount: untracked,
                evictedHistoryCount: history.evictedCount, trafficEpoch: traffic.epoch,
                applicationTraffic: traffic.totals, untrackedTrafficFlowCount: traffic.untrackedFlowCount))
        }
    }

    func applyPolicyData(_ data: Data) throws {
        try stateQueue.sync { try installPolicy(data) }
    }

    func clearHistory() { stateQueue.sync { history.clear() } }

    var ownerUID: uid_t? {
        (filterConfiguration.vendorConfiguration?[ProductConfiguration.ownerKey] as? NSNumber).map { uid_t($0.uint32Value) }
    }

    /// All callers hold stateQueue. New deny rules also drop retained existing flows.
    private func installPolicy(_ data: Data) throws {
        let policy = try WireCodec.decode(FirewallPolicy.self, from: data)
        try engine.replace(with: policy)
        let denied = flows.filter { engine.decision(for: $0.value.identity.id) == .deny }
        for (id, tracked) in denied {
            update(tracked.flow, using: .drop(), for: .any)
            history.markBlocked(id: id)
            flows.removeValue(forKey: id)
        }
    }

    private func resolve(_ token: Data?) -> ApplicationIdentity {
        guard let token else { return .unidentified }
        if let cached = identityCache.object(forKey: token as NSData) { return cached.identity }
        let identity = IdentityResolver.application(auditToken: token)
        if identity.canCreateRule { identityCache.setObject(IdentityBox(identity), forKey: token as NSData) }
        return identity
    }
}

private final class IdentityBox: NSObject {
    let identity: ApplicationIdentity
    init(_ identity: ApplicationIdentity) { self.identity = identity }
}

private final class ControlListener: NSObject, NSXPCListenerDelegate {
    private weak var provider: FilterDataProvider?
    private var listener: NSXPCListener?
    private var connections: [UUID: NSXPCConnection] = [:]
    private let lock = NSLock()
    init(provider: FilterDataProvider) { self.provider = provider }
    func start() {
        guard !ProductConfiguration.serviceName.isEmpty else { return }
        let listener = NSXPCListener(machServiceName: ProductConfiguration.serviceName)
        self.listener = listener; listener.delegate = self; listener.resume()
    }
    func stop() {
        listener?.invalidate()
        lock.lock(); let current = Array(connections.values); connections.removeAll(); lock.unlock()
        current.forEach { $0.invalidate() }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let provider, let owner = provider.ownerUID,
              connection.effectiveUserIdentifier == owner,
              let requirement = ProductConfiguration.requirement(for: ProductConfiguration.appIdentifier) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard connections.count < 8 else { return false }
        // Foundation enforces this on messages, avoiding a PID-only validation race.
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: FirewallControlProtocol.self)
        connection.exportedObject = ControlSession(provider: provider)
        let id = UUID(); connections[id] = connection
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.connections.removeValue(forKey: id); self.lock.unlock()
        }
        connection.resume(); return true
    }
}

private final class ControlSession: NSObject, FirewallControlProtocol {
    private weak var provider: FilterDataProvider?
    init(provider: FilterDataProvider) { self.provider = provider }
    func snapshot(reply: @escaping (Data?, String?) -> Void) {
        do { guard let provider else { throw unavailable() }; reply(try provider.snapshotData(), nil) }
        catch { reply(nil, error.localizedDescription) }
    }
    func applyPolicy(_ data: Data, reply: @escaping (String?) -> Void) {
        do { guard let provider else { throw unavailable() }; try provider.applyPolicyData(data); reply(nil) }
        catch { reply(error.localizedDescription) }
    }
    func clearHistory(reply: @escaping () -> Void) { provider?.clearHistory(); reply() }
    private func unavailable() -> NSError {
        NSError(domain: "org.openfirewall.filter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The network filter has stopped."])
    }
}
