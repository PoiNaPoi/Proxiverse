import Foundation

/// Bounded latency samples with nearest-rank percentiles. Keeps only the newest `limit` values.
struct LatencySamples: Equatable {
    private(set) var values: [Double] = []
    private(set) var totalCount = 0
    let limit: Int

    init(limit: Int = 1_000) { self.limit = max(1, limit) }

    var count: Int { values.count }
    var last: Double? { values.last }

    mutating func add(_ value: Double) {
        totalCount += 1
        values.append(value)
        if values.count > limit { values.removeFirst(values.count - limit) }
    }

    /// Nearest-rank percentile, `fraction` in 0...1. Returns 0 when there are no samples.
    func percentile(_ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((min(max(fraction, 0), 1) * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

struct ProcessSample: Equatable {
    let pid: Int32
    let parent: Int32
    let rssKB: Double
    let cpu: Double
}

/// RAM/CPU split between the UI process and the capture engine tree. RSS may double count shared pages.
struct ResourceUsage: Equatable {
    var uiMB = 0.0
    var engineMB = 0.0
    var uiCPU = 0.0
    var engineCPU = 0.0
    var totalMB: Double { uiMB + engineMB }
    var totalCPU: Double { uiCPU + engineCPU }

    static func parse(psOutput: String) -> [ProcessSample] {
        psOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]),
                  let rss = Double(fields[2]), let cpu = Double(fields[3]) else { return nil }
            return ProcessSample(pid: pid, parent: parent, rssKB: rss, cpu: cpu)
        }
    }

    static func descendants(of roots: Set<Int32>, in processes: [ProcessSample]) -> Set<Int32> {
        var included = roots
        var count = 0
        while count != included.count {
            count = included.count
            for process in processes where included.contains(process.parent) { included.insert(process.pid) }
        }
        return included
    }

    /// `enginePID <= 0` means no engine is running. Engine descendants are never counted as UI.
    static func measure(uiPID: Int32, enginePID: Int32, processes: [ProcessSample]) -> ResourceUsage {
        let engine = enginePID > 0 ? descendants(of: [enginePID], in: processes) : []
        let ui = descendants(of: [uiPID], in: processes).subtracting(engine)
        func sum(_ ids: Set<Int32>) -> (mb: Double, cpu: Double) {
            let selected = processes.filter { ids.contains($0.pid) }
            return (selected.reduce(0) { $0 + $1.rssKB } / 1024, selected.reduce(0) { $0 + $1.cpu })
        }
        let uiTotals = sum(ui)
        let engineTotals = sum(engine)
        return ResourceUsage(uiMB: uiTotals.mb, engineMB: engineTotals.mb, uiCPU: uiTotals.cpu, engineCPU: engineTotals.cpu)
    }
}

