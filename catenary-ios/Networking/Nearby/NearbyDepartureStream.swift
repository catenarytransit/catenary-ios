import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct NearbyAPIResponse: Decodable, Sendable {
    var longDistance: [NearbyStationGroup] = []
    var local: [NearbyRouteGroup] = []
    var routes: [String: [String: NearbyRouteInfo]] = [:]
    var stops: [String: [String: NearbyStopInfo]] = [:]
    var debug: NearbyDebugInfo? = nil
}

struct NearbyDebugInfo: Decodable, Sendable {
    let totalTimeMs: Int64?
}

struct NearbyStationGroup: Decodable, Identifiable, Sendable {
    let stationName: String
    let osmStationId: Int64?
    var distanceM: Double
    var departures: [NearbyStationDeparture]
    let lat: Double
    let lon: Double
    let timezone: String

    var id: String { "station|\(osmStationId.map(String.init) ?? stationName)|\(lat)|\(lon)" }
}

struct NearbyStationDeparture: Decodable, Identifiable, Sendable {
    let scheduledDeparture: Int64?
    let realtimeDeparture: Int64?
    let scheduledArrival: Int64?
    let realtimeArrival: Int64?
    let serviceDate: String?
    let headsign: String
    let platform: String?
    let tripId: String?
    let tripShortName: String?
    let routeId: String
    let stopId: String
    let cancelled: Bool?
    let delayed: Bool?
    let chateauId: String
    let lastStop: Bool?
    let finalStationName: String?

    var id: String {
        "station-departure|\(chateauId)|\(tripId ?? "")|\(routeId)|\(stopId)|\(scheduledDeparture ?? scheduledArrival ?? 0)"
    }

    var effectiveDeparture: Int64? {
        if let realtimeDeparture { return realtimeDeparture }
        // A realtime arrival only stands in for the departure when there's no scheduled departure
        // to compare against, or it's actually after it; otherwise it's a stale/earlier event.
        if let realtimeArrival, scheduledDeparture == nil || realtimeArrival > scheduledDeparture! {
            return realtimeArrival
        }
        return scheduledDeparture ?? scheduledArrival
    }
}

struct NearbyRouteGroup: Decodable, Identifiable, Sendable {
    let chateauId: String
    let routeId: String
    let color: String?
    let textColor: String?
    let shortName: String?
    let longName: String?
    let routeType: Int?
    let agencyName: String?
    var headsigns: [String: [NearbyLocalDeparture]]
    var closestDistance: Double

    var id: String { "route|\(chateauId)|\(routeId)" }
}

struct NearbyLocalDeparture: Decodable, Identifiable, Sendable {
    let tripId: String?
    let departureSchedule: Int64?
    let departureRealtime: Int64?
    let arrivalSchedule: Int64?
    let arrivalRealtime: Int64?
    let stopId: String
    let stopName: String?
    let cancelled: Bool?
    let platform: String?
    let lastStop: Bool?
    let serviceDate: String?

    var id: String {
        "local-departure|\(tripId ?? "")|\(stopId)|\(departureSchedule ?? arrivalSchedule ?? 0)"
    }

    var effectiveDeparture: Int64? {
        if let departureRealtime { return departureRealtime }
        // A realtime arrival only stands in for the departure when it's actually after the
        // scheduled departure; otherwise it's a stale/earlier event that would show the wrong time.
        if let arrivalRealtime, departureSchedule == nil || arrivalRealtime > departureSchedule! {
            return arrivalRealtime
        }
        return departureSchedule ?? arrivalSchedule
    }
}

struct NearbyRouteInfo: Decodable, Sendable {
    let shortName: String?
    let longName: String?
    let agencyName: String?
    let color: String?
    let textColor: String?
    let routeType: Int?
}

struct NearbyStopInfo: Decodable, Sendable {
    let gtfsId: String?
    let name: String
    let lat: Double
    let lon: Double
    let osmStationId: Int64?
    let timezone: String?
}

struct NearbyDepartureQuery: Equatable, Sendable {
    let lat: Double
    let lon: Double
    let departureTime: Int64?
}

struct NearbyDepartureRequest: Encodable, Sendable {
    let type = "nearby_departures"
    let requestId: String
    let lat: Double
    let lon: Double
    let departureTime: Int64?
    let progressive: Bool
    let limitPerStation = 10
    let limitPerHeadsign = 20

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }
}

