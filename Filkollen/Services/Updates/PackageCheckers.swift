import Foundation

/// Homebrew formulae and casks.
enum HomebrewChecker {
    static var brew: URL? { Shell.find("brew") }
    static let env = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1"]

    private struct Outdated: Decodable {
        let formulae: [Package]
        let casks: [Package]
    }

    private struct Package: Decodable {
        let name: String
        let installed: String
        let current: String

        enum CodingKeys: String, CodingKey {
            case name, installed_versions, current_version
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            current = (try? c.decode(String.self, forKey: .current_version)) ?? "?"
            // Formulae give an array; older brew versions give casks a plain string.
            if let list = try? c.decode([String].self, forKey: .installed_versions) {
                installed = list.last ?? "?"
            } else {
                installed = (try? c.decode(String.self, forKey: .installed_versions)) ?? "?"
            }
        }
    }

    static func check(refreshIndex: Bool) async throws -> [AppUpdate] {
        guard let brew else { return [] }
        if refreshIndex { _ = await Shell.run(brew, ["update", "--quiet"], env: env) }
        let out = await Shell.run(brew, ["outdated", "--json=v2"], env: env)
        guard out.ok, let start = out.text.firstIndex(of: "{") else {
            throw NSError(domain: "Homebrew", code: Int(out.status),
                          userInfo: [NSLocalizedDescriptionKey: out.text.isEmpty ? "brew outdated failed" : out.text])
        }
        let parsed = try JSONDecoder().decode(Outdated.self, from: Data(out.text[start...].utf8))
        let formulae = parsed.formulae.map {
            AppUpdate(name: $0.name, installed: $0.installed, available: $0.current, source: .homebrew, token: $0.name)
        }
        let casks = parsed.casks.map {
            AppUpdate(name: $0.name, installed: $0.installed, available: $0.current, source: .homebrew,
                      token: $0.name, isCask: true)
        }
        return (casks + formulae)
    }

    static func upgrade(_ updates: [AppUpdate]) async -> Shell.Output {
        guard let brew else { return Shell.Output(status: -1, text: "Homebrew not found") }
        let casks = updates.filter(\.isCask).compactMap(\.token)
        let formulae = updates.filter { !$0.isCask }.compactMap(\.token)
        var log = ""
        var status: Int32 = 0
        if !formulae.isEmpty {
            let r = await Shell.run(brew, ["upgrade", "--formula"] + formulae, env: env)
            log += r.text; if !r.ok { status = r.status }
        }
        if !casks.isEmpty {
            let r = await Shell.run(brew, ["upgrade", "--cask"] + casks, env: env)
            log += r.text; if !r.ok { status = r.status }
        }
        return Shell.Output(status: status, text: log)
    }
}

/// Mac App Store apps, via the `mas` command-line tool (brew install mas).
enum AppStoreChecker {
    static var mas: URL? { Shell.find("mas") }
    static let updatesPage = URL(string: "macappstore://showUpdatesPage")!

    static func check() async -> [AppUpdate] {
        guard let mas else { return [] }
        let out = await Shell.run(mas, ["outdated"])
        // "497799835 Xcode (15.0 -> 15.1)"
        let regex = try! NSRegularExpression(pattern: #"^\s*(\d+)\s+(.+?)\s+\((.+?)\s*->\s*(.+?)\)\s*$"#)
        return out.text.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
            func group(_ i: Int) -> String { Range(m.range(at: i), in: line).map { String(line[$0]) } ?? "" }
            return AppUpdate(name: group(2), installed: group(3), available: group(4), source: .appStore,
                             appURL: URL(fileURLWithPath: "/Applications/\(group(2)).app"), token: group(1))
        }
    }
}

/// macOS and Apple software updates, via `softwareupdate -l` (can take ~30 s).
enum MacOSUpdateChecker {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!

    static func check() async -> [AppUpdate] {
        guard let tool = Shell.find("softwareupdate") else { return [] }
        // Use the last background scan when there is one; otherwise ask Apple's servers.
        var fresh = await Shell.run(tool, ["--list", "--no-scan"])
        if !fresh.text.contains("Title:") {
            fresh = await Shell.run(tool, ["--list"])
        }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let installed = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"

        // "\tTitle: macOS Sonoma 14.5, Version: 14.5, Size: 123K, Recommended: YES, Action: restart,"
        return fresh.text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Title:") else { return nil }
            var fields: [String: String] = [:]
            for part in line.split(separator: ",") {
                let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { fields[kv[0]] = kv[1] }
            }
            guard let title = fields["Title"] else { return nil }
            return AppUpdate(name: title, installed: title.hasPrefix("macOS") ? installed : "",
                             available: fields["Version"] ?? "", source: .macOS, infoURL: settingsURL)
        }
    }
}
