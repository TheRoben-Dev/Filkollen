import Foundation

/// Build products, downloaded toolchain data and package-manager caches.
/// Each source says what it is and whether it comes back on its own, so the
/// user can judge the cost of removing it.
struct DeveloperScanner: Sendable {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    struct Source: Sendable {
        enum Mode: Sendable {
            /// The folder as one item.
            case whole
            /// Each entry inside as its own item (e.g. one per iOS version).
            case children
        }

        let group: String
        let path: String
        let mode: Mode
        let explanation: String
        /// Pre-selected only when it's re-created automatically and cheap to get back.
        let selected: Bool
        /// Bundle IDs of apps that use it; while one runs, the item is left unselected.
        var usedBy: [String] = []
    }

    static let xcode = ["com.apple.dt.Xcode"]
    static let simulator = ["com.apple.iphonesimulator", "com.apple.dt.Xcode"]

    static let sources: [Source] = [
        Source(group: "Xcode Archives", path: "Library/Developer/Xcode/Archives", mode: .children,
               explanation: "Builds you archived. Needed to symbolicate crash reports for versions you shipped; not re-created.",
               selected: false, usedBy: xcode),
        Source(group: "Device Support", path: "Library/Developer/Xcode/iOS DeviceSupport", mode: .children,
               explanation: "Debug symbols copied from an iPhone or iPad. Xcode copies them again the next time you connect that device.",
               selected: true, usedBy: xcode),
        Source(group: "Device Support", path: "Library/Developer/Xcode/watchOS DeviceSupport", mode: .children,
               explanation: "Debug symbols copied from an Apple Watch. Xcode copies them again when needed.",
               selected: true, usedBy: xcode),
        Source(group: "Device Support", path: "Library/Developer/Xcode/tvOS DeviceSupport", mode: .children,
               explanation: "Debug symbols copied from an Apple TV. Xcode copies them again when needed.",
               selected: true, usedBy: xcode),
        Source(group: "Device Support", path: "Library/Developer/Xcode/visionOS DeviceSupport", mode: .children,
               explanation: "Debug symbols copied from a Vision Pro. Xcode copies them again when needed.",
               selected: true, usedBy: xcode),
        Source(group: "Simulator Caches", path: "Library/Developer/CoreSimulator/Caches", mode: .whole,
               explanation: "Simulator dyld and runtime caches. Rebuilt the next time a simulator boots.",
               selected: true, usedBy: simulator),
        Source(group: "Xcode Previews", path: "Library/Developer/Xcode/UserData/Previews", mode: .whole,
               explanation: "SwiftUI preview simulators and builds. Rebuilt the next time you open a preview.",
               selected: true, usedBy: xcode),
        Source(group: "Swift Package Manager", path: "Library/Caches/org.swift.swiftpm", mode: .whole,
               explanation: "Downloaded Swift packages. Fetched again on the next resolve.",
               selected: true, usedBy: xcode),
        Source(group: "Homebrew", path: "Library/Caches/Homebrew", mode: .whole,
               explanation: "Downloaded bottles and sources. Homebrew downloads them again if it needs them.",
               selected: true),
        Source(group: "npm", path: ".npm/_cacache", mode: .whole,
               explanation: "npm's package cache. Packages are downloaded again on the next install.",
               selected: true),
        Source(group: "Yarn", path: "Library/Caches/Yarn", mode: .whole,
               explanation: "Yarn's package cache. Downloaded again on the next install.",
               selected: true),
        Source(group: "pnpm", path: "Library/pnpm/store", mode: .whole,
               explanation: "pnpm's content store. Projects that link into it need `pnpm install` again.",
               selected: false),
        Source(group: "pip", path: "Library/Caches/pip", mode: .whole,
               explanation: "pip's download and wheel cache. Downloaded again when needed.",
               selected: true),
        Source(group: "Cargo", path: ".cargo/registry/cache", mode: .whole,
               explanation: "Downloaded crate archives. Fetched again on the next build.",
               selected: true),
        Source(group: "Cargo", path: ".cargo/registry/src", mode: .whole,
               explanation: "Unpacked crate sources. Re-extracted from the cache or re-downloaded on the next build.",
               selected: true),
        Source(group: "Gradle", path: ".gradle/caches", mode: .whole,
               explanation: "Gradle's dependency and build cache. Rebuilt on the next build (slower first build).",
               selected: true),
        Source(group: "CocoaPods", path: "Library/Caches/CocoaPods", mode: .whole,
               explanation: "Downloaded pod specs and sources. Fetched again on the next `pod install`.",
               selected: true),
        Source(group: "Go", path: "Library/Caches/go-build", mode: .whole,
               explanation: "Go's build cache. Rebuilt on the next build.",
               selected: true),
        Source(group: "Go", path: "go/pkg/mod", mode: .whole,
               explanation: "Downloaded Go modules. Re-downloaded on the next build; offline builds need them.",
               selected: false),
    ]

    /// Entries of ~/Library/Caches this module reports, so System Junk doesn't list them twice.
    static var claimedCacheNames: Set<String> {
        Set(sources.compactMap { s in
            s.path.hasPrefix("Library/Caches/") ? String(s.path.dropFirst("Library/Caches/".count)) : nil
        })
    }

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress, counting: true)
        let running = Set(context.runningApps().map { $0.bundleID.lowercased() })
        var targets: [(URL, Source)] = []

        for source in Self.sources {
            let url = context.home.appendingPathComponent(source.path)
            guard fm.fileExists(atPath: url.path) else { continue }
            switch source.mode {
            case .whole:
                targets.append((url, source))
            case .children:
                let entries = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                targets += entries.map { ($0, source) }
            }
        }

        let items = parallelMap(targets) { [context] target -> JunkItem? in
            let (url, source) = target
            guard !context.isCancelled, fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.abbreviatedPath)
            let measured = FileSizer.measure(url, fileManager: fm)
            guard measured.allocated > 0 else { return nil }
            let user = source.usedBy.first { running.contains($0.lowercased()) }
            let userName = user.map { $0 == "com.apple.iphonesimulator" ? "Simulator" : "Xcode" }
            return JunkItem(
                url: url,
                size: measured.allocated,
                category: .developerJunk,
                group: source.group,
                detail: userName.map { "\($0) is running. Quit it first. " + source.explanation } ?? source.explanation,
                isSelected: source.selected && user == nil,
                modified: FileSizer.modificationDate(url),
                inUseBy: userName,
                reclaimable: measured.reclaimable
            )
        }.compactMap { $0 }

        if context.isCancelled { return [] }
        return items.sorted { $0.size > $1.size }
    }
}