struct NearbyDepartureMessage: Decodable, Sendable {
    let type: String
    let requestId: String?
    let phase: String?
    let complete: Bool?
    let data: NearbyAPIResponse?
    let message: String?
}

enum NearbyDepartureStreamError: LocalizedError {
    case invalidPhase
    case server(String?)

    var errorDescription: String? {
        switch self {
        case .invalidPhase: return URLError(.badServerResponse).localizedDescription
        case .server(let message): return message ?? URLError(.badServerResponse).localizedDescription
        }
    }
}

private struct NearbyRouteKey: Hashable {
    let chateau: String
    let route: String
}

private enum NearbyStationKey: Hashable {
    case osm(Int64)
    case coordinate(String, Double, Double)

    init(_ station: NearbyStationGroup) {
        if let id = station.osmStationId {
            self = .osm(id)
        } else {
            self = .coordinate(station.stationName, station.lat, station.lon)
        }
    }
}

private struct NearbyDepartureKey: Hashable {
    let chateau: String?
    let route: String?
    let trip: String?
    let date: String?
    let stop: String
    let departure: Int64?
    let arrival: Int64?

    init(_ item: NearbyLocalDeparture) {
        chateau = nil
        route = nil
        trip = item.tripId
        date = item.serviceDate
        stop = item.stopId
        departure = item.departureSchedule
        arrival = item.arrivalSchedule
    }

    init(_ item: NearbyStationDeparture) {
        chateau = item.chateauId
        route = item.routeId
        trip = item.tripId
        date = item.serviceDate
        stop = item.stopId
        departure = item.scheduledDeparture
        arrival = item.scheduledArrival
    }
}

// Preserve order on ties; the newer frame wins for the same occurrence.
private func mergeByKey<Value, Key: Hashable>(
    _ first: [Value], _ second: [Value], key: (Value) -> Key,
    combine: (Value, Value) -> Value
) -> [Value] {
    var values: [Value] = []
    var indices: [Key: Int] = [:]
    for value in first + second {
        let identity = key(value)
        if let index = indices[identity] {
            values[index] = combine(values[index], value)
        } else {
            indices[identity] = values.count
            values.append(value)
        }
    }
    return values
}

private func mergeTables<Value>(
    _ first: [String: [String: Value]], _ second: [String: [String: Value]]
) -> [String: [String: Value]] {
    first.merging(second) { old, new in old.merging(new) { _, latest in latest } }
}

func mergeNearbyDepartures(_ first: NearbyAPIResponse, _ second: NearbyAPIResponse) -> NearbyAPIResponse {
    let routes = mergeByKey(first.local, second.local, key: {
        NearbyRouteKey(chateau: $0.chateauId, route: $0.routeId)
    }) { old, new in
        var merged = new
        merged.closestDistance = min(old.closestDistance, new.closestDistance)
        merged.headsigns = old.headsigns.merging(new.headsigns) { previous, latest in
            mergeByKey(previous, latest, key: { NearbyDepartureKey($0) }) { _, newer in newer }
                .sorted { ($0.effectiveDeparture ?? Int64.max) < ($1.effectiveDeparture ?? Int64.max) }
        }
        return merged
    }
    let stations = mergeByKey(first.longDistance, second.longDistance, key: NearbyStationKey.init) { old, new in
        var merged = new
        merged.distanceM = min(old.distanceM, new.distanceM)
        merged.departures = mergeByKey(old.departures, new.departures, key: { NearbyDepartureKey($0) }) { _, newer in newer }
            .sorted { ($0.effectiveDeparture ?? Int64.max) < ($1.effectiveDeparture ?? Int64.max) }
        return merged
    }
    return NearbyAPIResponse(
        longDistance: stations.sorted { $0.distanceM < $1.distanceM },
        local: routes.sorted { $0.closestDistance < $1.closestDistance },
        routes: mergeTables(first.routes, second.routes),
        stops: mergeTables(first.stops, second.stops),
        debug: second.debug ?? first.debug
    )
}

enum NearbyDepartureFrameResult {
    case ignored
    case priority(NearbyAPIResponse)
    case complete(NearbyAPIResponse)
}

/// A new accumulator for every refresh; a full response replaces previous data.
struct NearbyDepartureStreamState {
    let requestId: String
    let publishPriority: Bool
    private var priority: NearbyAPIResponse?
    private var finished = false

