import SwiftUI

enum JunkCategory: String, CaseIterable, Identifiable, Hashable {
    case systemJunk
    case appLeftovers
    case duplicatePhotos
    case duplicateFiles
    case largeFiles
    case developerJunk
    case oldInstallers
    case iosBackups
    case browserCaches

    var id: String { rawValue }

    /// What Smart Scan covers. Large files and duplicate files are your own data and
    /// developer caches can be slow to get back, so those are opt-in.
    static let smartScan: [JunkCategory] = [.systemJunk, .appLeftovers, .duplicatePhotos, .browserCaches]

    var title: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .appLeftovers: return "App Leftovers"
        case .duplicatePhotos: return "Duplicate Photos"
        case .duplicateFiles: return "Duplicate Files"
        case .largeFiles: return "Large & Old Files"
        case .developerJunk: return "Developer Junk"
        case .oldInstallers: return "Old Installers"
        case .iosBackups: return "iOS Backups & Firmware"
        case .browserCaches: return "Browser & Mail Caches"
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk: return "Caches, logs and temporary files"
        case .appLeftovers: return "Files left behind by apps you removed"
        case .duplicatePhotos: return "Identical copies of the same image"
        case .duplicateFiles: return "Identical copies of documents, videos, music and downloads"
        case .largeFiles: return "Big files in your home folder you may not need"
        case .developerJunk: return "Xcode, simulator and package-manager caches"
        case .oldInstallers: return "Disk images and packages in Downloads you've already used"
        case .iosBackups: return "iPhone and iPad backups and leftover update files"
        case .browserCaches: return "Cached web content and opened attachments. Never history, cookies, passwords or mail"
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk: return "trash.circle.fill"
        case .appLeftovers: return "shippingbox.circle.fill"
        case .duplicatePhotos: return "photo.on.rectangle.angled"
        case .duplicateFiles: return "doc.on.doc.fill"
        case .largeFiles: return "archivebox.fill"
        case .developerJunk: return "hammer.circle.fill"
        case .oldInstallers: return "shippingbox.and.arrow.backward.fill"
        case .iosBackups: return "iphone.circle.fill"
        case .browserCaches: return "globe"
        }
    }

    var scanningMessage: String {
        switch self {
        case .systemJunk: return "Looking for caches and logs…"
        case .appLeftovers: return "Matching leftovers against installed apps…"
        case .duplicatePhotos: return "Comparing photos…"
        case .duplicateFiles: return "Comparing files…"
        case .largeFiles: return "Looking for large files…"
        case .developerJunk: return "Looking for build caches and downloads…"
        case .oldInstallers: return "Checking Downloads for installers…"
        case .iosBackups: return "Looking for device backups…"
        case .browserCaches: return "Looking at browser caches…"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .systemJunk: return Theme.gradient(.pink, .orange)
        case .appLeftovers: return Theme.gradient(.teal, .blue)
        case .duplicatePhotos: return Theme.gradient(.purple, .indigo)
        case .duplicateFiles: return Theme.gradient(.indigo, .purple)
        case .largeFiles: return Theme.gradient(.yellow, .orange)
        case .developerJunk: return Theme.gradient(.blue, .cyan)
        case .oldInstallers: return Theme.gradient(.mint, .teal)
        case .iosBackups: return Theme.gradient(.gray, .blue)
        case .browserCaches: return Theme.gradient(.indigo, .blue)
        }
    }

    var tint: Color {
        switch self {
        case .systemJunk: return .pink
        case .appLeftovers: return .teal
        case .duplicatePhotos: return .purple
        case .duplicateFiles: return .purple
        case .largeFiles: return .orange
        case .developerJunk: return .cyan
        case .oldInstallers: return .mint
        case .iosBackups: return .blue
        case .browserCaches: return .indigo
        }
    }
}

extension JunkCategory {
    /// Grouped as "keep one, remove the rest".
    var isDuplicates: Bool { self == .duplicatePhotos || self == .duplicateFiles }
}
