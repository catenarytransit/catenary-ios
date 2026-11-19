import Foundation

// Ported from catenary-compose TripPlannerModels.kt. Keep Edelweiss field names and units.
/// OJP-style v2 event: an estimated or recorded event is the sole evidence
/// of realtime, so an explicit on-time update is displayed as +0'.
struct DirectionsEventTime: Codable, Equatable, Sendable {
    var timetabledTime: String? = nil
    var estimatedTime: String? = nil
    var recordedAtTime: String? = nil

    enum CodingKeys: String, CodingKey {
        case timetabledTime = "TimetabledTime"
        case estimatedTime = "EstimatedTime"
        case recordedAtTime = "RecordedAtTime"
    }

    var effectiveTime: String? { recordedAtTime ?? estimatedTime ?? timetabledTime }
    var delaySeconds: Int64? {
        guard let baseline = directionsDate(timetabledTime),
              let realtime = directionsDate(recordedAtTime ?? estimatedTime) else { return nil }
        return Int64(realtime.timeIntervalSince(baseline).rounded())
    }
}

func directionsDelayLabel(_ delaySeconds: Int64?) -> String? {
    guard let delaySeconds else { return nil }
    let minutes = Int((Double(abs(delaySeconds)) / 60).rounded())
    return (delaySeconds < 0 ? "-" : "+") + String(minutes) + "'"
}

struct DirectionsLocation: Codable, Equatable, Sendable {
    var name: String
    var lat: Double
    var lon: Double
    var isCurrentLocation = false
    var isMapLocation = false
    var isValid: Bool { lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon) }
}

struct DirectionsPoint: Codable, Equatable, Sendable {
    var stopId: String? = nil
    var name: String?
    var lat: Double?
    var lon: Double?
    var platform: String?
    var timezone: String? = nil
    var platformCode: String?
    var plannedQuay: String? = nil
    var estimatedQuay: String? = nil
    var serviceDeparture: DirectionsEventTime? = nil
    var serviceArrival: DirectionsEventTime? = nil
    var notServicedStop: Bool? = nil
    var noBoardingAtStop: Bool? = nil
    var noAlightingAtStop: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case stopId, name, lat, lon, platform, timezone, platformCode
        case plannedQuay = "PlannedQuay"
        case estimatedQuay = "EstimatedQuay"
        case serviceDeparture = "ServiceDeparture"
        case serviceArrival = "ServiceArrival"
        case notServicedStop = "NotServicedStop"
        case noBoardingAtStop = "NoBoardingAtStop"
        case noAlightingAtStop = "NoAlightingAtStop"
    }

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
    var timezone: String? = nil
    var stopId: String? = nil
    var serviceDeparture: DirectionsEventTime? = nil
    var serviceArrival: DirectionsEventTime? = nil
    var plannedQuay: String? = nil
    var estimatedQuay: String? = nil
    var notServicedStop: Bool? = nil
    var noBoardingAtStop: Bool? = nil
    var noAlightingAtStop: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case name, arrival, departure, scheduledArrival, scheduledDeparture, timezone, stopId
        case serviceDeparture = "ServiceDeparture"
        case serviceArrival = "ServiceArrival"
        case plannedQuay = "PlannedQuay"
        case estimatedQuay = "EstimatedQuay"
        case notServicedStop = "NotServicedStop"
        case noBoardingAtStop = "NoBoardingAtStop"
        case noAlightingAtStop = "NoAlightingAtStop"
    }
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
    var tripId: String? = nil
    var tripStartDate: String? = nil
    var tripStartTime: String? = nil
    var fromStopSequence: Int? = nil
    var toStopSequence: Int? = nil
    var serviceDeparture: DirectionsEventTime? = nil
    var serviceArrival: DirectionsEventTime? = nil
    var cancelled: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case mode, duration, startTime, endTime, routeColor, routeTextColor
        case routeShortName, routeLongName, routeId, routeType, chateau
        case tripShortName, from, to, fromPlatform, toPlatform
        case intermediateStops, legGeometry, headsign, tripId, tripStartDate, tripStartTime
        case fromStopSequence, toStopSequence, cancelled
        case serviceDeparture = "ServiceDeparture"
        case serviceArrival = "ServiceArrival"
    }

    var departureEvent: DirectionsEventTime? { serviceDeparture ?? from?.serviceDeparture }
    var arrivalEvent: DirectionsEventTime? { serviceArrival ?? to?.serviceArrival }
    var departureDelaySeconds: Int64? { departureEvent?.delaySeconds }
    var arrivalDelaySeconds: Int64? { arrivalEvent?.delaySeconds }
    var departureCurrentTime: String? { departureEvent?.effectiveTime ?? startTime }
    var arrivalCurrentTime: String? { arrivalEvent?.effectiveTime ?? endTime }
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
    var canBeSaved: Bool { (directionsDate(endTime) ?? .distantPast) > Date() }
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
