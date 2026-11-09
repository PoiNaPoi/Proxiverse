import Foundation

enum TrafficColumn: String, CaseIterable {
    case number = "id", method, status, source, host, path, duration = "time", size
}

struct TrafficSort {
    var column: TrafficColumn = .number
    var ascending = true

    func sorted(_ rows: [TrafficFlow]) -> [TrafficFlow] {
        // URL parsing belongs outside the O(n log n) comparison loop.
        let paths = column == .path ? Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.path) }) : [:]
        return rows.sorted { left, right in
            let before: Bool?
            switch column {
            case .number: before = numeric(left.number, right.number)
            case .method: before = text(left.method, right.method)
            case .status: before = numeric(left.status, right.status)
            case .source: before = numeric(left.mapLocal.map { $0 ? 1 : 0 }, right.mapLocal.map { $0 ? 1 : 0 })
            case .host: before = text(left.host, right.host)
            case .path: before = text(paths[left.id] ?? "", paths[right.id] ?? "")
            case .duration:
                before = numeric(left.state == "pending" ? nil : left.duration,
                                 right.state == "pending" ? nil : right.duration)
            case .size: before = numeric(left.size, right.size)
            }
            if let before { return before }
            // Equal values keep a deterministic capture order in either direction.
            if left.number != right.number { return (left.number ?? Int.max) < (right.number ?? Int.max) }
            if left.started != right.started { return left.started < right.started }
            return left.id < right.id
        }
    }

    private func numeric<T: Comparable>(_ left: T?, _ right: T?) -> Bool? {
        // Pending/unknown values remain at the bottom in both directions.
        guard let left, let right else {
            return left == nil && right == nil ? nil : left != nil
        }
        guard left != right else { return nil }
        return ascending ? left < right : left > right
    }

    private func text(_ left: String, _ right: String) -> Bool? {
        let comparison = left.localizedStandardCompare(right)
        guard comparison != .orderedSame else { return nil }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}
