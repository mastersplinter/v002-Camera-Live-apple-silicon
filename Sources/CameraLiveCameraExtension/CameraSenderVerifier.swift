import Foundation
import Security
import VirtualCameraShared

/// CMIO's optional signingID is not an authentication guarantee. Validate the
/// running sender supplied by CMIO against our app IDs and our signing team.
final class CameraSenderVerifier {
    private let requirement: SecRequirement?

    convenience init() { self.init(teamIdentifier: Self.ownTeamIdentifier()) }

    init(teamIdentifier: String?) {
        guard let teamIdentifier, teamIdentifier.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            requirement = nil
            return
        }
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and " +
            "(identifier \"\(VirtualCameraFormat.appIdentifier)\" or identifier \"\(VirtualCameraFormat.diagnosticsIdentifier)\")"
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(expression as CFString, [], &requirement)
        self.requirement = status == errSecSuccess ? requirement : nil
    }

    func status(for pid: pid_t) -> OSStatus {
        guard pid > 0, let requirement else { return errSecParam }
        var code: SecCode?
        // Camera extensions cannot read the host's bundle in /Applications or
        // the user's home directory. Validate the running signature supplied
        // by macOS instead of asking Security to open those files.
        let attributes: [CFString: Any] = [kSecGuestAttributePid: pid, kSecGuestAttributeDynamicCode: true]
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &code)
        guard status == errSecSuccess, let code else { return status == errSecSuccess ? errSecCSNoSuchCode : status }
        return SecCodeCheckValidity(code, [], requirement)
    }

    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?, staticCode: SecStaticCode?, information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
