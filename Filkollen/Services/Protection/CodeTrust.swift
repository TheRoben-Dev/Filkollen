import Foundation
import Security

/// Who signed a piece of code, and whether macOS would trust it. Read-only:
/// nothing here changes or launches what it checks.
enum CodeTrust {
    enum Level: Int, Comparable, Sendable {
        /// Broken signature: modified after signing, or a bad certificate.
        case invalid
        case unsigned
        /// Signed without an identity (common for things built locally or by Homebrew).
        case adHoc
        /// Developer ID signed, with no notarization ticket stapled. Checked offline,
        /// so a notarized app whose ticket only lives on Apple's servers lands here too.
        case developerID
        /// Mac App Store or other Apple-issued certificate.
        case appStore
        case notarized
        case apple

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .invalid: return "Signature broken"
            case .unsigned: return "Unsigned"
            case .adHoc: return "Ad-hoc signed"
            case .developerID: return "Developer ID"
            case .appStore: return "App Store"
            case .notarized: return "Notarized"
            case .apple: return "Apple"
            }
        }

        /// Worth a second look. Not proof of anything bad: plenty of legit tools are ad-hoc signed.
        var isConcerning: Bool { self <= .adHoc }
    }

    struct Report: Hashable, Sendable {
        let level: Level
        let teamID: String?
        let signer: String?
        /// Downloaded and still carries the com.apple.quarantine flag (never opened).
        let quarantined: Bool
    }

    /// Never ask Apple's servers (revocation or notarization lookups): Filkollen's
    /// only network destination is MalwareBazaar.
    private static let noNetwork = SecCSFlags.noNetworkAccess.rawValue

    private static func requirement(_ text: String) -> SecRequirement? {
        var req: SecRequirement?
        return SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess ? req : nil
    }

    private static let appleReq = requirement("anchor apple")
    private static let notarizedReq = requirement("notarized")
    private static let developerIDReq = requirement("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13]")
    private static let appStoreReq = requirement("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]")

    /// Checks an app bundle or a single executable. `deep` also validates every
    /// nested resource, which is slow for big apps; the default checks the main code.
    static func evaluate(_ url: URL, deep: Bool = false) -> Report {
        let quarantined = hasQuarantineFlag(url)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return Report(level: .unsigned, teamID: nil, signer: nil, quarantined: quarantined)
        }
        let flags = SecCSFlags(rawValue: (deep ? kSecCSCheckNestedCode | kSecCSStrictValidate : kSecCSDoNotValidateResources) | noNetwork)
        let basic = SecStaticCodeCheckValidity(code, flags, nil)

        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = (info as? [String: Any]) ?? [:]
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signer = certs?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        let codeFlags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0

        func report(_ level: Level) -> Report { Report(level: level, teamID: teamID, signer: signer, quarantined: quarantined) }

        if basic == errSecCSUnsigned { return report(.unsigned) }
        guard basic == errSecSuccess else { return report(.invalid) }
        if codeFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 || certs == nil { return report(.adHoc) }

        func satisfies(_ req: SecRequirement?) -> Bool {
            guard let req else { return false }
            return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources | noNetwork), req) == errSecSuccess
        }
        if satisfies(appleReq) { return report(.apple) }
        if satisfies(notarizedReq) { return report(.notarized) }
        if satisfies(appStoreReq) { return report(.appStore) }
        if satisfies(developerIDReq) { return report(.developerID) }
        return report(.adHoc)
    }

    static func hasQuarantineFlag(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) > 0
        }
    }
}
