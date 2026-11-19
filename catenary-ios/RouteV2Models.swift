import Foundation

/// OJP-inspired JSON returned by Edelweiss /v2/route and /v2/route/ws.
struct RouteV2Event: Codable, Sendable {
    let timetabledTime: String?
    let estimatedTime: String?
    let recordedAtTime: String?

    enum CodingKeys: String, CodingKey {
        case timetabledTime = "TimetabledTime"
        case estimatedTime = "EstimatedTime"
        case recordedAtTime = "RecordedAtTime"
    }

    var effectiveTime: String? { recordedAtTime ?? estimatedTime ?? timetabledTime }

    /// A schedule alone does not establish a zero-minute realtime delay.
    var delaySeconds: Int? {
        guard let original = RouteV2Time.parse(timetabledTime),
              let current = RouteV2Time.parse(recordedAtTime ?? estimatedTime) else { return nil }
        return Int(current.timeIntervalSince(original).rounded())
    }
}

enum RouteV2Time {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    static func clock(_ value: String?, timezoneID: String?) -> String {
        guard let date = parse(value) else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        return formatter.string(from: date)
    }

    /// +0' is displayed for explicitly known realtime on-time events.
    static func delay(_ seconds: Int?) -> String? {
        guard let seconds else { return nil }
        let minutes = Int((Double(abs(seconds)) / 60.0).rounded())
        return (seconds < 0 ? "-" : "+") + String(minutes) + "'"
    }
}

struct RouteV2Place: Codable, Sendable {
    let name: String?
    let lat: Double?
    let lon: Double?
    let timezone: String?
    let stopId: String?
    let plannedQuay: String?
    let estimatedQuay: String?
    let serviceDeparture: RouteV2Event?
    let serviceArrival: RouteV2Event?
    let notServicedStop: Bool?

    enum CodingKeys: String, CodingKey {
        case name, lat, lon, timezone, stopId
        case plannedQuay = "PlannedQuay"
        case estimatedQuay = "EstimatedQuay"
        case serviceDeparture = "ServiceDeparture"
        case serviceArrival = "ServiceArrival"
        case notServicedStop = "NotServicedStop"
    }
}

struct RouteV2Stop: Codable, Sendable, Identifiable {
    let name: String?
    let arrival: String?
    let departure: String?
    let scheduledArrival: String?
    let scheduledDeparture: String?
    let timezone: String?
    let stopId: String?
    let serviceArrival: RouteV2Event?
    let serviceDeparture: RouteV2Event?
    let plannedQuay: String?
    let estimatedQuay: String?
    let notServicedStop: Bool?

    enum CodingKeys: String, CodingKey {
        case name, arrival, departure, scheduledArrival, scheduledDeparture, timezone, stopId
        case serviceArrival = "ServiceArrival"
        case serviceDeparture = "ServiceDeparture"
        case plannedQuay = "PlannedQuay"
        case estimatedQuay = "EstimatedQuay"
        case notServicedStop = "NotServicedStop"
    }

    var id: String { (stopId ?? name ?? "stop") + "|" + (departure ?? arrival ?? "") }
}

struct RouteV2Leg: Codable, Sendable, Identifiable {
    let mode: String
    let startTime: String?
    let endTime: String?
    let duration: Double?
    let routeShortName: String?
    let routeLongName: String?
    let routeId: String?
    let routeType: Int?
    let chateau: String?
    let tripId: String?
    let tripStartDate: String?
    let tripStartTime: String?
    let headsign: String?
    let from: RouteV2Place?
    let to: RouteV2Place?
    let intermediateStops: [RouteV2Stop]?
    let serviceDeparture: RouteV2Event?
    let serviceArrival: RouteV2Event?
    let cancelled: Bool?

    enum CodingKeys: String, CodingKey {
        case mode, startTime, endTime, duration, routeShortName, routeLongName
        case routeId, routeType, chateau, tripId, tripStartDate, tripStartTime
        case headsign, from, to, intermediateStops, cancelled
        case serviceDeparture = "ServiceDeparture"
        case serviceArrival = "ServiceArrival"
    }

    var id: String {
        [mode, tripId ?? "", startTime ?? "", endTime ?? "", from?.stopId ?? ""].joined(separator: "|")
    }
    var street: Bool { ["WALK", "FOOT", "PEDESTRIAN", "BIKE", "BICYCLE"].contains(mode.uppercased()) }
    var label: String { routeShortName ?? routeLongName ?? routeId ?? mode.capitalized }
    var departureEvent: RouteV2Event? { serviceDeparture ?? from?.serviceDeparture }
    var arrivalEvent: RouteV2Event? { serviceArrival ?? to?.serviceArrival }
    var departureTime: String? { departureEvent?.effectiveTime ?? startTime }
    var arrivalTime: String? { arrivalEvent?.effectiveTime ?? endTime }
}

struct RouteV2Journey: Codable, Sendable, Identifiable {
    let id: String?
    let startTime: String
    let endTime: String
    let duration: Double?
    let transfers: Int?
    let legs: [RouteV2Leg]

    var stableID: String {
        id?.isEmpty == false ? id! :
            ([startTime, endTime] + legs.map(\.id)).joined(separator: "|")
    }
    var departureTimezone: String? {
        legs.first(where: { !$0.street })?.from?.timezone ?? legs.first?.from?.timezone
    }
    var arrivalTimezone: String? {
        legs.last(where: { !$0.street })?.to?.timezone ?? legs.last?.to?.timezone
    }
    var idString: String { stableID }
    var durationMinutes: Int {
        if let duration { return max(0, Int((duration / 60).rounded())) }
        guard let start = RouteV2Time.parse(startTime),
              let end = RouteV2Time.parse(endTime) else { return 0 }
        return max(0, Int((end.timeIntervalSince(start) / 60).rounded()))
    }

    /// Preserve the Compose order: trip origin, optional first boarding, delay,
    /// duration, optional last alighting, final destination.
    var boardingLeg: RouteV2Leg? { legs.first { !$0.street } }
    var alightingLeg: RouteV2Leg? { legs.last { !$0.street } }
}

struct RouteV2Plan: Codable, Sendable {
    let itineraries: [RouteV2Journey]
    let direct: [RouteV2Journey]?
    let previousPageCursor: String?
    let nextPageCursor: String?

    var allJourneys: [RouteV2Journey] {
        var ids = Set<String>()
        return (itineraries + (direct ?? []))
            .filter { ids.insert($0.stableID).inserted }
            .sorted { $0.startTime < $1.startTime }
    }
}

struct RouteV2StreamFrame: Codable, Sendable {
    let type: String
    let requestId: String?
    let sequence: Int?
    let response: RouteV2Plan?
    let message: String?
}
