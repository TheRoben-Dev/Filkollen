import Darwin
import Foundation

struct SystemSnapshot: Equatable {
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    var load: Double = 0
    var cpuCount = 0
    var uptime: TimeInterval = 0
    var osVersion = ""
    var trashSize: Int64 = 0

    var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }
    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    /// 1-minute load average relative to core count, clamped to 0…1.
    var cpuFraction: Double { cpuCount > 0 ? min(1, load / Double(cpuCount)) : 0 }
}

enum SystemInfo {
    static var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    /// Cheap enough to call every few seconds, except the Trash size, which is opt-in.
    static func snapshot(includeTrash: Bool = false) -> SystemSnapshot {
        var s = SystemSnapshot()
        let info = ProcessInfo.processInfo

        if let v = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        ) {
            s.diskTotal = Int64(v.volumeTotalCapacity ?? 0)
            s.diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
        }

        s.memoryTotal = info.physicalMemory
        s.memoryUsed = usedMemory()

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { s.load = loads[0] }
        s.cpuCount = info.activeProcessorCount
        s.uptime = info.systemUptime

        let v = info.operatingSystemVersion
        s.osVersion = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")

        if includeTrash { s.trashSize = FileSizer.allocatedSize(of: trashURL) }
        return s
    }

    /// Active + wired + compressed pages, which is roughly what Activity Monitor calls "Memory Used".
    private static func usedMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    /// Permanently empties the user's Trash. Callers must confirm with the user first.
    static func emptyTrash() -> (freed: Int64, failed: Int) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)) ?? []
        var freed: Int64 = 0
        var failed = 0
        for item in items {
            let size = FileSizer.allocatedSize(of: item)
            do {
                try fm.removeItem(at: item)
                freed += size
            } catch {
                failed += 1
            }
        }
        return (freed, failed)
    }
}

extension TimeInterval {
    /// "3 d 4 h", "5 h 12 min"
    var uptimeString: String {
        let f = DateComponentsFormatter()
        f.allowedUnits = self >= 86_400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: self) ?? ""
    }
}

extension UInt64 {
    var formattedMemory: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory) }
}
