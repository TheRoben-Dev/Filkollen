import SwiftUI

enum JunkCategory: String, CaseIterable, Identifiable, Hashable {
    case systemJunk
    case appLeftovers
    case duplicatePhotos
    case largeFiles

    var id: String { rawValue }

    /// What Smart Scan covers. Large files are your own data, so they're opt-in.
    static let smartScan: [JunkCategory] = [.systemJunk, .appLeftovers, .duplicatePhotos]

    var title: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .appLeftovers: return "App Leftovers"
        case .duplicatePhotos: return "Duplicate Photos"
        case .largeFiles: return "Large & Old Files"
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk: return "Caches, logs and temporary files"
        case .appLeftovers: return "Files left behind by apps you removed"
        case .duplicatePhotos: return "Identical copies of the same image"
        case .largeFiles: return "Big files in your home folder you may not need"
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk: return "trash.circle.fill"
        case .appLeftovers: return "shippingbox.circle.fill"
        case .duplicatePhotos: return "photo.on.rectangle.angled"
        case .largeFiles: return "archivebox.fill"
        }
    }

    var scanningMessage: String {
        switch self {
        case .systemJunk: return "Looking for caches and logs…"
        case .appLeftovers: return "Matching leftovers against installed apps…"
        case .duplicatePhotos: return "Comparing photos…"
        case .largeFiles: return "Looking for large files…"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .systemJunk: return Theme.gradient(.pink, .orange)
        case .appLeftovers: return Theme.gradient(.teal, .blue)
        case .duplicatePhotos: return Theme.gradient(.purple, .indigo)
        case .largeFiles: return Theme.gradient(.yellow, .orange)
        }
    }

    var tint: Color {
        switch self {
        case .systemJunk: return .pink
        case .appLeftovers: return .teal
        case .duplicatePhotos: return .purple
        case .largeFiles: return .orange
        }
    }
}
