import Foundation

struct SingleTripSelection: Hashable {
    let chateauID: String
    let tripID: String?
    let routeID: String?
    let startTime: String?
    let startDate: String?
    let vehicleID: String?
    let routeType: Int?
}

struct SingleTripRealtimeTime: Codable, Equatable {
    let time: Int64?
}

struct SingleTripVehicle: Codable, Equatable {
    let id: String?
    let label: String?
}

struct SingleTripStopTime: Codable, Equatable, Identifiable {
    let name: String?
    let stopID: String
    let longitude: Double
    let latitude: Double
    let timezone: String?
    let scheduledArrivalTimeUnixSeconds: Int64?
    let scheduledDepartureTimeUnixSeconds: Int64?
    let interpolatedStoptimeUnixSeconds: Int64?
    let realtimeArrival: SingleTripRealtimeTime?
    let realtimeDeparture: SingleTripRealtimeTime?
    let realtimePlatformString: String?
    let scheduleRelationship: Int?
    let code: String?
    let timepoint: Bool?
    let replacedStop: Bool?
    let gtfsStopSequence: Int?
    let showBothDepartureAndArrival: Bool?

    var id: String {
        if let gtfsStopSequence {
            return "\(gtfsStopSequence)|\(stopID)"
        }
        return stopID
    }

    enum CodingKeys: String, CodingKey {
        case name
        case stopID = "stop_id"
        case longitude
        case latitude
        case timezone
        case scheduledArrivalTimeUnixSeconds = "scheduled_arrival_time_unix_seconds"
        case scheduledDepartureTimeUnixSeconds = "scheduled_departure_time_unix_seconds"
        case interpolatedStoptimeUnixSeconds = "interpolated_stoptime_unix_seconds"
        case realtimeArrival = "rt_arrival"
        case realtimeDeparture = "rt_departure"
        case realtimePlatformString = "rt_platform_string"
        case scheduleRelationship = "schedule_relationship"
        case code
        case timepoint
        case replacedStop = "replaced_stop"
        case gtfsStopSequence = "gtfs_stop_sequence"
        case showBothDepartureAndArrival = "show_both_departure_and_arrival"
    }
}

struct SingleTripAlertTranslation: Codable, Equatable, Sendable {
    let text: String
    let language: String?
}

struct SingleTripAlertText: Codable, Equatable, Sendable {
    let translation: [SingleTripAlertTranslation]

    func preferredTranslation(locale: Locale = .current) -> SingleTripAlertTranslation? {
        guard !translation.isEmpty else { return nil }

        let localeTag = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let languageCode = locale.language.languageCode?.identifier.lowercased()

        func normalized(_ value: String?) -> String {
            value?
                .replacingOccurrences(of: "-html", with: "")
                .replacingOccurrences(of: "_", with: "-")
                .lowercased() ?? ""
        }

        return translation.first(where: { normalized($0.language) == localeTag })
            ?? translation.first(where: {
                guard let languageCode else { return false }
                return normalized($0.language).split(separator: "-").first.map(String.init) == languageCode
            })
            ?? translation.first(where: { normalized($0.language).isEmpty })
            ?? translation.first
    }
}

struct SingleTripAlertActivePeriod: Codable, Equatable, Sendable {
    let start: Int64?
    let end: Int64?
}

struct SingleTripAlertTripDescriptor: Codable, Equatable, Sendable {
    let tripID: String?
    let routeID: String?
    let directionID: Int?
    let startTime: String?
    let startDate: String?

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case routeID = "route_id"
        case directionID = "direction_id"
        case startTime = "start_time"
        case startDate = "start_date"
    }
}

struct SingleTripAlertEntity: Codable, Equatable, Sendable {
    let agencyID: String?
    let routeID: String?
    let routeType: Int?
    let stopID: String?
    let trip: SingleTripAlertTripDescriptor?

    enum CodingKeys: String, CodingKey {
        case agencyID = "agency_id"
        case routeID = "route_id"
        case routeType = "route_type"
        case stopID = "stop_id"
        case trip
    }
}

struct SingleTripAlert: Codable, Equatable, Sendable {
    let cause: Int?
    let effect: Int?
    let url: SingleTripAlertText?
    let headerText: SingleTripAlertText?
    let descriptionText: SingleTripAlertText?
    let activePeriod: [SingleTripAlertActivePeriod]
    let informedEntity: [SingleTripAlertEntity]?

