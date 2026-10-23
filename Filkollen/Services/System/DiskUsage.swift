import Foundation

/// Sizes of a folder's direct children, for the Disk Usage map. Read-only.
enum DiskUsage {
    struct Entry: Identifiable, Hashable, Sendable {
        var id: URL { url }
        let url: URL
        let size: Int64
        let isFolder: Bool
        var name: String { url.lastPathComponent }
    }

    /// Children of `folder`, largest first. Packages (apps, Photos libraries) count as single items.
    static func children(of folder: URL, fileManager fm: FileManager = .default) -> [Entry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [])) ?? []
        let entries = parallelMap(urls) { url -> Entry? in
            guard let v = try? url.resourceValues(forKeys: keys), v.isSymbolicLink != true else { return nil }
            let size = FileSizer.measure(url).allocated
            guard size > 0 else { return nil }
            return Entry(url: url, size: size, isFolder: v.isDirectory == true && v.isPackage != true)
        }
        return entries.compactMap { $0 }.sorted { $0.size > $1.size }
    }
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk): tiles keep close to square.
enum Treemap {
    static func layout(_ sizes: [Double], in rect: CGRect) -> [CGRect] {
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return sizes.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { $0 * scale }
        var result = [CGRect](repeating: .zero, count: sizes.count)
        var remaining = rect
        var index = 0
        while index < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [index]
            var best = worst(row.map { areas[$0] }, side: side)
            var next = index + 1
            while next < areas.count {
                let candidate = worst((row + [next]).map { areas[$0] }, side: side)
                if candidate > best { break }
                row.append(next); best = candidate; next += 1
            }
            remaining = place(row, areas: areas, in: remaining, into: &result)
            index = next
        }
        return result
    }

    /// Highest aspect ratio in a row laid along a side of length `side`.
    private static func worst(_ row: [Double], side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let maxA = row.max(), let minA = row.min(), minA > 0 else { return .infinity }
        let s2 = side * side, sum2 = sum * sum
        return max(s2 * maxA / sum2, sum2 / (s2 * minA))
    }

    private static func place(_ row: [Int], areas: [Double], in rect: CGRect, into result: inout [CGRect]) -> CGRect {
        let sum = row.reduce(0) { $0 + areas[$1] }
        if rect.width >= rect.height {
            // Column on the left.
            let w = CGFloat(sum / Double(rect.height))
            var y = rect.minY
            for i in row {
                let h = CGFloat(areas[i] / Double(w))
                result[i] = CGRect(x: rect.minX, y: y, width: w, height: h)
                y += h
            }
            return CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height)
        } else {
            // Row along the top.
            let h = CGFloat(sum / Double(rect.width))
            var x = rect.minX
            for i in row {
                let w = CGFloat(areas[i] / Double(h))
                result[i] = CGRect(x: x, y: rect.minY, width: w, height: h)
                x += w
            }
            return CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
        }
    }
}
