import XCTest
@testable import FirewallCore

final class FirewallCoreTests: XCTestCase {
    let safari = ApplicationIdentity(id: "signed:apple:com.apple.Safari", name: "Safari", path: "/Applications/Safari.app")
    let other = ApplicationIdentity(id: "signed:OTHERTEAM:com.apple.Safari", name: "Safari", path: "/tmp/Safari.app")

    func testAllowByDefaultAndExplicitDeny() throws {
        var policy = FirewallPolicy(); policy.set(.deny, for: safari)
        let engine = try RuleEngine(policy: policy)
        XCTAssertEqual(engine.decision(for: safari.id), .deny)
        XCTAssertEqual(engine.decision(for: other.id), .allow)
        XCTAssertEqual(engine.decision(for: ApplicationIdentity.unidentified.id), .allow)
    }
    func testExplicitAllowOverridesDefaultDeny() throws {
        var policy = FirewallPolicy(); policy.defaultAction = .deny; policy.set(.allow, for: safari)
        let engine = try RuleEngine(policy: policy)
        XCTAssertEqual(engine.decision(for: safari.id), .allow)
        XCTAssertEqual(engine.decision(for: other.id), .deny)
    }
    func testDisplayNameOrPathNeverGrantsPermission() throws {
        var policy = FirewallPolicy(); policy.defaultAction = .deny; policy.set(.allow, for: safari)
        let engine = try RuleEngine(policy: policy)
        XCTAssertEqual(engine.decision(for: other.id), .deny)
        var renamed = safari; renamed.name = "Renamed"; renamed.path = "/Other/Safari.app"
        XCTAssertEqual(engine.decision(for: renamed.id), .allow)
    }
    func testRemovingRuleFallsBackAndUpdatesRevision() throws {
        var policy = FirewallPolicy(); policy.set(.deny, for: safari); policy.remove(applicationID: safari.id)
        XCTAssertEqual(policy.revision, 2)
        XCTAssertEqual(try RuleEngine(policy: policy).decision(for: safari.id), .allow)
    }
    func testRejectsDuplicateAndInvalidIdentities() throws {
        var policy = FirewallPolicy(); policy.rules = [ApplicationRule(application: safari, action: .allow), ApplicationRule(application: safari, action: .deny)]
        XCTAssertThrowsError(try RuleEngine(policy: policy))
        policy.rules = [ApplicationRule(application: .unidentified, action: .deny)]
        XCTAssertThrowsError(try RuleEngine(policy: policy))
        policy.schemaVersion = 99
        XCTAssertThrowsError(try policy.validated())
    }
    func testRejectsStaleRuleUpdates() throws {
        var newer = FirewallPolicy(); newer.revision = 10; newer.set(.deny, for: safari)
        var engine = try RuleEngine(policy: newer)
        XCTAssertThrowsError(try engine.replace(with: FirewallPolicy()))
        XCTAssertEqual(engine.decision(for: safari.id), .deny)
        try engine.replace(with: newer) // acknowledgement of identical policy is idempotent
        var conflicting = newer; conflicting.defaultAction = .deny
        XCTAssertThrowsError(try engine.replace(with: conflicting))
    }
    func testCodeDirectoryHashPinsSpecificBuild() throws {
        var policy = FirewallPolicy(); policy.defaultAction = .deny
        let old = ApplicationIdentity(id: "cdhash:aaaa", name: "tool", path: "/tmp/tool")
        policy.set(.allow, for: old)
        XCTAssertEqual(try RuleEngine(policy: policy).decision(for: "cdhash:bbbb"), .deny)
    }
    func testPolicyRoundTripPreservesDecision() throws {
        var policy = FirewallPolicy(); policy.defaultAction = .deny; policy.set(.allow, for: safari)
        let decoded = try WireCodec.decode(FirewallPolicy.self, from: WireCodec.encode(policy))
        XCTAssertEqual(decoded, policy)
        XCTAssertEqual(try RuleEngine(policy: decoded).decision(for: safari.id), .allow)
    }
    func testHistoryBoundedAndReportsMonotonic() {
        var history = ConnectionHistory(capacity: 2)
        let first = ConnectionRecord(application: safari, host: "example.com", port: "443", transport: "TCP", direction: "Outgoing", action: .allow)
        history.insert(first)
        history.report(id: first.id, bytesIn: 100, bytesOut: 50, closed: false)
        history.report(id: first.id, bytesIn: 20, bytesOut: 10, closed: true)
        XCTAssertEqual(history.newestFirst[0].bytesIn, 100)
        XCTAssertEqual(history.newestFirst[0].state, .closed)
        let second = ConnectionRecord(application: safari, host: "two", port: "443", transport: "UDP", direction: "Outgoing", action: .allow)
        let third = ConnectionRecord(application: safari, host: "three", port: "443", transport: "TCP", direction: "Outgoing", action: .deny)
        history.insert(second); history.insert(third)
        XCTAssertEqual(history.newestFirst.map(\.id), [third.id, second.id])
        XCTAssertEqual(history.evictedCount, 1)
        history.markBlocked(id: second.id)
        history.report(id: second.id, bytesIn: 1, bytesOut: 2, closed: true)
        XCTAssertEqual(history.newestFirst.last?.state, .blocked)
        history.clear(); XCTAssertTrue(history.newestFirst.isEmpty)
    }
    func testMalformedPolicyDataIsRejected() {
        XCTAssertThrowsError(try WireCodec.decode(FirewallPolicy.self, from: Data("not JSON".utf8)))
        XCTAssertThrowsError(try WireCodec.decode(FirewallPolicy.self, from: Data(repeating: 0, count: 8 * 1024 * 1024 + 1)))
    }
}
