import Foundation
import Security

enum IdentityResolver {
    static func application(at url: URL) throws -> ApplicationIdentity {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw identityError(status) }
        var info: CFDictionary?
        let result = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        if result == errSecSuccess, let info {
            return try identity(info: info as NSDictionary, verifies: { requirement in
                SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
            })
        }
        throw NSError(domain: "org.openfirewall.identity", code: Int(result), userInfo: [NSLocalizedDescriptionKey:
            "This executable has no usable code signature. Sign a local tool with an ad-hoc signature to create a build-pinned rule."])
    }

    static func application(auditToken: Data?) -> ApplicationIdentity {
        guard let auditToken, auditToken.count == 32 else { return .unidentified }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: auditToken] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return .unidentified }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unidentified }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info else { return .unidentified }
        return (try? identity(info: info as NSDictionary, verifies: { requirement in
            SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        })) ?? .unidentified
    }

    private static func identity(info: NSDictionary, verifies: (SecRequirement?) -> Bool) throws -> ApplicationIdentity {
        let executable = (info[kSecCodeInfoMainExecutable] as? URL)?.path ?? ""
        let identifier = info[kSecCodeInfoIdentifier] as? String
        let team = info[kSecCodeInfoTeamIdentifier] as? String
        for anchor in ["anchor apple generic", "anchor apple"] {
            var requirement: SecRequirement?
            if SecRequirementCreateWithString(anchor as CFString, [], &requirement) == errSecSuccess,
               verifies(requirement), let identifier, !identifier.isEmpty {
                let signer = team ?? "apple-platform"
                return ApplicationIdentity(id: "signed:\(signer):\(identifier)", name: displayName(executable), path: executable,
                                           signingIdentifier: identifier, teamIdentifier: signer, isVerifiedSigner: true)
            }
        }
        guard verifies(nil), let hash = info[kSecCodeInfoUnique] as? Data, !hash.isEmpty else {
            throw identityError(errSecCSUnsigned)
        }
        return ApplicationIdentity(id: "cdhash:\(hash.map { String(format: "%02x", $0) }.joined())",
                                   name: displayName(executable), path: executable, signingIdentifier: identifier)
    }

    static func displayName(_ path: String) -> String {
        guard !path.isEmpty else { return "Unidentified process" }
        var partial = ""
        for component in URL(fileURLWithPath: path).pathComponents {
            partial = (partial as NSString).appendingPathComponent(component)
            if component.hasSuffix(".app") {
                let bundle = Bundle(path: partial)
                return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? URL(fileURLWithPath: component).deletingPathExtension().lastPathComponent
            }
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func identityError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            SecCopyErrorMessageString(status, nil) as String? ?? "Could not verify this application's identity."])
    }
}
