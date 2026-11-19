import Foundation

enum RouteV2Error: LocalizedError {
    case backend(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case let .backend(message), let .transport(message): return message
        }
    }
}

/// The planner owns one WebSocket for its visible lifetime. Routing happens over
/// the open socket first, with POST /v2/route as transport-only fallback.
@MainActor
final class RouteV2Session: ObservableObject {
    @Published private(set) var journeys: [RouteV2Journey] = []
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var connected = false

    private var socket: URLSessionWebSocketTask?
    private var connectionTask: Task<Bool, Never>?
    private var routingTask: Task<Void, Never>?
    private var requestID: String?
    private var generation = 0
    private let decoder = JSONDecoder()

    func connect() {
        guard socket == nil, connectionTask == nil else { return }
        let task = URLSession.shared.webSocketTask(
            with: URL(string: "wss://edelweiss.catenarymaps.org/v2/route/ws")!
        )
        socket = task
        task.resume()
        // Ping is used as a readiness handshake: route messages must not be
        // submitted before the connection is actually established.
        connectionTask = Task { [weak self] in
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    task.sendPing { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                guard let self, self.socket === task else { return false }
                self.connected = true
                return true
            } catch {
                guard let self else { return false }
                if self.socket === task {
                    self.connected = false
                    self.socket = nil
                    task.cancel(with: .goingAway, reason: nil)
                }
                return false
            }
        }
    }

    func close() {
        generation += 1
        routingTask?.cancel()
        routingTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        requestID = nil
        loading = false
    }

    func route(from: (Double, Double), to: (Double, Double), arriveBy: Bool = false) {
        generation += 1
        let token = generation
        routingTask?.cancel()
        // The WebSocket itself remains open across subsequent routing requests.
        journeys = []
        loading = true
        errorMessage = nil
        if socket == nil { connect() }

        routingTask = Task { [weak self] in
            guard let self else { return }
            let requestID = UUID().uuidString
            self.requestID = requestID
            let query = self.query(from: from, to: to, arriveBy: arriveBy, requestID: requestID)
            do {
                guard let task = self.socket,
                      await self.connectionTask?.value == true else {
                    throw RouteV2Error.transport("WebSocket unavailable")
                }
                try await self.performSocketRoute(task: task, query: query, requestID: requestID, generation: token)
            } catch is CancellationError {
                return
            } catch RouteV2Error.backend(let message) {
                if token == self.generation { self.errorMessage = message }
            } catch {
                // Transport failure only: preserve backend errors instead of
                // masking them with another route search.
                do {
                    let plan = try await self.performHTTPRoute(query: query)
                    if token == self.generation { self.journeys = plan.allJourneys }
                } catch {
                    if token == self.generation { self.errorMessage = error.localizedDescription }
                }
            }
            if token == self.generation { self.loading = false }
        }
    }

    private func query(
        from: (Double, Double),
        to: (Double, Double),
        arriveBy: Bool,
        requestID: String
    ) -> [String: Any] {
        let epoch = Int(Date().timeIntervalSince1970)
        return [
            "from": ["lat": from.0, "lon": from.1],
            "to": ["lat": to.0, "lon": to.1],
            (arriveBy ? "arrival_unix_seconds" : "departure_unix_seconds"): epoch,
            "preTransitModes": ["WALK"],
            "postTransitModes": ["WALK"],
            "pedestrianSpeed": 1.190476,
            "maxPreTransitTime": 900,
            "maxPostTransitTime": 900,
            "maxDirectTime": 1800,
            "detailed_legs": true,
            "timetable_view": true,
            "timeout_seconds": 8,
            "number_of_results_after": arriveBy ? 0 : 8,
            "number_of_results_before": arriveBy ? 8 : 0,
            "request_id": requestID
        ]
    }

    private func performSocketRoute(
        task: URLSessionWebSocketTask,
        query: [String: Any],
        requestID: String,
        generation: Int
    ) async throws {
        let envelope: [String: Any] = [
            "type": "route",
            "requestId": requestID,
            "query": query
        ]
        let encoded = try JSONSerialization.data(withJSONObject: envelope)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw RouteV2Error.transport("Invalid routing request encoding")
        }
        try await task.send(.string(text))
        var lastSequence = 0
        while !Task.isCancelled && generation == self.generation {
            let message = try await task.receive()
            let data: Data
            switch message {
            case let .data(body): data = body
            case let .string(body): data = Data(body.utf8)
            @unknown default: continue
            }
            let frame = try decoder.decode(RouteV2StreamFrame.self, from: data)
            guard frame.requestId == requestID else { continue }
            switch frame.type {
            case "snapshot":
                guard let sequence = frame.sequence, sequence > lastSequence,
                      let response = frame.response else { continue }
                lastSequence = sequence
                journeys = response.allJourneys
            case "complete":
                guard let response = frame.response else {
                    throw RouteV2Error.backend("Routing completed without a response")
                }
                journeys = response.allJourneys
                return
            case "error", "cancelled":
                throw RouteV2Error.backend(frame.message ?? "Routing was cancelled")
            default:
                continue
            }
        }
    }

    private func performHTTPRoute(query: [String: Any]) async throws -> RouteV2Plan {
        var request = URLRequest(url: URL(string: "https://edelweiss.catenarymaps.org/v2/route")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: query)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw RouteV2Error.backend("Edelweiss could not calculate this journey")
        }
        return try decoder.decode(RouteV2Plan.self, from: data)
    }
}
