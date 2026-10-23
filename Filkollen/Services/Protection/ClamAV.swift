import Foundation

/// Optional deeper scan using a locally installed ClamAV (`brew install clamav`).
///
/// ClamAV's signatures catch variants and packed samples that an exact-hash
/// list can't, but bundling libclamav (GPL, ~300 MB of signatures) isn't
/// worth it for v1, so we shell out when it's present.
enum ClamAV {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]

    static var clamscan: URL? { find("clamscan") }
    static var freshclam: URL? { find("freshclam") }
    static var isInstalled: Bool { clamscan != nil }

    private static func find(_ tool: String) -> URL? {
        searchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    struct Detection: Sendable {
        let url: URL
        let signature: String
    }

    /// Scans the given folders; returns infected files. Exit code 1 means "found something".
    static func scan(_ roots: [URL], progress: @escaping @Sendable (String) -> Void) throws -> [Detection] {
        guard let clamscan else { return [] }
        progress("ClamAV is scanning… this can take a while")
        let output = try run(clamscan, ["--infected", "--no-summary", "--recursive", "--max-filesize=200M"]
            + roots.map(\.path))
        guard output.status == 0 || output.status == 1 else {
            throw NSError(domain: "ClamAV", code: Int(output.status),
                          userInfo: [NSLocalizedDescriptionKey: output.text.isEmpty
                                     ? "clamscan failed (has freshclam been run?)" : output.text])
        }
        // Lines look like: "/path/to/file: Osx.Trojan.Generic-123 FOUND"
        return output.text.split(separator: "\n").compactMap { line in
            guard line.hasSuffix(" FOUND"), let sep = line.range(of: ": ", options: .backwards) else { return nil }
            let path = String(line[..<sep.lowerBound])
            let sig = String(line[sep.upperBound...].dropLast(" FOUND".count))
            return Detection(url: URL(fileURLWithPath: path), signature: sig)
        }
    }

    /// Where Homebrew and MacPorts keep ClamAV's signature databases.
    static let databaseDirectories = ["/opt/homebrew/var/lib/clamav", "/usr/local/var/lib/clamav", "/opt/local/share/clamav"]

    /// When the newest signature file (daily.cvd / daily.cld) was written, nil if none.
    /// Filkollen doesn't run freshclam itself: it only talks to MalwareBazaar.
    static func signaturesDate(in dirs: [String] = databaseDirectories) -> Date? {
        dirs.flatMap { dir in ["daily.cld", "daily.cvd", "main.cld", "main.cvd"].map { "\(dir)/\($0)" } }
            .compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date }
            .max()
    }

    private static func run(_ tool: URL, _ args: [String]) throws -> (status: Int32, text: String) {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = tool
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