    enum CodingKeys: String, CodingKey {
        case cause
        case effect
        case url
        case headerText = "header_text"
        case descriptionText = "description_text"
        case activePeriod = "active_period"
        case informedEntity = "informed_entity"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cause = try container.decodeIfPresent(Int.self, forKey: .cause)
        effect = try container.decodeIfPresent(Int.self, forKey: .effect)
        url = try container.decodeIfPresent(SingleTripAlertText.self, forKey: .url)
        headerText = try container.decodeIfPresent(SingleTripAlertText.self, forKey: .headerText)
        descriptionText = try container.decodeIfPresent(SingleTripAlertText.self, forKey: .descriptionText)
        activePeriod = try container.decodeIfPresent([SingleTripAlertActivePeriod].self, forKey: .activePeriod) ?? []
        informedEntity = try container.decodeIfPresent([SingleTripAlertEntity].self, forKey: .informedEntity)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cause, forKey: .cause)
        try container.encodeIfPresent(effect, forKey: .effect)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(headerText, forKey: .headerText)
        try container.encodeIfPresent(descriptionText, forKey: .descriptionText)
        try container.encode(activePeriod, forKey: .activePeriod)
        try container.encodeIfPresent(informedEntity, forKey: .informedEntity)
    }

    func isActive(at epochSeconds: Int64) -> Bool {
        activePeriod.isEmpty || activePeriod.contains { period in
            (period.start == nil || period.start! <= epochSeconds)
                && (period.end == nil || epochSeconds < period.end!)
        }
    }

    func isTripSpecific() -> Bool {
        guard let informedEntity, !informedEntity.isEmpty else { return false }
        return informedEntity.allSatisfy { entity in
            guard let tripID = entity.trip?.tripID else { return false }
            return !tripID.isEmpty
        }
    }
}

struct SingleTripDataResponse: Codable, Equatable {
    let color: String?
    let textColor: String?
    let routeID: String?
    let vehicle: SingleTripVehicle?
    let tripHeadsign: String?
    let tripShortName: String?
    let routeShortName: String?
    let routeLongName: String?
    let routeType: Int?
    let blockID: String?
    let serviceDate: String?
    let tripID: String?
    let shapePolyline: String?
    let oldShapePolyline: String?
    let realtimeShape: Bool?
    let timezone: String?
    let stopTimes: [SingleTripStopTime]
    let alerts: [String: SingleTripAlert]
    let isCancelled: Bool?
    let deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case color
        case textColor = "text_color"
        case routeID = "route_id"
        case vehicle
        case tripHeadsign = "trip_headsign"
        case tripShortName = "trip_short_name"
        case routeShortName = "route_short_name"
        case routeLongName = "route_long_name"
        case routeType = "route_type"
        case blockID = "block_id"
        case serviceDate = "service_date"
        case tripID = "trip_id"
        case shapePolyline = "shape_polyline"
        case oldShapePolyline = "old_shape_polyline"
        case realtimeShape = "rt_shape"
        case timezone = "tz"
        case stopTimes = "stoptimes"
        case alerts = "alert_id_to_alert"
        case isCancelled = "is_cancelled"
        case deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor)
        routeID = try container.decodeIfPresent(String.self, forKey: .routeID)
        vehicle = try container.decodeIfPresent(SingleTripVehicle.self, forKey: .vehicle)
        tripHeadsign = try container.decodeIfPresent(String.self, forKey: .tripHeadsign)
        tripShortName = try container.decodeIfPresent(String.self, forKey: .tripShortName)
        routeShortName = try container.decodeIfPresent(String.self, forKey: .routeShortName)
        routeLongName = try container.decodeIfPresent(String.self, forKey: .routeLongName)
        routeType = try container.decodeIfPresent(Int.self, forKey: .routeType)
        blockID = try container.decodeIfPresent(String.self, forKey: .blockID)
        serviceDate = try container.decodeIfPresent(String.self, forKey: .serviceDate)
        tripID = try container.decodeIfPresent(String.self, forKey: .tripID)
        shapePolyline = try container.decodeIfPresent(String.self, forKey: .shapePolyline)
        oldShapePolyline = try container.decodeIfPresent(String.self, forKey: .oldShapePolyline)
        realtimeShape = try container.decodeIfPresent(Bool.self, forKey: .realtimeShape)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        stopTimes = try container.decodeIfPresent([SingleTripStopTime].self, forKey: .stopTimes) ?? []
        alerts = try container.decodeIfPresent([String: SingleTripAlert].self, forKey: .alerts) ?? [:]
        isCancelled = try container.decodeIfPresent(Bool.self, forKey: .isCancelled)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(textColor, forKey: .textColor)
        try container.encodeIfPresent(routeID, forKey: .routeID)
        try container.encodeIfPresent(vehicle, forKey: .vehicle)
        try container.encodeIfPresent(tripHeadsign, forKey: .tripHeadsign)
        try container.encodeIfPresent(tripShortName, forKey: .tripShortName)
        try container.encodeIfPresent(routeShortName, forKey: .routeShortName)
        try container.encodeIfPresent(routeLongName, forKey: .routeLongName)
        try container.encodeIfPresent(routeType, forKey: .routeType)
        try container.encodeIfPresent(blockID, forKey: .blockID)
        try container.encodeIfPresent(serviceDate, forKey: .serviceDate)
        try container.encodeIfPresent(tripID, forKey: .tripID)
        try container.encodeIfPresent(shapePolyline, forKey: .shapePolyline)
        try container.encodeIfPresent(oldShapePolyline, forKey: .oldShapePolyline)
        try container.encodeIfPresent(realtimeShape, forKey: .realtimeShape)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encode(stopTimes, forKey: .stopTimes)
        try container.encode(alerts, forKey: .alerts)
        try container.encodeIfPresent(isCancelled, forKey: .isCancelled)
        try container.encodeIfPresent(deleted, forKey: .deleted)
    }
}

