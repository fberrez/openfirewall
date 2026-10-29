import XCTest
@testable import FirewallCore

final class ApplicationTrafficTests: XCTestCase {
    let browser = ApplicationIdentity(id: "signed:TEAM:browser", name: "Browser", path: "/Applications/Browser.app")
    let other = ApplicationIdentity(id: "signed:OTHER:browser", name: "Browser", path: "/Other/Browser.app")
    func record(_ app: ApplicationIdentity, host: String = "example.com", action: FirewallAction = .allow) -> ConnectionRecord {
        ConnectionRecord(application: app, host: host, port: "443", transport: "TCP", direction: "Outgoing", action: action)
    }
    func testReportsAfterLogEvictionStillAccumulate() {
        var history = ConnectionHistory(capacity: 1)
        var ledger = ApplicationTrafficLedger()
        let a = record(browser), b = record(browser)
        history.insert(a); ledger.register(a)
        ledger.report(id: a.id, bytesIn: 100, bytesOut: 10, closed: false)
        history.insert(b); ledger.register(b)
        XCTAssertEqual(history.newestFirst.map(\.id), [b.id])
        ledger.report(id: a.id, bytesIn: 250, bytesOut: 20, closed: true)
        ledger.report(id: b.id, bytesIn: 50, bytesOut: 5, closed: true)
        XCTAssertEqual(ledger.totals.first?.bytesIn, 300)
        XCTAssertEqual(ledger.totals.first?.bytesOut, 25)
        history.clear()
        XCTAssertEqual(ledger.totals.first?.bytesIn, 300)
    }
    func testRepeatedAndOutOfOrderStatisticsDoNotDoubleCount() {
        var ledger = ApplicationTrafficLedger()
        let r = record(browser); ledger.register(r); ledger.register(r)
        for count: UInt64 in [100, 100, 50, 150] {
            ledger.report(id: r.id, bytesIn: count, bytesOut: 0, closed: false)
        }
        ledger.report(id: r.id, bytesIn: 200, bytesOut: 10, closed: true)
        ledger.report(id: r.id, bytesIn: 200, bytesOut: 10, closed: true)
        XCTAssertEqual(ledger.totals.first?.bytesIn, 200)
        XCTAssertEqual(ledger.totals.first?.bytesOut, 10)
    }
    func testIdentitySeparatesApplicationsWithTheSameName() {
        var ledger = ApplicationTrafficLedger()
        let a = record(browser), b = record(other)
        ledger.register(a); ledger.register(b)
        ledger.report(id: a.id, bytesIn: 25, bytesOut: 0, closed: true)
        ledger.report(id: b.id, bytesIn: 40, bytesOut: 0, closed: true)
        XCTAssertEqual(ledger.totals.count, 2)
        XCTAssertEqual(ledger.totals.first { $0.id == browser.id }?.bytesIn, 25)
    }
    func testAccountingLimitsAreReportedAndClosingFreesCapacity() {
        var ledger = ApplicationTrafficLedger(flowLimit: 1, applicationLimit: 1)
        let a = record(browser), b = record(browser), c = record(other)
        ledger.register(a); ledger.register(b)
        XCTAssertEqual(ledger.untrackedFlowCount, 1)
        ledger.report(id: a.id, bytesIn: 10, bytesOut: 0, closed: true)
        ledger.register(b)
        ledger.report(id: b.id, bytesIn: 20, bytesOut: 0, closed: true)
        ledger.register(c)
        XCTAssertEqual(ledger.untrackedFlowCount, 2)
        XCTAssertEqual(ledger.totals.first?.bytesIn, 30)
    }
    func testCounterOverflowSaturatesRatherThanWrapping() {
        var ledger = ApplicationTrafficLedger()
        for value: UInt64 in [.max, 1] {
            let r = record(browser); ledger.register(r)
            ledger.report(id: r.id, bytesIn: value, bytesOut: value, closed: true)
        }
        XCTAssertEqual(ledger.totals.first?.bytesIn, .max)
        XCTAssertEqual(ledger.totals.first?.bytesOut, .max)
    }
    func testUISessionSubtractsExistingTrafficAndAccumulatesNewApps() {
        var session = ApplicationTrafficSession(); let epoch = UUID()
        session.consume(epoch: epoch, totals: [.init(application: browser, bytesIn: 1000)])
        XCTAssertEqual(session.totals.first?.bytesIn, 0)
        session.consume(epoch: epoch, totals: [.init(application: browser, bytesIn: 1200), .init(application: other, bytesIn: 50)])
        session.consume(epoch: epoch, totals: [.init(application: browser, bytesIn: 1200), .init(application: other, bytesIn: 50)])
        session.consume(epoch: epoch, totals: [.init(application: browser, bytesIn: 1100)])
        XCTAssertEqual(session.totals.first { $0.id == browser.id }?.bytesIn, 200)
        XCTAssertEqual(session.totals.first { $0.id == other.id }?.bytesIn, 50)
    }
    func testUIRestartResetsRXWhileProviderRestartPreservesTheSession() {
        let epoch = UUID(); var session = ApplicationTrafficSession()
        session.consume(epoch: epoch, totals: [.init(application: browser, bytesIn: 100)])
        session.consume(epoch: epoch, totals: [.init(application: browser, bytesIn: 150)])
        let nextEpoch = UUID()
        session.consume(epoch: nextEpoch, totals: [.init(application: browser, bytesIn: 20)])
        session.consume(epoch: nextEpoch, totals: [.init(application: browser, bytesIn: 30)])
        XCTAssertEqual(session.totals.first?.bytesIn, 80)
        var relaunched = ApplicationTrafficSession()
        relaunched.consume(epoch: nextEpoch, totals: [.init(application: browser, bytesIn: 30)])
        XCTAssertEqual(relaunched.totals.first?.bytesIn, 0)
    }
    func testGroupsSortRXNumericallyAndRetainAppsAfterLogClear() {
        let totals = [ApplicationTrafficTotal(application: browser, bytesIn: 9000),
                      ApplicationTrafficTotal(application: other, bytesIn: 1_000_000)]
        let groups = ConnectionLogRow.groups(connections: [record(browser), record(other)], totals: totals)
        XCTAssertEqual(groups.map(\.application.id), [other.id, browser.id])
        XCTAssertEqual(groups.map { $0.children?.count }, [1, 1])
        let cleared = ConnectionLogRow.groups(connections: [], totals: totals)
        XCTAssertEqual(cleared.count, 2)
        XCTAssertEqual(cleared.first?.bytesIn, 1_000_000)
        XCTAssertNil(cleared.first?.children)
    }
    func testSearchAndDecisionFiltersDoNotChangeAppSessionRX() {
        let connections = [record(browser, host: "one.example"), record(browser, host: "two.example", action: .deny)]
        let total = ApplicationTrafficTotal(application: browser, bytesIn: 500)
        let searched = ConnectionLogRow.groups(connections: connections, totals: [total], search: "one.example")
        XCTAssertEqual(searched.first?.children?.count, 1)
        XCTAssertEqual(searched.first?.bytesIn, 500)
        let blocked = ConnectionLogRow.groups(connections: connections, totals: [total], decision: .deny)
        XCTAssertEqual(blocked.first?.children?.first?.connection?.action, .deny)
        XCTAssertEqual(blocked.first?.bytesIn, 500)
        XCTAssertTrue(ConnectionLogRow.groups(connections: [], totals: [total], search: "missing").isEmpty)
    }
    func testOlderSnapshotsDecodeWithoutInventingCumulativeRX() throws {
        let snapshot = ProviderSnapshot(policy: FirewallPolicy(), connections: [record(browser)], startedAt: Date(), activeFlowCount: 1)
        let encoder = JSONEncoder()
        let legacy = try WireCodec.decode(ProviderSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertNil(legacy.applicationTraffic)
        let rows = ConnectionLogRow.groups(connections: legacy.connections, totals: [])
        XCTAssertNil(rows.first?.bytesIn)
        let modern = ProviderSnapshot(policy: snapshot.policy, connections: snapshot.connections, startedAt: snapshot.startedAt,
            activeFlowCount: 1, trafficEpoch: UUID(), applicationTraffic: [.init(application: browser, bytesIn: 42)], untrackedTrafficFlowCount: 0)
        let decoded = try WireCodec.decode(ProviderSnapshot.self, from: encoder.encode(modern))
        XCTAssertEqual(decoded.applicationTraffic, modern.applicationTraffic)
        XCTAssertEqual(decoded.trafficEpoch, modern.trafficEpoch)
    }
}
