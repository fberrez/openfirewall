import Foundation

public enum FirewallAction: String, Codable, CaseIterable, Sendable {
    case allow, deny
    public var title: String { self == .allow ? "Allow" : "Block" }
}

/// Verified Apple-anchored signing identities survive app updates. Other binaries
/// are pinned to a code-directory hash; paths are display information, never keys.
public struct ApplicationIdentity: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public var signingIdentifier: String?
    public var teamIdentifier: String?
    public var isVerifiedSigner: Bool

    public init(id: String, name: String, path: String, signingIdentifier: String? = nil,
                teamIdentifier: String? = nil, isVerifiedSigner: Bool = false) {
        self.id = id; self.name = name; self.path = path
        self.signingIdentifier = signingIdentifier; self.teamIdentifier = teamIdentifier
        self.isVerifiedSigner = isVerifiedSigner
    }

    public static let unidentified = ApplicationIdentity(id: "unidentified", name: "Unidentified process", path: "")
    public var canCreateRule: Bool { id != Self.unidentified.id && !id.isEmpty }
}

public struct ApplicationRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String { application.id }
    public var application: ApplicationIdentity
    public var action: FirewallAction
    public var modifiedAt: Date
    public init(application: ApplicationIdentity, action: FirewallAction, modifiedAt: Date = Date()) {
        self.application = application; self.action = action; self.modifiedAt = modifiedAt
    }
}

public struct FirewallPolicy: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var revision: UInt64 = 0
    public var defaultAction: FirewallAction = .allow
    public var rules: [ApplicationRule] = []
    public init() {}

    public func validated() throws -> FirewallPolicy {
        guard schemaVersion == 1 else { throw PolicyError.unsupportedSchema }
        guard rules.count <= 10_000 else { throw PolicyError.tooManyRules }
        var keys = Set<String>()
        for rule in rules {
            guard rule.application.canCreateRule,
                  rule.id.utf8.count <= 2048,
                  rule.application.name.utf8.count <= 4096,
                  rule.application.path.utf8.count <= 16_384 else { throw PolicyError.invalidIdentity }
            guard keys.insert(rule.id).inserted else { throw PolicyError.duplicateIdentity }
        }
        return self
    }

    public mutating func set(_ action: FirewallAction, for application: ApplicationIdentity) {
        rules.removeAll { $0.id == application.id }
        rules.append(ApplicationRule(application: application, action: action))
        revision += 1
    }

    public mutating func remove(applicationID: String) {
        rules.removeAll { $0.id == applicationID }; revision += 1
    }
}

public enum PolicyError: String, Error, LocalizedError {
    case unsupportedSchema, tooManyRules, invalidIdentity, duplicateIdentity, staleRevision
    public var errorDescription: String? { "Invalid firewall policy: \(rawValue)." }
}

public struct RuleEngine: Sendable {
    public private(set) var policy: FirewallPolicy
    private var actions: [String: FirewallAction]
    public init(policy: FirewallPolicy = FirewallPolicy()) throws {
        self.policy = try policy.validated()
        actions = Dictionary(uniqueKeysWithValues: policy.rules.map { ($0.id, $0.action) })
    }
    public func decision(for applicationID: String) -> FirewallAction { actions[applicationID] ?? policy.defaultAction }
    public mutating func replace(with policy: FirewallPolicy) throws {
        guard policy.revision >= self.policy.revision else { throw PolicyError.staleRevision }
        guard policy.revision != self.policy.revision || policy == self.policy else { throw PolicyError.staleRevision }
        self = try RuleEngine(policy: policy)
    }
}

public enum ConnectionState: String, Codable, Sendable { case active, blocked, closed }

public struct ConnectionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var application: ApplicationIdentity
    public var host: String
    public var port: String
    public var transport: String
    public var direction: String
    public var action: FirewallAction
    public var state: ConnectionState
    public var startedAt: Date
    public var updatedAt: Date
    public var bytesIn: UInt64 = 0
    public var bytesOut: UInt64 = 0

    public init(id: UUID = UUID(), application: ApplicationIdentity, host: String, port: String,
                transport: String, direction: String, action: FirewallAction, startedAt: Date = Date()) {
        self.id = id; self.application = application; self.host = host; self.port = port
        self.transport = transport; self.direction = direction; self.action = action
        self.state = action == .deny ? .blocked : .active
        self.startedAt = startedAt; self.updatedAt = startedAt
    }
}

/// A bounded, metadata-only history. Counters are cumulative per flow. Out-of-order
/// reports never decrease them. A clear operation establishes an explicit new window.
public struct ConnectionHistory: Sendable {
    public let capacity: Int
    public private(set) var evictedCount: UInt64 = 0
    private var records: [UUID: ConnectionRecord] = [:]
    private var order: [UUID] = []
    public init(capacity: Int = 500) { self.capacity = max(1, capacity) }
    public var newestFirst: [ConnectionRecord] { order.reversed().compactMap { records[$0] } }
    public mutating func insert(_ record: ConnectionRecord) {
        if records[record.id] == nil { order.append(record.id) }
        records[record.id] = record
        while order.count > capacity {
            records.removeValue(forKey: order.removeFirst()); evictedCount += 1
        }
    }
    public mutating func report(id: UUID, bytesIn: UInt64, bytesOut: UInt64, closed: Bool, at date: Date = Date()) {
        guard var record = records[id] else { return }
        record.bytesIn = max(record.bytesIn, bytesIn); record.bytesOut = max(record.bytesOut, bytesOut)
        if closed && record.state != .blocked { record.state = .closed }
        record.updatedAt = date; records[id] = record
    }
    public mutating func markBlocked(id: UUID) {
        guard var record = records[id] else { return }
        record.action = .deny; record.state = .blocked; record.updatedAt = Date(); records[id] = record
    }
    public mutating func clear() { records.removeAll(); order.removeAll(); evictedCount = 0 }
}

public struct ProviderSnapshot: Codable, Sendable {
    public var policy: FirewallPolicy
    public var connections: [ConnectionRecord]
    public var startedAt: Date
    public var activeFlowCount: Int
    public var untrackedFlowCount: UInt64
    public var evictedHistoryCount: UInt64
    public init(policy: FirewallPolicy, connections: [ConnectionRecord], startedAt: Date,
                activeFlowCount: Int, untrackedFlowCount: UInt64 = 0, evictedHistoryCount: UInt64 = 0) {
        self.policy = policy; self.connections = connections; self.startedAt = startedAt
        self.activeFlowCount = activeFlowCount; self.untrackedFlowCount = untrackedFlowCount
        self.evictedHistoryCount = evictedHistoryCount
    }
}

public enum WireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= 8 * 1024 * 1024 else { throw PolicyError.tooManyRules }
        return try JSONDecoder().decode(type, from: data)
    }
}