struct SingleTripStopTimeRefresh: Codable, Equatable {
    let stopID: String?
    let realtimeArrival: SingleTripRealtimeTime?
    let realtimeDeparture: SingleTripRealtimeTime?
    let scheduleRelationship: Int?
    let gtfsStopSequence: Int?
    let realtimePlatformString: String?
    let departureOccupancyStatus: Int?

    enum CodingKeys: String, CodingKey {
        case stopID = "stop_id"
        case realtimeArrival = "rt_arrival"
        case realtimeDeparture = "rt_departure"
        case scheduleRelationship = "schedule_relationship"
        case gtfsStopSequence = "gtfs_stop_sequence"
        case realtimePlatformString = "rt_platform_string"
        case departureOccupancyStatus = "departure_occupancy_status"
    }
}

struct SingleTripRealtimeUpdate: Codable, Equatable {
    let stopTimes: [SingleTripStopTimeRefresh]
    let timestamp: Int64?
    let tripID: String?
    let chateau: String?

    enum CodingKeys: String, CodingKey {
        case stopTimes = "stoptimes"
        case timestamp
        case tripID = "trip_id"
        case chateau
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stopTimes = try container.decodeIfPresent([SingleTripStopTimeRefresh].self, forKey: .stopTimes) ?? []
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        tripID = try container.decodeIfPresent(String.self, forKey: .tripID)
        chateau = try container.decodeIfPresent(String.self, forKey: .chateau)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stopTimes, forKey: .stopTimes)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(tripID, forKey: .tripID)
        try container.encodeIfPresent(chateau, forKey: .chateau)
    }
}

struct SingleTripVehiclePosition: Codable, Equatable {
    let latitude: Double?
    let longitude: Double?
    let bearing: Float?
    let odometer: Double?
    let speed: Float?
}

struct SingleTripRealtimeVehicleInfo: Codable, Equatable {
    let id: String?
    let label: String?
    let licensePlate: String?
    let wheelchairAccessible: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case licensePlate = "license_plate"
        case wheelchairAccessible = "wheelchair_accessible"
    }
}

struct SingleTripRealtimeTripInfo: Codable, Equatable {
    let tripID: String?
    let tripHeadsign: String?
    let routeID: String?
    let tripShortName: String?
    let directionID: Int?
    let startTime: String?
    let startDate: String?
    let scheduleRelationship: String?
    let delay: Int?

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case tripHeadsign = "trip_headsign"
        case routeID = "route_id"
        case tripShortName = "trip_short_name"
        case directionID = "direction_id"
        case startTime = "start_time"
        case startDate = "start_date"
        case scheduleRelationship = "schedule_relationship"
        case delay
    }
}

struct SingleTripVehicleRealtimeData: Codable, Equatable {
    let timestamp: Int64?
    let position: SingleTripVehiclePosition?
    let occupancyStatus: String?
    let occupancyPercentage: Int?
    let vehicle: SingleTripRealtimeVehicleInfo?
    let trip: SingleTripRealtimeTripInfo?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case position
        case occupancyStatus = "occupancy_status"
        case occupancyPercentage = "occupancy_percentage"
        case vehicle
        case trip
    }
}

struct SingleTripVehicleRealtimeDataResponse: Codable, Equatable {
    let data: [SingleTripVehicleRealtimeData]?
}

struct SingleTripStopState: Identifiable, Equatable {
    var raw: SingleTripStopTime
    var realtimeArrivalTime: Int64?
    var realtimeDepartureTime: Int64?
    var realtimeArrivalDifference: Int64?
    var realtimeDepartureDifference: Int64?

    var id: String { raw.id }

    var displayName: String {
        let trimmed = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : raw.stopID
    }

    var isCancelled: Bool { raw.scheduleRelationship == 1 }

    var platform: String? {
        let realtime = raw.realtimePlatformString?.trimmingCharacters(in: .whitespacesAndNewlines)
        if realtime?.isEmpty == false { return realtime }
        let code = raw.code?.trimmingCharacters(in: .whitespacesAndNewlines)
        return code?.isEmpty == false ? code : nil
    }
}
