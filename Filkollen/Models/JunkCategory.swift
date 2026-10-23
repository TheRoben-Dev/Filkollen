import SwiftUI

enum JunkCategory: String, CaseIterable, Identifiable, Hashable {
    case systemJunk
    case appLeftovers
    case duplicatePhotos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .appLeftovers: return "App Leftovers"
        case .duplicatePhotos: return "Duplicate Photos"
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk: return "Caches, logs and temporary files"
        case .appLeftovers: return "Files left behind by apps you removed"
        case .duplicatePhotos: return "Identical copies of the same image"
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk: return "trash.circle.fill"
        case .appLeftovers: return "shippingbox.circle.fill"
        case .duplicatePhotos: return "photo.on.rectangle.angled"
        }
    }

    var scanningMessage: String {
        switch self {
        case .systemJunk: return "Looking for caches and logs…"
        case .appLeftovers: return "Matching leftovers against installed apps…"
        case .duplicatePhotos: return "Comparing photos…"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .systemJunk: return Theme.gradient(.pink, .orange)
        case .appLeftovers: return Theme.gradient(.teal, .blue)
        case .duplicatePhotos: return Theme.gradient(.purple, .indigo)
        }
    }

    var tint: Color {
        switch self {
        case .systemJunk: return .pink
        case .appLeftovers: return .teal
        case .duplicatePhotos: return .purple
        }
    }
}
