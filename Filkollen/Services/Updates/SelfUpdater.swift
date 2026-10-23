import Sparkle
import SwiftUI

/// Filkollen's own updates, through Sparkle 2. Dormant (no updater, no network)
/// until an appcast URL and EdDSA public key are set in project.yml, and even
/// then it only checks on its own if you turn that on.
@MainActor
final class SelfUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    static func isConfigured(_ info: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        let feed = (info?["SUFeedURL"] as? String) ?? ""
        let key = (info?["SUPublicEDKey"] as? String) ?? ""
        return feed.hasPrefix("https://") && !key.isEmpty
    }

    init() {
        controller = Self.isConfigured() && !AppEnvironment.isRunningTests
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
