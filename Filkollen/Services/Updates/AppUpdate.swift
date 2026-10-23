import Foundation

struct AppUpdate: Identifiable, Hashable, Sendable {
    enum Source: String, CaseIterable, Sendable {
        case apps = "Apps"
        case homebrew = "Homebrew"
        case appStore = "App Store"
        case macOS = "macOS"

        var symbol: String {
            switch self {
            case .apps: return "app.badge.fill"
            case .homebrew: return "mug.fill"
            case .appStore: return "bag.fill"
            case .macOS: return "apple.logo"
            }
        }
    }

    var id: String { "\(source.rawValue):\(token ?? name)" }
    let name: String
    let installed: String
    let available: String
    let source: Source
    /// The installed .app, used for its icon and to open it.
    var appURL: URL? = nil
    /// Release notes or download page.
    var infoURL: URL? = nil
    /// Homebrew formula/cask name or App Store id.
    var token: String? = nil
    var isCask = false
}

enum VersionCompare {
    /// True if `candidate` is newer than `installed` ("1.10" > "1.9", "2.0" > "2.0b3").
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = normalize(candidate), b = normalize(installed)
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }
        return a.compare(b, options: .numeric) == .orderedDescending
    }

    private static func normalize(_ v: String) -> String {
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        // Drop trailing ".0" so "2.0" equals "2".
        while s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }
}
