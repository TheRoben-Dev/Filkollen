import Foundation
import UniformTypeIdentifiers

/// Big or long-unused files in your home folder that might not be worth
/// keeping, grouped by kind. Never pre-selected: these are your files, not junk.
struct LargeFileScanner {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }
    private var home: URL { context.home }

    /// Old files smaller than this aren't worth listing, however old they are.
    static let oldFileMinBytes: Int64 = 50 * 1_048_576

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress, counting: true)
        let minSize = context.largeFileMinBytes
        let oldCutoff = context.largeFileMinAge.map { context.now().addingTimeInterval(-$0) }
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .contentAccessDateKey, .contentModificationDateKey,
            .mayShareFileContentKey, .linkCountKey, .contentTypeKey,
        ]
        let keySet = Set(keys)
        let skipTopLevel: Set<String> = ["Library", ".Trash"]
        var items: [JunkItem] = []

        guard let enumerator = fm.enumerator(
            at: home, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        for case let url as URL in enumerator {
            if context.isCancelled { return [] }
            if enumerator.level == 1, skipTopLevel.contains(url.lastPathComponent) {
                enumerator.skipDescendants(); continue
            }
            throttle.report(url.abbreviatedPath)
            guard let v = try? url.resourceValues(forKeys: keySet), v.isRegularFile == true,
                  let size = v.totalFileAllocatedSize.map(Int64.init) else { continue }

            let lastUsed = [v.contentAccessDate, v.contentModificationDate].compactMap { $0 }.max()
            let isLarge = size >= minSize
            let isOld = oldCutoff.map { cutoff in size >= Self.oldFileMinBytes && (lastUsed ?? .distantPast) < cutoff } ?? false
            guard isLarge || isOld else { continue }

            let when = lastUsed.map { "last opened \($0.formatted(.relative(presentation: .named)))" } ?? "never opened"
            items.append(JunkItem(
                url: url,
                size: size,
                category: .largeFiles,
                group: Self.kind(of: v.contentType, ext: url.pathExtension),
                detail: "\(url.deletingLastPathComponent().abbreviatedPath) · \(when)",
                isSelected: false,
                modified: lastUsed,
                // A clone or an extra hard link gives nothing back when deleted.
                reclaimable: v.mayShareFileContent == true || (v.linkCount ?? 1) > 1 ? 0 : nil
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// A human group name for a file type.
    static func kind(of type: UTType?, ext: String) -> String {
        let type = type ?? UTType(filenameExtension: ext)
        guard let type else { return "Other" }
        let groups: [(UTType, String)] = [
            (.movie, "Videos"), (.audio, "Music & Audio"), (.image, "Photos & Images"),
            (.diskImage, "Disk Images"), (.archive, "Archives"), (.pdf, "Documents"),
            (.presentation, "Documents"), (.spreadsheet, "Documents"), (.text, "Documents"),
            (.application, "Apps"), (.database, "Databases"),
        ]
        if type.conforms(to: .movie) { return "Videos" }
        for (parent, name) in groups where type.conforms(to: parent) { return name }
        if ["iso", "dmg", "img", "vmdk", "vdi", "qcow2", "ipsw"].contains(ext.lowercased()) { return "Disk Images" }
        if type.conforms(to: .data), ["docx", "doc", "pages", "key", "numbers", "xlsx", "pptx"].contains(ext.lowercased()) {
            return "Documents"
        }
        return "Other"
    }
}
