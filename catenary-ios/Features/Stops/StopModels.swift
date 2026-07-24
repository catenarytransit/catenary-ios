import CoreLocation
import Foundation

enum StopScreenSource: Hashable, Sendable {
    case stop(chateauID: String, stopID: String)
    case osmStation(id: String)

    init?(destination: CatenaryStackItem) {
        switch destination {
        case let .stop(chateauID, stopID, _):
            self = .stop(chateauID: chateauID, stopID: stopID)
        case let .osmStation(osmStationID, _, _, _, _, _):
            self = .osmStation(id: osmStationID)
        default:
            return nil
        }
    }

    var id: String {
        switch self {
        case let .stop(chateauID, stopID):
            return "stop|\(chateauID)|\(stopID)"
        case let .osmStation(id):
            return "osm|\(id)"
        }
    }

    var explicitChateauID: String? {
        guard case let .stop(chateauID, _) = self else { return nil }
        return chateauID
    }
}

struct StopPrimary: Decodable, Equatable, Sendable {
    let stopName: String
    let stopLon: Double
    let stopLat: Double
    let timezone: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: stopLat, longitude: stopLon)
    }
}

struct StopRouteInfo: Decodable, Equatable, Sendable {
    let color: String?
    let textColor: String?
    let shortName: String?
    let longName: String?
    let shapesList: [String]?
    let routeType: Int?
    let agencyId: String?
}

struct StopAgencyInfo: Decodable, Equatable, Sendable {
    let agencyName: String
    let agencyUrl: String?
    let agencyTimezone: String?
    let agencyLang: String?
    let agencyPhone: String?
    let agencyFareUrl: String?
}

struct StopEvent: Decodable, Equatable, Identifiable, Sendable {
    let chateau: String
    let tripId: String?
    let routeId: String
    let serviceDate: String?
    let headsign: String?
    let stopId: String
    let scheduledDeparture: Int64?
    let realtimeDeparture: Int64?
    let scheduledArrival: Int64?
    let realtimeArrival: Int64?
    let tripShortName: String?
    var lastStop: Bool?
    let platformStringRealtime: String?
    let vehicleNumber: String?
    let delaySeconds: Int64?
    let tripCancelled: Bool?
    let stopCancelled: Bool?
    let tripDeleted: Bool?
    let routeType: Int?
    let timezone: String?
    let distanceM: Double?
    let finalStationName: String?

    var id: String { eventKey }

    var eventKey: String {
        let scheduled = scheduledDeparture ?? scheduledArrival ?? 0
        return [
            chateau,
            tripId ?? "",
            routeId,
            headsign ?? "",
            stopId,
            serviceDate ?? "",
            String(scheduled)
        ].joined(separator: "|")
    }

    var effectiveTime: Int64? {
        if lastStop == true {
            return realtimeArrival ?? scheduledArrival ?? realtimeDeparture ?? scheduledDeparture
        }
        return realtimeDeparture ?? scheduledDeparture ?? realtimeArrival ?? scheduledArrival
    }

    var scheduledTime: Int64? {
        if lastStop == true {
            return scheduledArrival ?? scheduledDeparture
        }
        return scheduledDeparture ?? scheduledArrival
    }

    var realtimeTime: Int64? {
        if lastStop == true {
            return realtimeArrival ?? realtimeDeparture
        }
        return realtimeDeparture ?? realtimeArrival
    }

    var isCancelled: Bool {
        tripCancelled == true || stopCancelled == true || tripDeleted == true
    }

    var isTerminalArrivalOnly: Bool {
        lastStop == true && scheduledDeparture == nil && realtimeDeparture == nil
    }

    var normalizedForStationDisplay: StopEvent {
        guard lastStop == true,
              scheduledDeparture != nil || realtimeDeparture != nil else {
            return self
        }
        var copy = self
        copy.lastStop = false
        return copy
    }
}

