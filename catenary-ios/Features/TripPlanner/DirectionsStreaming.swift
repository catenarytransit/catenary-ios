import Foundation

// Ported from catenary-compose TripPlannerStreaming.kt. Keep the wire contract shared with Edelweiss.
enum ConnectionDirection { case before, after }

struct DirectionsRouteEnvelope: Codable {
    let type: String
    let requestId: String
    var query: DirectionsRequest

    static func decode(_ data: Data) throws -> Self {
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        guard envelope.type == "route", !envelope.requestId.isEmpty,
              envelope.query.request_id == nil || envelope.query.request_id == envelope.requestId else {
            throw DirectionsError.invalidRequest
        }
        return envelope
    }
}

/// Copies `base` with cursor/count fields for one page. Matches the web's page sizes: 8 on the
/// first call, 4 earlier / 5 later on follow-up pages.
func directionsPageQuery(base: DirectionsRequest, direction: ConnectionDirection, cursor: String? = nil, requestId: String) -> DirectionsRequest {
    var query = base
    query.request_id = requestId
    query.page_cursor = cursor
    query.number_of_results_before = direction == .before ? (cursor == nil ? 8 : 4) : 0
    query.number_of_results_after = direction == .after ? (cursor == nil ? 8 : 5) : 0
    return query
}

/// Wire envelope shared with catenary-web and Edelweiss /v1/route/ws.
struct DirectionsStreamMessage: Decodable {
    let type: String
    let requestId: String?
    let sequence: Int64?
    let response: DirectionsPlan?
    let message: String?
}

enum DirectionsStreamError: LocalizedError {
    case backend(String)
    case timeout
    var errorDescription: String? {
        switch self {
        case .backend(let message): return message
        case .timeout: return "Routing request timed out."
        }
    }
}

enum DirectionsStreamOutcome {
    case ignored
    case page(DirectionsPlan)
    case complete(DirectionsPlan?)
}

/// Ignore unrelated/stale frames; complete always carries the authoritative replacement.
final class DirectionsStreamState {
    private let requestId: String
    private var sequence: Int64 = 0
    init(requestId: String) { self.requestId = requestId }

    func accept(_ message: DirectionsStreamMessage) throws -> DirectionsStreamOutcome {
        guard message.requestId == requestId else { return .ignored }
        switch message.type {
        case "snapshot":
            guard let next = message.sequence, next > sequence, let response = message.response else { return .ignored }
            sequence = next
            return .page(response)
        case "complete":
            guard message.response != nil else { throw URLError(.cannotParseResponse) }
            return .complete(message.response)
        case "error":
            throw DirectionsStreamError.backend(message.message ?? "Routing failed")
        case "cancelled":
            throw DirectionsStreamError.backend("Routing cancelled")
        default:
            return .ignored
        }
    }
}

/// Dedup by identity, keep transit sorted chronologically, then append direct itineraries and re-sort.
func mergeDirectionsPages(_ pages: [DirectionsPlan]) -> [DirectionsItinerary] {
    func valid(_ itinerary: DirectionsItinerary) -> Bool {
        directionsDate(itinerary.startTime) != nil && directionsDate(itinerary.endTime) != nil
    }
    func sortKey(_ itinerary: DirectionsItinerary) -> (Date, Date) {
        (directionsDate(itinerary.startTime) ?? .distantPast, directionsDate(itinerary.endTime) ?? .distantPast)
    }
    var seen = Set<String>()
    let transit = pages.flatMap { $0.itineraries ?? [] }
        .filter { valid($0) && seen.insert($0.identity).inserted }
        .sorted { sortKey($0) < sortKey($1) }
    let direct = pages.flatMap { $0.direct ?? [] }
        .filter { valid($0) && seen.insert($0.identity).inserted }
    return (transit + direct).sorted { sortKey($0) < sortKey($1) }
}

