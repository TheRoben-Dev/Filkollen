import Foundation

/// Runs command-line tools (brew, mas, softwareupdate, launchctl) off the main thread.
enum Shell {
    struct Output: Sendable {
        let status: Int32
        let text: String
        var ok: Bool { status == 0 }
    }

    static let toolPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/usr/sbin", "/bin"]

    static func find(_ tool: String) -> URL? {
        toolPaths.map { URL(fileURLWithPath: $0).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func run(_ tool: URL, _ args: [String], env extra: [String: String] = [:]) async -> Output {
        await Task.detached(priority: .utility) {
            let p = Process()
            let pipe = Pipe()
            p.executableURL = tool
            p.arguments = args
            p.standardOutput = pipe
            p.standardError = pipe
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = toolPaths.joined(separator: ":")
            env.merge(extra) { _, new in new }
            p.environment = env
            do {
                try p.run()
            } catch {
                return Output(status: -1, text: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Output(status: p.terminationStatus, text: String(decoding: data, as: UTF8.self))
        }.value
    }
}
