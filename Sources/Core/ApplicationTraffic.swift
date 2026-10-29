import Foundation

public struct ApplicationTrafficTotal: Codable, Equatable, Identifiable, Sendable {
    public var application: ApplicationIdentity
    public var bytesIn: UInt64 = 0
    public var bytesOut: UInt64 = 0
    public var id: String { application.id }
    public init(application: ApplicationIdentity, bytesIn: UInt64 = 0, bytesOut: UInt64 = 0) {
        self.application = application; self.bytesIn = bytesIn; self.bytesOut = bytesOut
    }
}

/// Accounting is separate from the 500-row log. Retain counters until flow close,
/// so statistics arriving after log eviction still contribute to application totals.
public struct ApplicationTrafficLedger: Sendable {
    public let epoch = UUID()
    public private(set) var untrackedFlowCount: UInt64 = 0
    private let flowLimit: Int
    private let applicationLimit: Int
    private var applications: [String: ApplicationTrafficTotal] = [:]
    private var flows: [UUID: FlowCounter] = [:]
    private struct FlowCounter: Sendable {
        let applicationID: String
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
    }
    public init(flowLimit: Int = 16_384, applicationLimit: Int = 4096) {
        self.flowLimit = max(1, flowLimit); self.applicationLimit = max(1, applicationLimit)
    }
    public var totals: [ApplicationTrafficTotal] { applications.values.sorted { $0.id < $1.id } }
    public mutating func register(_ record: ConnectionRecord) {
        guard flows[record.id] == nil else { return }
        let id = record.application.id
        guard flows.count < flowLimit, applications[id] != nil || applications.count < applicationLimit else {
            untrackedFlowCount = saturatedAdd(untrackedFlowCount, 1); return
        }
        if applications[id] == nil { applications[id] = ApplicationTrafficTotal(application: record.application) }
        flows[record.id] = FlowCounter(applicationID: id)
    }
    public mutating func report(id: UUID, bytesIn: UInt64, bytesOut: UInt64, closed: Bool) {
        guard var flow = flows[id], var app = applications[flow.applicationID] else { return }
        let incoming = max(flow.bytesIn, bytesIn), outgoing = max(flow.bytesOut, bytesOut)
        app.bytesIn = saturatedAdd(app.bytesIn, incoming - flow.bytesIn)
        app.bytesOut = saturatedAdd(app.bytesOut, outgoing - flow.bytesOut)
        flow.bytesIn = incoming; flow.bytesOut = outgoing
        applications[flow.applicationID] = app
        if closed { flows.removeValue(forKey: id) } else { flows[id] = flow }
    }
}

/// A fresh instance is created only when the UI process launches. First readings
/// establish a baseline; later readings add deltas, including across provider restarts.
public struct ApplicationTrafficSession: Sendable {
    private var epoch: UUID?
    private var previous: [String: ApplicationTrafficTotal] = [:]
    private var accumulated: [String: ApplicationTrafficTotal] = [:]
    public init() {}
    public var totals: [ApplicationTrafficTotal] { accumulated.values.sorted { $0.id < $1.id } }
    public mutating func consume(epoch: UUID, totals: [ApplicationTrafficTotal]) {
        let firstReading = self.epoch == nil
        if self.epoch != epoch { previous.removeAll(); self.epoch = epoch }
        for value in totals {
            var session = accumulated[value.id] ?? ApplicationTrafficTotal(application: value.application)
            let old = previous[value.id] ?? ApplicationTrafficTotal(application: value.application)
            let incoming = max(old.bytesIn, value.bytesIn), outgoing = max(old.bytesOut, value.bytesOut)
            if !firstReading {
                session.bytesIn = saturatedAdd(session.bytesIn, incoming - old.bytesIn)
                session.bytesOut = saturatedAdd(session.bytesOut, outgoing - old.bytesOut)
            }
            session.application = value.application
            accumulated[value.id] = session
            previous[value.id] = ApplicationTrafficTotal(application: value.application, bytesIn: incoming, bytesOut: outgoing)
        }
    }
}

/// Root rows group by verified identity. Children remain the retained connection log.
public struct ConnectionLogRow: Identifiable, Sendable {
    public let application: ApplicationIdentity
    public let connection: ConnectionRecord?
    public let sessionBytesIn: UInt64?
    public let children: [ConnectionLogRow]?
    public var id: String { connection.map { "flow:\($0.id)" } ?? "app:\(application.id)" }
    public var name: String { application.name }
    public var bytesIn: UInt64? { connection?.bytesIn ?? sessionBytesIn }
    public var rxSortValue: UInt64 { bytesIn ?? 0 }
    public init(connection: ConnectionRecord) {
        self.application = connection.application; self.connection = connection
        sessionBytesIn = nil; children = nil
    }
    public init(application: ApplicationIdentity, bytesIn: UInt64?, connections: [ConnectionRecord]) {
        self.application = application; connection = nil; sessionBytesIn = bytesIn
        children = connections.isEmpty ? nil : connections.map(ConnectionLogRow.init(connection:))
    }
    public static func groups(connections: [ConnectionRecord], totals: [ApplicationTrafficTotal],
                              search: String = "", decision: FirewallAction? = nil) -> [ConnectionLogRow] {
        let byApp = Dictionary(grouping: connections, by: { $0.application.id })
        let traffic = Dictionary(totals.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var identities = Dictionary(connections.map { ($0.application.id, $0.application) }, uniquingKeysWith: { _, last in last })
        for total in totals { identities[total.id] = total.application }
        return identities.values.compactMap { app in
            let appMatches = search.isEmpty || app.name.localizedCaseInsensitiveContains(search) || app.path.localizedCaseInsensitiveContains(search)
            let retained = (byApp[app.id] ?? []).filter {
                (decision == nil || $0.action == decision) &&
                (appMatches || $0.host.localizedCaseInsensitiveContains(search) || $0.port.localizedCaseInsensitiveContains(search))
            }
            guard !retained.isEmpty || (decision == nil && appMatches) else { return nil }
            return ConnectionLogRow(application: app, bytesIn: traffic[app.id]?.bytesIn, connections: retained)
        }.sorted {
            if $0.rxSortValue != $1.rxSortValue { return $0.rxSortValue > $1.rxSortValue }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
    }
}

private func saturatedAdd(_ left: UInt64, _ right: UInt64) -> UInt64 {
    let (value, overflow) = left.addingReportingOverflow(right)
    return overflow ? .max : value
}