    init(requestId: String, publishPriority: Bool = true) {
        self.requestId = requestId
        self.publishPriority = publishPriority
    }

    mutating func accept(_ frame: NearbyDepartureMessage) throws -> NearbyDepartureFrameResult {
        guard !finished else { return .ignored }
        if frame.type == "error", frame.requestId == nil {
            throw NearbyDepartureStreamError.server(frame.message)
        }
        guard frame.requestId == requestId else { return .ignored }
        if frame.type == "nearby_departures_error" || frame.type == "error" {
            throw NearbyDepartureStreamError.server(frame.message)
        }
        guard frame.type == "nearby_departures" else { return .ignored }
        guard let data = frame.data else { throw NearbyDepartureStreamError.invalidPhase }

        switch frame.phase {
        case "priority":
            guard frame.complete != true else { throw NearbyDepartureStreamError.invalidPhase }
            guard priority == nil else { return .ignored }
            priority = data
            return publishPriority ? .priority(data) : .ignored
        case "remaining":
            guard frame.complete == true, let priority else { throw NearbyDepartureStreamError.invalidPhase }
            finished = true
            return .complete(mergeNearbyDepartures(priority, data))
        case "full":
            guard frame.complete == true else { throw NearbyDepartureStreamError.invalidPhase }
            finished = true
            return .complete(data)
        default:
            throw NearbyDepartureStreamError.invalidPhase
        }
    }
}

/// Decode and merge on a dedicated actor, outside SwiftUI's main actor.
actor NearbyDepartureAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func stream(
        query: NearbyDepartureQuery, progressive: Bool,
        onSnapshot: @escaping @MainActor @Sendable (NearbyAPIResponse) throws -> Void
    ) async throws {
        let request = NearbyDepartureRequest(
            requestId: UUID().uuidString, lat: query.lat, lon: query.lon,
            departureTime: query.departureTime, progressive: progressive
        )
        let socket = session.webSocketTask(with: URL(string: "wss://ramonda.catenarymaps.org/ws/")!)
        // Nearby results can exceed URLSession's default one-megabyte limit.
        socket.maximumMessageSize = 32 * 1024 * 1024
        socket.resume()

        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.receive(socket: socket, request: request, onSnapshot: onSnapshot)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 45_000_000_000)
                    throw URLError(.timedOut)
                }
                group.addTask {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            socket.sendPing { error in
                                if let error {
                                    continuation.resume(throwing: error)
                                } else {
                                    continuation.resume()
                                }
                            }
                        }
                    }
                    try Task.checkCancellation()
                }
                defer {
                    group.cancelAll()
                    socket.cancel(with: .goingAway, reason: nil)
                }
                try await group.next()
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private func receive(
        socket: URLSessionWebSocketTask, request: NearbyDepartureRequest,
        onSnapshot: @MainActor @Sendable (NearbyAPIResponse) throws -> Void
    ) async throws {
        try Task.checkCancellation()
        try await socket.send(.string(String(decoding: try request.encoded(), as: UTF8.self)))
        var state = NearbyDepartureStreamState(requestId: request.requestId, publishPriority: request.progressive)
        while true {
            try Task.checkCancellation()
            let message = try await socket.receive()
            try Task.checkCancellation()
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: throw URLError(.badServerResponse)
            }
            let frame = try decoder.decode(NearbyDepartureMessage.self, from: data)
            switch try state.accept(frame) {
            case .ignored: continue
            case .priority(let snapshot):
                try await onSnapshot(snapshot)
            case .complete(let snapshot):
                try await onSnapshot(snapshot)
                return
            }
        }
    }

    func fetchHTTP(query: NearbyDepartureQuery) async throws -> NearbyAPIResponse {
        var components = URLComponents(string: "https://birch.catenarymaps.org/nearbydeparturesfromcoordsv3")!
        var items = [
            URLQueryItem(name: "lat", value: String(query.lat)),
            URLQueryItem(name: "lon", value: String(query.lon)),
            URLQueryItem(name: "limit_per_station", value: "10"),
            URLQueryItem(name: "limit_per_headsign", value: "20")
        ]
        if let departureTime = query.departureTime {
            items.append(URLQueryItem(name: "departure_time", value: String(departureTime)))
        }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()
        return try decoder.decode(NearbyAPIResponse.self, from: data)
    }
}
