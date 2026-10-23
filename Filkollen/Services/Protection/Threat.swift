import Foundation

struct Threat: Identifiable, Hashable, Sendable {
    enum Engine: String, Codable, Sendable {
        case malwareBazaar = "MalwareBazaar"
        case clamAV = "ClamAV"
    }

    var id: URL { url }
    let url: URL
    let size: Int64
    let engine: Engine
    /// SHA-256 for hash matches, signature name for ClamAV.
    let identifier: String

    var name: String { url.lastPathComponent }

    /// Link to the public sample report, so the user can see what it is.
    var reportURL: URL? {
        guard engine == .malwareBazaar else { return nil }
        return URL(string: "https://bazaar.abuse.ch/sample/\(identifier)/")
    }
}
