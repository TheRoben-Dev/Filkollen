import Foundation

/// Checks new files in Downloads against the offline threat database as they
/// arrive. Off by default. Only looks and notifies: it never moves a file, and
/// it makes no network calls (the database is the one already downloaded).
final class DownloadsWatcher: @unchecked Sendable {
    private let folder: URL
    private let database: ThreatDatabase
    private let onThreats: @Sendable ([Threat]) -> Void
    private let queue = DispatchQueue(label: "Filkollen.DownloadsWatcher", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    /// path → modification time already checked.
    private var checked: [String: Date] = [:]

    /// Still being written by a browser; checked once renamed to the final name.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]
    static let maxFileSize = 256 * 1024 * 1024

    init(folder: URL, database: ThreatDatabase = .shared, onThreats: @escaping @Sendable ([Threat]) -> Void) {
        self.folder = folder
        self.database = database
        self.onThreats = onThreats
    }

    deinit { source?.cancel() }

    var isRunning: Bool { queue.sync { source != nil } }

    func start() {
        queue.async { [self] in
            guard source == nil else { return }
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { Log.protection.error("Downloads watcher couldn't open the folder"); return }
            // What's there now is the baseline; only new or changed files are checked.
            for (url, date) in Self.entries(in: folder) { checked[url.path] = date }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
            src.setEventHandler { [weak self] in self?.scheduleCheck() }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
            Log.protection.info("Watching Downloads for new threats")
        }
    }

    func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
            pending?.cancel()
            checked = [:]
        }
    }

    /// Waits for a burst of writes (a download finishing) to settle.
    private func scheduleCheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkNow() }
        pending = work
        queue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Visible for tests: checks anything new since the last call and reports matches.
    func checkNow() {
        let fresh = Self.entries(in: folder).filter { checked[$0.url.path] != $0.modified }
        guard !fresh.isEmpty else { return }
        for entry in fresh { checked[entry.url.path] = entry.modified }
        do { try database.load() } catch { return } // no (or a damaged) database: nothing to compare with
        let threats = Self.match(fresh.map(\.url), table: database.snapshot())
        database.unload()
        if !threats.isEmpty {
            Log.protection.notice("Downloads watcher found \(threats.count) known threat(s)")
            onThreats(threats)
        }
    }

    static func match(_ urls: [URL], table: [ThreatDatabase.Digest]) -> [Threat] {
        guard !table.isEmpty else { return [] }
        return urls.compactMap { url in
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size > 0, size <= maxFileSize,
                  let digest = MalwareScanner.sha256(url), ThreatDatabase.contains(digest, in: table) else { return nil }
            return Threat(url: url, size: Int64(size), engine: .malwareBazaar, identifier: digest.hex)
        }
    }

    /// Top-level regular files in the folder, skipping partial downloads and inert types.
    static func entries(in folder: URL) -> [(url: URL, modified: Date)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard !partialExtensions.contains(ext), !MalwareScanner.inertExtensions.contains(ext),
                  let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { return nil }
            return (url, v.contentModificationDate ?? .distantPast)
        }
    }
}
