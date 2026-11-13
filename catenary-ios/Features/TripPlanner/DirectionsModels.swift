import Foundation

// Ported from catenary-compose TripPlannerModels.kt. Keep Edelweiss field names and units.
struct DirectionsLocation: Codable, Equatable, Sendable {
    var name: String
    var lat: Double
    var lon: Double
    var isCurrentLocation = false
    var isMapLocation = false
    var isValid: Bool { lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon) }
}

struct DirectionsPoint: Codable, Equatable, Sendable {
    var name: String?
    var lat: Double?
    var lon: Double?
    var platform: String?
    var platformCode: String?
    var location: DirectionsLocation? {
        guard let lat, let lon else { return nil }
        let result = DirectionsLocation(name: name ?? "", lat: lat, lon: lon)
        return result.isValid ? result : nil
    }
}
struct DirectionsStop: Codable, Equatable, Sendable {
    var name: String?
    var arrival: String?
    var departure: String?
    var scheduledArrival: String?
    var scheduledDeparture: String?
}
struct DirectionsGeometry: Codable, Equatable, Sendable {
    var points: String?
    var precision: Int?
}
struct DirectionsLeg: Codable, Equatable, Sendable {
    var mode: String
    var duration: Double?
    var startTime: String?
    var endTime: String?
    var routeColor: String?
    var routeTextColor: String?
    var routeShortName: String?
    var routeLongName: String?
    var routeId: String?
    var routeType: Int?
    var chateau: String?
    var tripShortName: String?
    var from: DirectionsPoint?
    var to: DirectionsPoint?
    var fromPlatform: String?
    var toPlatform: String?
    var intermediateStops: [DirectionsStop]?
    var legGeometry: DirectionsGeometry?
    var headsign: String?
    var street: Bool { ["WALK", "BIKE", "BICYCLE"].contains(mode.uppercased()) }
    var label: String { routeShortName ?? routeLongName ?? routeId ?? mode.capitalized }
    var seconds: Double { directionsDuration(duration, startTime, endTime) }
}
struct DirectionsItinerary: Codable, Equatable, Sendable {
    var startTime: String
    var endTime: String
    var duration: Double?
    var transfers: Int?
    var legs: [DirectionsLeg]
    var id: String?
    var seconds: Double { directionsDuration(duration, startTime, endTime) }
    /// Stable key for dedup/selection across pages; falls back to a structural fingerprint when the backend omits `id`.
    var identity: String {
        if let id, !id.isEmpty { return id }
        let legsPart = legs.map {
            "\($0.mode)|\($0.startTime ?? "")|\($0.endTime ?? "")|\($0.routeId ?? "")|\($0.from?.name ?? "")|\($0.to?.name ?? "")"
        }.joined(separator: ";")
        return "\(startTime)|\(endTime)|\(legsPart)"
    }
}
struct DirectionsPlan: Codable, Sendable {
    var itineraries: [DirectionsItinerary]?
    var direct: [DirectionsItinerary]?
    var previousPageCursor: String?
    var nextPageCursor: String?
    var journeys: [DirectionsItinerary] {
        ((itineraries ?? []) + (direct ?? [])).filter {
            directionsDate($0.startTime) != nil && directionsDate($0.endTime) != nil
        }
    }
}
struct DirectionsOptions: Codable, Equatable, Sendable {
    var cycling = false
    var walkingPace = 840.0 // seconds per kilometre
    var cyclingKmh = 16.0
    var accessSeconds = 900.0
    var egressSeconds = 900.0
    var directSeconds = 1800.0
}
struct DirectionsRequest: Codable {
    struct Point: Codable { let lat: Double; let lon: Double }
    let from: Point
    let to: Point
    let departure_unix_seconds: Int64?
    let arrival_unix_seconds: Int64?
    let preTransitModes: [String]
    let postTransitModes: [String]
    let pedestrianSpeed: Double
    let cyclingSpeed: Double
    let maxPreTransitTime: Int
    let maxPostTransitTime: Int
    let maxDirectTime: Int
    let detailed_legs = true
    let timetable_view = true
    let timeout_seconds = 8
    var page_cursor: String?
    var number_of_results_before = 0
    var number_of_results_after = 0
    var request_id: String?

    init(from: DirectionsLocation, to: DirectionsLocation, date: Date, arriveBy: Bool, options: DirectionsOptions) throws {
        guard from.isValid, to.isValid,
              options.walkingPace.isFinite, options.walkingPace > 0,
              options.cyclingKmh.isFinite, options.cyclingKmh > 0,
              [options.accessSeconds, options.egressSeconds, options.directSeconds].allSatisfy({ $0.isFinite }) else {
            throw DirectionsError.invalidRequest
        }
        // Match Edelweiss's 1...3600-second contract for every travel-time budget.
        func budget(_ seconds: Double) -> Int { Int(seconds).clamped(to: 1...3600) }
        self.from = Point(lat: from.lat, lon: from.lon)
        self.to = Point(lat: to.lat, lon: to.lon)
        let epoch = Int64(date.timeIntervalSince1970)
        departure_unix_seconds = arriveBy ? nil : epoch
        arrival_unix_seconds = arriveBy ? epoch : nil
        preTransitModes = [options.cycling ? "BIKE" : "WALK"]
        postTransitModes = preTransitModes
        pedestrianSpeed = 1000 / options.walkingPace
        cyclingSpeed = options.cyclingKmh / 3.6
        maxPreTransitTime = budget(options.accessSeconds)
        maxPostTransitTime = budget(options.egressSeconds)
        maxDirectTime = budget(options.directSeconds)
    }
}
private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
enum DirectionsError: LocalizedError {
    case invalidRequest
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Choose valid locations and travel options."
        case .http(let code): return "Unable to plan journey (HTTP \(code)). Please try again."
        }
    }
}
func directionsDate(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
}
private func directionsDuration(_ duration: Double?, _ start: String?, _ end: String?) -> Double {
    if let duration, duration.isFinite { return max(0, duration) }
    guard let a = directionsDate(start), let b = directionsDate(end) else { return 0 }
    return max(0, b.timeIntervalSince(a))
}
