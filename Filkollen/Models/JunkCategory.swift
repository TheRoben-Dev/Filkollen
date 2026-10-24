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
        case .systemJunk: return String(localized: "System Junk")
        case .appLeftovers: return String(localized: "App Leftovers")
        case .duplicatePhotos: return String(localized: "Duplicate Photos")
        case .duplicateFiles: return String(localized: "Duplicate Files")
        case .largeFiles: return String(localized: "Large & Old Files")
        case .developerJunk: return String(localized: "Developer Junk")
        case .oldInstallers: return String(localized: "Old Installers")
        case .iosBackups: return String(localized: "iOS Backups & Firmware")
        case .browserCaches: return String(localized: "Browser & Mail Caches")
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk: return String(localized: "Caches, logs and temporary files")
        case .appLeftovers: return String(localized: "Files left behind by apps you removed")
        case .duplicatePhotos: return String(localized: "Identical copies of the same image")
        case .duplicateFiles: return String(localized: "Identical copies of documents, videos, music and downloads")
        case .largeFiles: return String(localized: "Big files in your home folder you may not need")
        case .developerJunk: return String(localized: "Xcode, simulator and package-manager caches")
        case .oldInstallers: return String(localized: "Disk images and packages in Downloads you've already used")
        case .iosBackups: return String(localized: "iPhone and iPad backups and leftover update files")
        case .browserCaches: return String(localized: "Cached web content and opened attachments. Never history, cookies, passwords or mail")
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
}

extension JunkCategory {
    /// Grouped as "keep one, remove the rest".
    var isDuplicates: Bool { self == .duplicatePhotos || self == .duplicateFiles }
}
