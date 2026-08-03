import Foundation

struct VehicleHistorySelection: Hashable {
    let chateauID: String
    let vehicleID: String
    let routeID: String?
}

struct VehicleHistoryRoute: Decodable, Sendable {
    let routeID: String
    let shortName: String?
    let longName: String?
    let routeType: Int?
    let color: String?
    let textColor: String?

    enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case shortName = "short_name"
        case longName = "long_name"
        case routeType = "route_type"
        case color
        case textColor = "text_color"
    }

    var displayName: String {
        let short = shortName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let short, !short.isEmpty { return short }

        let long = longName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let long, !long.isEmpty { return long }

        return routeID
    }
}

struct VehicleHistoryRow: Decodable, Identifiable, Sendable {
    let operationDate: String
    let unixStartTime: Int64?
    let tripID: String
    let routeID: String
    let tripShortName: String?
    let directionHeadsign: String?
    let blockID: String?

    enum CodingKeys: String, CodingKey {
        case operationDate = "operation_date"
        case unixStartTime = "unix_start_time"
        case tripID = "trip_id"
        case routeID = "route_id"
        case tripShortName = "trip_short_name"
        case directionHeadsign = "direction_headsign"
        case blockID = "block_id"
    }

    var id: String {
        "\(operationDate)|\(tripID)|\(routeID)|\(unixStartTime.map { String($0) } ?? "")|\(blockID ?? "")"
    }

    var displayHeadsign: String {
        for candidate in [directionHeadsign, tripShortName, tripID] {
            if let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !candidate.isEmpty {
                return candidate
            }
        }
        return tripID
    }
}

struct VehicleHistoryLookupResponse: Decodable, Sendable {
    let tripHistory: [VehicleHistoryRow]
    let routes: [String: VehicleHistoryRoute]
    let agencyTimezone: String
    let agencyName: String

    enum CodingKeys: String, CodingKey {
        case tripHistory = "trip_history"
        case routes
        case agencyTimezone = "agency_timezone"
        case agencyName = "agency_name"
    }

    static let empty = VehicleHistoryLookupResponse(
        tripHistory: [],
        routes: [:],
        agencyTimezone: "UTC",
        agencyName: ""
    )
}

struct VehicleHistoryLookupErrorResponse: Decodable, Sendable {
    let error: VehicleHistoryLookupErrorBody
}

struct VehicleHistoryLookupErrorBody: Decodable, Sendable {
    let code: String
    let message: String
}
