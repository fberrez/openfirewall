import Foundation
import Darwin

/// Exercises Security.framework against real signatures and this running process.
/// The script signs this probe ad hoc with an Apple-looking identifier on purpose.
@main
struct IdentitySmoke {
    static func main() throws {
        let ownURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let selected = try IdentityResolver.application(at: ownURL)
        precondition(selected.id.hasPrefix("cdhash:"), "An ad-hoc identifier must not gain a trusted signer identity")
        precondition(!selected.isVerifiedSigner)

        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &token) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        precondition(status == KERN_SUCCESS, "Could not read own audit token")
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        let attributed = IdentityResolver.application(auditToken: tokenData)
        precondition(attributed.id == selected.id, "Selected executable and attributed flow must resolve to the same rule key")
        precondition(IdentityResolver.application(auditToken: Data([1, 2])).id == ApplicationIdentity.unidentified.id)

        let apple = try IdentityResolver.application(at: URL(fileURLWithPath: "/System/Applications/Notes.app"))
        precondition(apple.isVerifiedSigner && apple.id.hasPrefix("signed:"))
        precondition(apple.signingIdentifier == "com.apple.Notes")
        precondition(apple.id != selected.id, "An identifier alone cannot impersonate a signed Apple app")
        print("Identity checks passed: audit-token attribution matches static selection; ad-hoc spoofing stays hash-pinned; Apple signature verified; malformed token rejected.")
    }
}
