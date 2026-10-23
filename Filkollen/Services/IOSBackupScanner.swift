import Foundation

/// iPhone/iPad backups made by Finder, and firmware files (.ipsw) left behind
/// by updates and restores. Backups are never pre-selected: they may be the
/// only copy of a device's data.
struct IOSBackupScanner: Sendable {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    struct BackupInfo: Equatable, Sendable {
        var deviceName: String?
        var productType: String?
        var productVersion: String?
        var lastBackup: Date?
        var isEncrypted = false
    }

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress, counting: true)
        var items: [JunkItem] = []

        // Backups: one folder per device (plus dated copies Finder sometimes keeps).
        let backupRoot = context.library("Application Support/MobileSync/Backup")
        let backups = (try? fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let infos = backups.map { ($0, Self.info(for: $0)) }
        // The newest backup of each device gets a note; older ones are clearly older.
        var newest: [String: Date] = [:]
        for (_, info) in infos {
            guard let name = info.deviceName, let date = info.lastBackup else { continue }
            newest[name] = max(newest[name] ?? .distantPast, date)
        }
        for (url, info) in infos {
            if context.isCancelled { return [] }
            throttle.report(url.lastPathComponent)
            let measured = FileSizer.measure(url, fileManager: fm)
            guard measured.allocated > 0 else { continue }
            let isLatest = info.deviceName.flatMap { newest[$0] } == info.lastBackup && info.lastBackup != nil
            items.append(JunkItem(
                url: url,
                size: measured.allocated,
                category: .iosBackups,
                group: "Device Backups",
                detail: Self.describe(info, isLatest: isLatest),
                isSelected: false,
                modified: info.lastBackup,
                reclaimable: measured.reclaimable
            ))
        }

        // Firmware: Finder re-downloads it whenever it's needed.
        let firmwareFolders = ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"]
            .map { context.library("iTunes/\($0)") } + [context.home.appendingPathComponent("Downloads")]
        for folder in firmwareFolders {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for file in files where file.pathExtension.lowercased() == "ipsw" {
                if context.isCancelled { return [] }
                throttle.report(file.abbreviatedPath)
                let measured = FileSizer.measure(file, fileManager: fm)
                guard measured.allocated > 0 else { continue }
                items.append(JunkItem(
                    url: file,
                    size: measured.allocated,
                    category: .iosBackups,
                    group: "Firmware Files",
                    detail: "iOS/iPadOS firmware. Finder downloads it again if a restore or update needs it.",
                    modified: FileSizer.modificationDate(file),
                    reclaimable: measured.reclaimable
                ))
            }
        }
        return items.sorted { ($0.group, $1.size) < ($1.group, $0.size) }
    }

    /// Reads the backup's Info.plist (device name, model, iOS version, date) and Manifest.plist (encryption).
    static func info(for backup: URL) -> BackupInfo {
        var info = BackupInfo()
        if let data = try? Data(contentsOf: backup.appendingPathComponent("Info.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            info.deviceName = plist["Device Name"] as? String ?? plist["Display Name"] as? String
            info.productType = plist["Product Type"] as? String
            info.productVersion = plist["Product Version"] as? String
            info.lastBackup = plist["Last Backup Date"] as? Date
        }
        if let data = try? Data(contentsOf: backup.appendingPathComponent("Manifest.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            info.isEncrypted = plist["IsEncrypted"] as? Bool ?? false
        }
        return info
    }

    static func describe(_ info: BackupInfo, isLatest: Bool) -> String {
        var parts: [String] = [info.deviceName ?? "Unknown device"]
        if let version = info.productVersion { parts.append("iOS \(version)") }
        if let date = info.lastBackup { parts.append("backed up \(date.formatted(date: .abbreviated, time: .omitted))") }
        if info.isEncrypted { parts.append("encrypted") }
        if isLatest { parts.append("latest backup of this device") }
        return parts.joined(separator: " · ")
    }
}
