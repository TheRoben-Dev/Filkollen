import SwiftUI

enum JunkCategory: String, CaseIterable, Identifiable, Hashable {
    case systemJunk
    case appLeftovers
    case duplicatePhotos
    case largeFiles
    case developerJunk
    case oldInstallers

    var id: String { rawValue }

    /// What Smart Scan covers. Large files are your own data and developer caches
    /// can be slow to get back, so both are opt-in.
    static let smartScan: [JunkCategory] = [.systemJunk, .appLeftovers, .duplicatePhotos]

    var title: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .appLeftovers: return "App Leftovers"
        case .duplicatePhotos: return "Duplicate Photos"
        case .largeFiles: return "Large & Old Files"
        case .developerJunk: return "Developer Junk"
        case .oldInstallers: return "Old Installers"
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk: return "Caches, logs and temporary files"
        case .appLeftovers: return "Files left behind by apps you removed"
        case .duplicatePhotos: return "Identical copies of the same image"
        case .largeFiles: return "Big files in your home folder you may not need"
        case .developerJunk: return "Xcode, simulator and package-manager caches"
        case .oldInstallers: return "Disk images and packages in Downloads you've already used"
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk: return "trash.circle.fill"
        case .appLeftovers: return "shippingbox.circle.fill"
        case .duplicatePhotos: return "photo.on.rectangle.angled"
        case .largeFiles: return "archivebox.fill"
        case .developerJunk: return "hammer.circle.fill"
        case .oldInstallers: return "shippingbox.and.arrow.backward.fill"
        }
    }

    var scanningMessage: String {
        switch self {
        case .systemJunk: return "Looking for caches and logs…"
        case .appLeftovers: return "Matching leftovers against installed apps…"
        case .duplicatePhotos: return "Comparing photos…"
        case .largeFiles: return "Looking for large files…"
        case .developerJunk: return "Looking for build caches and downloads…"
        case .oldInstallers: return "Checking Downloads for installers…"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .systemJunk: return Theme.gradient(.pink, .orange)
        case .appLeftovers: return Theme.gradient(.teal, .blue)
        case .duplicatePhotos: return Theme.gradient(.purple, .indigo)
        case .largeFiles: return Theme.gradient(.yellow, .orange)
        case .developerJunk: return Theme.gradient(.blue, .cyan)
        case .oldInstallers: return Theme.gradient(.mint, .teal)
        }
    }

    var tint: Color {
        switch self {
        case .systemJunk: return .pink
        case .appLeftovers: return .teal
        case .duplicatePhotos: return .purple
        case .largeFiles: return .orange
        case .developerJunk: return .cyan
        case .oldInstallers: return .mint
        }
    }
}