/// Warm sockets are consumed by one request each, so overlapping pages never share frames.
actor DirectionsSocketPool {
    static let shared = DirectionsSocketPool()
    private let session = URLSession(configuration: .default)
    private var idle: [(task: URLSessionWebSocketTask, created: Date)] = []
    private var active = false

    func preconnect() {
        active = true
        discardExpired()
        while idle.count < 2 { idle.append((makeSocket(), Date())) }
    }
    func take() -> URLSessionWebSocketTask {
        discardExpired()
        let socket = idle.isEmpty ? makeSocket() : idle.removeFirst().task
        if active { preconnect() }
        return socket
    }
    func close() {
        active = false
        idle.forEach { $0.task.cancel(with: .goingAway, reason: nil) }
        idle.removeAll()
    }
    private func makeSocket() -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: URL(string: "wss://edelweiss.catenarymaps.org/v1/route/ws")!)
        task.resume()
        return task
    }
    private func discardExpired() {
        idle.removeAll { entry in
            guard Date().timeIntervalSince(entry.created) > 25 else { return false }
            entry.task.cancel(with: .goingAway, reason: nil)
            return true
        }
    }
}

/// WebSocket-first pages consume a preconnected socket; HTTP is a transport-failure fallback.
enum DirectionsStreaming {
    static func load(query: DirectionsRequest, requestId: String, session: URLSession = .shared, onPage: @escaping (DirectionsPlan) -> Void) async throws {
        do {
            try await socketPage(query: query, requestId: requestId, onPage: onPage)
        } catch DirectionsStreamError.backend(let message) {
            // An explicit backend error/cancellation is authoritative; only transport failures (including timeout) fall back to HTTP.
            throw DirectionsStreamError.backend(message)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            try await httpFallback(query: query, session: session, onPage: onPage)
        }
    }

    private static func httpFallback(query: DirectionsRequest, session: URLSession, onPage: @escaping (DirectionsPlan) -> Void) async throws {
        var urlRequest = URLRequest(url: URL(string: "https://edelweiss.catenarymaps.org/v1/route")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(query)
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DirectionsError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let plan = try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(DirectionsPlan.self, from: data)
        }.value
        await MainActor.run { onPage(plan) }
    }

    private static func socketPage(query: DirectionsRequest, requestId: String, onPage: @escaping (DirectionsPlan) -> Void) async throws {
        let task = await DirectionsSocketPool.shared.take()
        defer { task.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let state = DirectionsStreamState(requestId: requestId)
            // Bound a stalled connection, including one that never sends a complete frame.
            let completed = try await withThrowingTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask {
                    try await task.send(.string(try buildEnvelope(query: query, requestId: requestId)))
                    return try await receiveLoop(task: task, state: state, onPage: onPage)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 45_000_000_000)
                    throw DirectionsStreamError.timeout
                }
                // URLSession receive can remain suspended after Task cancellation.
                // Close the socket before the group waits for its cancelled children.
                defer {
                    group.cancelAll()
                    task.cancel(with: .goingAway, reason: nil)
                }
                return try await group.next() ?? false
            }
            guard completed else { throw DirectionsStreamError.timeout }
        }, onCancel: { task.cancel(with: .goingAway, reason: nil) })
    }

    private static func receiveLoop(task: URLSessionWebSocketTask, state: DirectionsStreamState, onPage: @escaping (DirectionsPlan) -> Void) async throws -> Bool {
        while true {
            try Task.checkCancellation()
            let message = try await task.receive()
            guard case .string(let text) = message, let data = text.data(using: .utf8) else { continue }
            let decoded = try JSONDecoder().decode(DirectionsStreamMessage.self, from: data)
            switch try state.accept(decoded) {
            case .ignored:
                continue
            case .page(let page):
                await MainActor.run { onPage(page) }
            case .complete(let page):
                if let page { await MainActor.run { onPage(page) } }
                return true
            }
        }
    }

    private static func buildEnvelope(query: DirectionsRequest, requestId: String) throws -> String {
        let envelope = DirectionsRouteEnvelope(type: "route", requestId: requestId, query: query)
        let data = try JSONEncoder().encode(envelope)
        return String(decoding: data, as: UTF8.self)
    }
}
