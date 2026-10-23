import Foundation

/// Launch agents and daemons: the things that start with the Mac.
struct StartupItem: Identifiable, Hashable {
    enum Scope: String {
        case userAgent = "Your Launch Agents"
        case systemAgent = "System Launch Agents"
        case systemDaemon = "System Launch Daemons"

        var removable: Bool { self == .userAgent }
    }

    var id: URL { plist }
    let plist: URL
    let label: String
    let program: String?
    let scope: Scope
    let disabled: Bool
    let runAtLoad: Bool
    /// The executable it points to is gone, usually because its app was deleted.
    let isBroken: Bool
    let ownerName: String?

    var displayName: String { ownerName ?? label }
}

enum StartupItems {
    static func load() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sources: [(URL, StartupItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon),
        ]
        var items: [StartupItem] = []
        for (dir, scope) in sources {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension == "plist" {
                if let item = parse(file, scope: scope) { items.append(item) }
            }
        }
        return items.sorted { ($0.scope.rawValue, $0.displayName.lowercased()) < ($1.scope.rawValue, $1.displayName.lowercased()) }
    }

    private static func parse(_ url: URL, scope: StartupItem.Scope) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
        // BundleProgram is relative to an app bundle we can't locate here, so don't call it broken.
        let broken = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false

        return StartupItem(
            plist: url,
            label: label,
            program: program,
            scope: scope,
            disabled: plist["Disabled"] as? Bool ?? false,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
            isBroken: broken,
            ownerName: AppNames.friendlyName(for: label) ?? ownerFromProgram(program)
        )
    }

    /// "/Applications/Foo.app/Contents/..." → "Foo"
    private static func ownerFromProgram(_ program: String?) -> String? {
        guard let program, let range = program.range(of: ".app/") else { return nil }
        return (String(program[..<range.lowerBound]) as NSString).lastPathComponent
    }

    /// Unloads a user agent and moves its plist to the Trash.
    static func remove(_ item: StartupItem) async throws {
        guard item.scope.removable else { throw CocoaError(.fileWriteNoPermission) }
        if let launchctl = Shell.find("launchctl") {
            _ = await Shell.run(launchctl, ["bootout", "gui/\(getuid())", item.plist.path])
        }
        try FileManager.default.trashItem(at: item.plist, resultingItemURL: nil)
    }
}
