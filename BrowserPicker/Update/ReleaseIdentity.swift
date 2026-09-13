import Foundation
import Security

/// Keep this compatible with the published v1.0.20 designated requirement.
/// TCC uses this identity to carry privacy permissions across app updates.
enum ReleaseIdentity {
    static let bundleIdentifier = "com.browserpicker.app"
    static let teamIdentifier = "NZDMMFNMU4"
    static let designatedRequirement = #"anchor apple generic and identifier "com.browserpicker.app" and (certificate leaf[field.1.2.840.113635.100.6.1.9] exists or certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = NZDMMFNMU4)"#

    static func isValid(at url: URL) -> Bool {
        guard Bundle(url: url)?.bundleIdentifier == bundleIdentifier else { return false }

        var staticCode: SecStaticCode?
        var expected: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode,
              SecRequirementCreateWithString(designatedRequirement as CFString, [], &expected) == errSecSuccess,
              let expected else { return false }

        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate))
        guard SecStaticCodeCheckValidity(code, flags, expected) == errSecSuccess else { return false }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any],
              info[kSecCodeInfoTeamIdentifier as String] as? String == teamIdentifier else { return false }

        // A valid Developer ID signature alone is insufficient: a custom,
        // build-specific DR could still cause TCC to forget permissions.
        var actual: SecRequirement?
        var actualData: CFData?
        var expectedData: CFData?
        guard SecCodeCopyDesignatedRequirement(code, [], &actual) == errSecSuccess,
              let actual,
              SecRequirementCopyData(actual, [], &actualData) == errSecSuccess,
              SecRequirementCopyData(expected, [], &expectedData) == errSecSuccess,
              let actualData, let expectedData else { return false }
        return actualData == expectedData
    }
}
