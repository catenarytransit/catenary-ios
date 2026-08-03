//
//  CatenaryStackItem.swift
//  catenary-ios
//

// MARK: - Typed navigation stack

/// Swift equivalent of catenary-compose's `CatenaryStackEnum`.
///
/// Keeping the full destination payload in the stack makes back navigation
/// deterministic and lets individual screens restore local state (for example,
/// the selected departure time on a stop screen).
enum CatenaryStackItem: Hashable, Identifiable {
    case singleTrip(
        chateauID: String,
        tripID: String?,
        routeID: String?,
        startTime: String?,
        startDate: String?,
        vehicleID: String?,
        routeType: Int?
    )
    case vehicleSelected(chateauID: String, vehicleID: String?, gtfsID: String)
    case vehicleHistory(chateauID: String, vehicleID: String, routeID: String?)
    case route(chateauID: String, routeID: String)
    case stop(chateauID: String, stopID: String, timeEpochSeconds: Int64? = nil)
    case nearbyDepartures(chateauID: String, latitude: Double, longitude: Double)
    case mapSelectionScreen(options: [MapSelectionOption])
    case settings
    case block(chateauID: String, blockID: String, serviceDate: String)
    case osmItem(osmID: String, osmClass: String, osmType: String?)
    case osmStation(
        osmStationID: String,
        stationName: String?,
        modeType: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timeEpochSeconds: Int64? = nil
    )

    var id: String {
        switch self {
        case let .singleTrip(chateauID, tripID, routeID, startTime, startDate, vehicleID, routeType):
            return "trip|\(chateauID)|\(tripID ?? "")|\(routeID ?? "")|\(startTime ?? "")|\(startDate ?? "")|\(vehicleID ?? "")|\(routeType.map { String($0) } ?? "")"
        case let .vehicleSelected(chateauID, vehicleID, gtfsID):
            return "vehicle|\(chateauID)|\(vehicleID ?? "")|\(gtfsID)"
        case let .vehicleHistory(chateauID, vehicleID, routeID):
            return "vehicle-history|\(chateauID)|\(vehicleID)|\(routeID ?? "")"
        case let .route(chateauID, routeID):
            return "route|\(chateauID)|\(routeID)"
        case let .stop(chateauID, stopID, timeEpochSeconds):
            return "stop|\(chateauID)|\(stopID)|\(timeEpochSeconds.map { String($0) } ?? "now")"
        case let .nearbyDepartures(chateauID, latitude, longitude):
            return "nearby|\(chateauID)|\(latitude)|\(longitude)"
        case let .mapSelectionScreen(options):
            return "selection|" + options.map(\.id).joined(separator: ",")
        case .settings:
            return "settings"
        case let .block(chateauID, blockID, serviceDate):
            return "block|\(chateauID)|\(blockID)|\(serviceDate)"
        case let .osmItem(osmID, osmClass, osmType):
            return "osm-item|\(osmID)|\(osmClass)|\(osmType ?? "")"
        case let .osmStation(osmStationID, stationName, modeType, latitude, longitude, timeEpochSeconds):
            return "osm-station|\(osmStationID)|\(stationName ?? "")|\(modeType ?? "")|\(latitude.map { String($0) } ?? "")|\(longitude.map { String($0) } ?? "")|\(timeEpochSeconds.map { String($0) } ?? "now")"
        }
    }
}

struct MapSelectionOption: Hashable, Identifiable {
    let data: MapSelectionSelector

    var id: String { data.id }
    var destination: CatenaryStackItem { data.destination }
}

enum MapSelectionSelector: Hashable, Identifiable {
    case stop(chateauID: String, stopID: String, stopName: String)
    case route(
        chateauID: String,
        routeID: String,
        colour: String,
        name: String?,
        routeType: Int?
    )
    case vehicle(
        chateauID: String,
        vehicleID: String?,
        routeID: String?,
        headsign: String,
        tripLabel: String?,
        colour: String,
        routeShortName: String?,
        routeLongName: String?,
        routeType: Int,
        tripShortName: String?,
        textColour: String,
        gtfsID: String,
        tripID: String?,
        startTime: String?,
        startDate: String?
    )
    case osmStation(
        osmID: String,
        name: String,
        modeType: String,
        latitude: Double,
        longitude: Double
    )

    var id: String {
        switch self {
        case let .stop(chateauID, stopID, _):
            return "stop|\(chateauID)|\(stopID)"
        case let .route(chateauID, routeID, _, _, _):
            return "route|\(chateauID)|\(routeID)"
        case let .vehicle(chateauID, vehicleID, _, _, _, _, _, _, _, _, _, gtfsID, tripID, _, _):
            return "vehicle|\(chateauID)|\(vehicleID ?? "")|\(gtfsID)|\(tripID ?? "")"
        case let .osmStation(osmID, _, _, _, _):
            return "osm-station|\(osmID)"
        }
    }

    var title: String {
        switch self {
        case let .stop(_, _, stopName):
            return stopName
        case let .route(_, routeID, _, name, _):
            return name?.isEmpty == false ? name! : routeID
        case let .vehicle(_, _, _, headsign, tripLabel, _, routeShortName, routeLongName, _, _, _, _, _, _, _):
            return routeShortName ?? tripLabel ?? routeLongName ?? headsign
        case let .osmStation(_, name, _, _, _):
            return name
        }
    }

    var subtitle: String {
        switch self {
        case let .stop(_, stopID, _):
            return stopID
        case let .route(_, routeID, _, _, _):
            return routeID
        case let .vehicle(_, vehicleID, _, headsign, _, _, _, _, _, _, _, _, _, _, _):
            return vehicleID.map { "\(headsign) • \($0)" } ?? headsign
        case let .osmStation(_, _, modeType, _, _):
            return modeType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var systemImage: String {
        switch self {
        case .stop: return "mappin.circle.fill"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .vehicle: return "location.fill"
        case .osmStation: return "building.2.fill"
        }
    }

    var destination: CatenaryStackItem {
        switch self {
        case let .stop(chateauID, stopID, _):
            return .stop(chateauID: chateauID, stopID: stopID)
        case let .route(chateauID, routeID, _, _, _):
            return .route(chateauID: chateauID, routeID: routeID)
        case let .vehicle(chateauID, vehicleID, routeID, _, _, _, _, _, routeType, _, _, gtfsID, tripID, startTime, startDate):
            if tripID != nil || routeID != nil {
                return .singleTrip(
                    chateauID: chateauID,
                    tripID: tripID,
                    routeID: routeID,
                    startTime: startTime,
                    startDate: startDate,
                    vehicleID: vehicleID,
                    routeType: routeType
                )
            }
            return .vehicleSelected(chateauID: chateauID, vehicleID: vehicleID, gtfsID: gtfsID)
        case let .osmStation(osmID, name, modeType, latitude, longitude):
            return .osmStation(
                osmStationID: osmID,
                stationName: name,
                modeType: modeType,
                latitude: latitude,
                longitude: longitude
            )
        }
    }
}
