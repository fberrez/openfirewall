import Foundation

enum ProductConfiguration {
    static var appIdentifier: String { Bundle.main.object(forInfoDictionaryKey: "FirewallAppIdentifier") as? String ?? "org.openfirewall.app" }
    static var filterIdentifier: String { Bundle.main.object(forInfoDictionaryKey: "FirewallFilterIdentifier") as? String ?? "org.openfirewall.filter" }
    static var teamIdentifier: String { Bundle.main.object(forInfoDictionaryKey: "SigningTeamIdentifier") as? String ?? "" }
    static var serviceName: String { Bundle.main.object(forInfoDictionaryKey: "FirewallMachService") as? String ?? "" }
    static let policyKey = "FirewallPolicy"
    static let ownerKey = "OwnerUID"

    static func requirement(for identifier: String) -> String? {
        let team = teamIdentifier
        guard team.count == 10, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

@objc protocol FirewallControlProtocol {
    func snapshot(reply: @escaping (Data?, String?) -> Void)
    func applyPolicy(_ data: Data, reply: @escaping (String?) -> Void)
    func clearHistory(reply: @escaping () -> Void)
}