struct DeparturesAtStopResponse: Decodable, Sendable {
    let primary: StopPrimary?
    let routes: [String: [String: StopRouteInfo]]?
    let events: [StopEvent]?
    let agencies: [String: [String: StopAgencyInfo]]?
    let stops: [StopPrimary]?
}

struct OSMStationRedirectResponse: Decodable, Sendable {
    let redirectToOsmStationId: Int64
}

struct OSMStationLookupResponse: Decodable, Sendable {
    let found: Bool
    let osmStationId: Int64?
    let osmStationInfo: OSMStationInfo?
}

struct OSMStationInfo: Decodable, Sendable {
    let name: String?
    let modeType: String?
    let lat: Double?
    let lon: Double?
}

enum StopTransitMode: String, CaseIterable, Identifiable, Sendable {
    case rail
    case metro
    case bus
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rail: return "Rail"
        case .metro: return "Metro & tram"
        case .bus: return "Bus"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .rail: return "tram.fill.tunnel"
        case .metro: return "lightrail.fill"
        case .bus: return "bus.fill"
        case .other: return "ferry.fill"
        }
    }

    static func from(routeType: Int?) -> StopTransitMode {
        switch routeType {
        case 2, 100, 101, 102, 103, 106, 107:
            return .rail
        case 0, 1, 5, 7, 12, 900:
            return .metro
        case 3, 11, 700:
            return .bus
        default:
            return .other
        }
    }
}

struct StopDaySection: Identifiable, Equatable {
    let date: Date
    let events: [StopEvent]

    var id: Date { date }
}

enum StopTrainCategoryClassifier {
    static func categories(for chateauID: String?) -> [String] {
        switch chateauID {
        case "île~de~france~mobilités":
            return ["Grandes lignes", "RER", "Transilien"]
        case "deutschland":
            return ["S-Bahn", "ICE/TGV/RJX", "IC/EC", "IR", "RE/RB", "Other"]
        case "schweiz":
            return ["ICE/TGV/RJX", "EC/IC", "IR/PE", "RE", "S/SN/R", "ARZ/EXT"]
        default:
            return []
        }
    }

    static func category(chateauID: String?, shortName: String?) -> String {
        let normalized = (shortName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        switch chateauID {
        case "île~de~france~mobilités":
            if ["A", "B", "C", "D", "E"].contains(normalized) { return "RER" }
            if ["H", "J", "K", "L", "N", "P", "R", "U", "V"].contains(normalized) {
                return "Transilien"
            }
            return "Grandes lignes"

        case "deutschland":
            if normalized.range(of: #"^S\d+"#, options: .regularExpression) != nil { return "S-Bahn" }
            if normalized.hasPrefix("ICE") || normalized.hasPrefix("TGV") || normalized.hasPrefix("RJX") {
                return "ICE/TGV/RJX"
            }
            if normalized.hasPrefix("IC") || normalized.hasPrefix("EC") { return "IC/EC" }
            if normalized.hasPrefix("IR") { return "IR" }
            if normalized.hasPrefix("RE") || normalized.hasPrefix("RB") { return "RE/RB" }
            return "Other"

        case "schweiz":
            if normalized.hasPrefix("ICE") || normalized.hasPrefix("TGV") || normalized.hasPrefix("RJX") {
                return "ICE/TGV/RJX"
            }
            if normalized.hasPrefix("EC") || normalized.hasPrefix("IC") { return "EC/IC" }
            if normalized.hasPrefix("IR") || normalized.hasPrefix("PE") { return "IR/PE" }
            if normalized.hasPrefix("RE") { return "RE" }
            if normalized.hasPrefix("ARZ") || normalized.hasPrefix("EXT") { return "ARZ/EXT" }
            return "S/SN/R"

        default:
            return "Other"
        }
    }
}

extension CatenaryStackItem {
    var stopScreenIdentity: String {
        StopScreenSource(destination: self)?.id ?? id
    }
}
