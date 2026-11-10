import Foundation

struct TrafficFlow: Codable, Identifiable, Equatable {
    let id: String
    let method: String
    let url: String
    let host: String
    let status: Int?
    let state: String
    let started: Double
    let duration: Double
    let size: Int?
    let error: String?
    var number: Int? = nil
    var client: String? = nil
    var mapLocal: Bool? = nil
    var contentType: String? = nil
    var tlsPassthrough: Bool? = nil

    var path: String {
        guard let components = URLComponents(string: url) else { return url }
        return components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    var cleanPath: String {
        guard let components = URLComponents(string: url) else { return "/" }
        let p = components.percentEncodedPath
        return p.isEmpty ? "/" : p
    }
}

struct FlowMessage: Codable, Equatable {
    let headers: [[String]]
    let body: String
    let truncated: Bool
    let streamed: Bool
    let httpVersion: String
    var captureState: BodyCaptureState? = nil

    var headerText: String { headers.compactMap { $0.count == 2 ? "\($0[0]): \($0[1])" : nil }.joined(separator: "\n") }
}

enum BodyCaptureState: String, Codable {
    case complete, truncated, streamed, encoded, binary
}

enum SidebarFilter: Hashable, Sendable, Codable {
    case all
    case domain(String)
    case domainPath(host: String, pathPrefix: String)
    case client(String)

    func matches(_ flow: TrafficFlow) -> Bool {
        switch self {
        case .all:
            return true
        case .domain(let host):
            return flow.host.localizedCaseInsensitiveCompare(host) == .orderedSame
        case .domainPath(let host, let pathPrefix):
            guard flow.host.localizedCaseInsensitiveCompare(host) == .orderedSame else { return false }
            if pathPrefix == "/" { return true }
            return flow.cleanPath == pathPrefix || flow.cleanPath.hasPrefix(pathPrefix.hasSuffix("/") ? pathPrefix : pathPrefix + "/")
        case .client(let clientName):
            if clientName == "Unknown" {
                return flow.client == nil || flow.client?.isEmpty == true
            }
            return flow.client == clientName
        }
    }
}

struct FlowDetail: Codable {
    let summary: TrafficFlow
    let request: FlowMessage
    let response: FlowMessage?
}

struct FlowEvent: Codable { let sequence: Int; let flow: TrafficFlow }
struct EventBatch: Codable { let events: [FlowEvent]; let cursor: Int; let gap: Bool; let total: Int }
struct EngineHealth: Codable {
    let ready: Bool
    let total: Int
    let retained: Int
    let uptime: Double
    var apiVersion: Int? = nil
    var previewBytes: Int? = nil

    func validateVersion() throws {
        if let apiVersion, apiVersion != 1 {
            throw AppFailure("Unsupported engine API version \(apiVersion); expected 1")
        }
    }
}

struct TrafficBuffer {
    private(set) var rows: [TrafficFlow] = []
    private var positions: [String: Int] = [:]
    let limit: Int

    init(limit: Int = 10_000) { self.limit = limit }

    mutating func apply(_ events: [FlowEvent]) {
        for event in events {
            let flow = event.flow
            if let index = positions[flow.id] {
                rows[index] = flow
            } else {
                positions[flow.id] = rows.count
                rows.append(flow)
            }
        }
        if rows.count > limit {
            rows.removeFirst(rows.count - limit)
            positions = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        }
    }

    func filtered(search: String, host: String?) -> [TrafficFlow] {
        let sidebar = host.map(SidebarFilter.domain) ?? .all
        return filtered(search: search, sidebar: sidebar)
    }

    func filtered(search: String, sidebar: SidebarFilter) -> [TrafficFlow] {
        filtered(query: TrafficQuery(freeText: search), sidebar: sidebar)
    }

    func filtered(query: TrafficQuery, sidebar: SidebarFilter) -> [TrafficFlow] {
        rows.filter { sidebar.matches($0) && query.matches($0) }
    }
}

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
