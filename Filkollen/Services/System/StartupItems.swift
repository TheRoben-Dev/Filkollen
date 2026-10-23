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
    /// What actually runs: the program, or the script an interpreter is given.
    var target: String? = nil
    /// Signature of `target`; nil when it can't be located.
    var trust: CodeTrust.Report? = nil
    /// Runs from a temp, shared or hidden folder, where legitimate software rarely lives.
    var oddLocation: Bool = false
    /// `target` is a script run by an interpreter (sh, python, osascript…).
    var isScript: Bool = false

    var displayName: String { ownerName ?? label }

    /// Worth a look: unsigned or broken code, a script, or an odd location. Not a verdict.
    var needsReview: Bool { oddLocation || isScript || (trust?.level.isConcerning ?? false) }
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
        let arguments = plist["ProgramArguments"] as? [String] ?? []
        let program = plist["Program"] as? String ?? arguments.first
        // BundleProgram is relative to an app bundle we can't locate here, so don't call it broken.
        let broken = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
        let (target, isScript) = runTarget(program: program, arguments: arguments)
        let trust = target.flatMap { path -> CodeTrust.Report? in
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
            return CodeTrust.evaluate(URL(fileURLWithPath: path))
        }

        return StartupItem(
            plist: url,
            label: label,
            program: program,
            scope: scope,
            disabled: plist["Disabled"] as? Bool ?? false,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
            isBroken: broken,
            ownerName: AppNames.friendlyName(for: label) ?? ownerFromProgram(program),
            target: target,
            trust: trust,
            oddLocation: target.map(isOddLocation) ?? false,
            isScript: isScript
        )
    }

    static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "tcsh", "csh", "python", "python3", "perl", "ruby", "node",
        "osascript", "php", "env",
    ]

    /// For `/bin/sh -c …` or `/usr/bin/python3 /path/x.py`, what runs is the script.
    static func runTarget(program: String?, arguments: [String]) -> (target: String?, isScript: Bool) {
        guard let program else { return (nil, false) }
        let name = (program as NSString).lastPathComponent
        guard interpreters.contains(name) || name.hasPrefix("python") else { return (program, false) }
        let rest = arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if name == "env", let first = rest.first {
            return runTarget(program: first, arguments: Array(rest))
        }
        // An inline command (`sh -c "…"`) has no file to check; show the interpreter but flag it.
        let script = rest.first { $0.hasPrefix("/") || $0.hasPrefix("~") }
        return (script.map { ($0 as NSString).expandingTildeInPath } ?? program, true)
    }

    /// Temp folders, /Users/Shared and hidden folders are where droppers park payloads.
    static func isOddLocation(_ path: String) -> Bool {
        let p = path.lowercased()
        for prefix in ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/users/shared/", "/var/folders/", "/private/var/folders/"]
        where p.hasPrefix(prefix) { return true }
        return path.split(separator: "/").dropLast().contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
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
