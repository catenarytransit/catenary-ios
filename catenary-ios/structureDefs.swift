//
//  structureDefs.swift
//  catenary-ios
//
//

import Foundation
import SwiftUI
import MapLibreSwiftUI
import MapLibre
import CoreLocation

extension Color {
    static let catenaryBlue   = Color(red: 0/255.0, green: 171/255.0, blue: 155/255.0)
    static let railCategory   = Color.blue           // matches mapLibreView line 830
    static let metroCategory  = Color.purple         // line 841
    static let tramCategory   = Color.green          // line 852  (note: Metro/Tram tab uses Metro's purple)
    static let busCategory    = Color.catenaryBlue   // line 863
    static let otherCategory  = Color.orange         // line 874
}
extension UIColor {
    static let catenaryBlue   = UIColor(red: 0/255.0, green: 171/255.0, blue: 155/255.0, alpha: 1)
    static let railCategory   = UIColor.systemBlue
    static let metroCategory  = UIColor.systemPurple
    static let tramCategory   = UIColor.systemGreen
    static let busCategory    = UIColor.catenaryBlue
    static let otherCategory  = UIColor.systemOrange
}

struct SelectedStopMapContext: Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

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

class viewObject: ObservableObject {
    @Published var camera: MapViewCamera = MapViewCamera.center(CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), zoom: 5.0)
    @Published private(set) var selectedStopContext: SelectedStopMapContext?

    func setSelectedStopContext(_ context: SelectedStopMapContext) {
        guard selectedStopContext != context else { return }
        selectedStopContext = context
    }

    func clearSelectedStopContext(id: String) {
        guard selectedStopContext?.id == id else { return }
        selectedStopContext = nil
    }

    @Published var allLayerSettings: AllLayerSettings = AllLayerSettings()
    @Published var currZoom: Double = 5.0
    @Published var visibleCoordinateBounds: MLNCoordinateBounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: 0, longitude: 0), ne: CLLocationCoordinate2D(latitude: 0, longitude: 0))
    
    @Published var searchText = ""
    @Published var showTopView = false
    @Published var presDetent: PresentationDetent = .height(80)
    @Published var sheetHeight: CGFloat = 350 {
            didSet { checkHeightEquality() }
        }
    @Published var largeDetentHeight: CGFloat = 0
    @Published var currentRotation: CLLocationDirection = 0
    @Published var isSearchFocusing: Bool = false
    
    /// `true` whenever the map camera is in any user-tracking mode.
    /// Derived from `camera.state`, so it updates automatically when the user
    /// pans the map and MapLibre exits tracking.
    var centered: Bool {
        switch camera.state {
        case .trackingUserLocation,
             .trackingUserLocationWithHeading,
             .trackingUserLocationWithCourse:
            return true
        default:
            return false
        }
    }
    @Published var showLayerSelector: Bool = false
    @Published private(set) var catenaryStack: [CatenaryStackItem] = []

    var currentStackItem: CatenaryStackItem? { catenaryStack.last }

    func push(_ item: CatenaryStackItem) {
        catenaryStack.append(item)
        presDetent = .large
        isSearchFocusing = false
    }

    func replaceTop(with item: CatenaryStackItem) {
        if catenaryStack.isEmpty {
            catenaryStack.append(item)
        } else {
            catenaryStack[catenaryStack.count - 1] = item
        }
        presDetent = .large
    }

    @discardableResult
    func pop() -> CatenaryStackItem? {
        catenaryStack.popLast()
    }

    func home() {
        catenaryStack.removeAll()
        selectedStopContext = nil
        presDetent = .height(350)
    }

    /// Mirrors StopScreen's `updateStackTime`: replace the current destination
    /// instead of pushing another copy, so returning to the screen restores the
    /// selected time slice.
    func updateCurrentStopTime(_ timeEpochSeconds: Int64?) {
        guard let current = currentStackItem else { return }
        switch current {
        case let .stop(chateauID, stopID, oldTime):
            guard oldTime != timeEpochSeconds else { return }
            replaceTop(with: .stop(
                chateauID: chateauID,
                stopID: stopID,
                timeEpochSeconds: timeEpochSeconds
            ))
        case let .osmStation(osmStationID, stationName, modeType, latitude, longitude, oldTime):
            guard oldTime != timeEpochSeconds else { return }
            replaceTop(with: .osmStation(
                osmStationID: osmStationID,
                stationName: stationName,
                modeType: modeType,
                latitude: latitude,
                longitude: longitude,
                timeEpochSeconds: timeEpochSeconds
            ))
        default:
            break
        }
    }

    func openDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        func query(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name == name })?.value
        }

        switch query("screen") {
        case "route":
            guard let chateauID = query("chateau"), let routeID = query("route_id") else { return }
            push(.route(chateauID: chateauID, routeID: routeID))
        case "stop":
            guard let chateauID = query("chateau"), let stopID = query("stop_id") else { return }
            push(.stop(chateauID: chateauID, stopID: stopID))
        case "trip":
            guard let chateauID = query("chateau") else { return }
            push(.singleTrip(
                chateauID: chateauID,
                tripID: query("trip_id"),
                routeID: query("route_id"),
                startTime: query("start_time"),
                startDate: query("start_date"),
                vehicleID: query("vehicle_id"),
                routeType: query("route_type").flatMap { Int($0) }
            ))
        case "osm_station":
            guard let osmStationID = query("osm_station_id") else { return }
            push(.osmStation(
                osmStationID: osmStationID,
                stationName: query("station_name"),
                modeType: query("mode_type"),
                latitude: query("lat").flatMap { Double($0) },
                longitude: query("lon").flatMap { Double($0) }
            ))
        default:
            break
        }
    }

    @Published var confirmedEqual: Bool = false
    private var equalityTimer: Timer?
    private let equalityDuration: TimeInterval = 0.25
    
    private func checkHeightEquality() {
        if sheetHeight == largeDetentHeight {
            // start or restart the timer
            equalityTimer?.invalidate()
            equalityTimer = Timer.scheduledTimer(withTimeInterval: equalityDuration, repeats: false) { [weak self] _ in
                withAnimation {
                    self?.confirmedEqual = true
                }
            }
        } else {
            // if diiverged: reset
            equalityTimer?.invalidate()
            withAnimation {
                confirmedEqual = false
            }
        }
    }
    
    deinit {
        equalityTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    @Published var isVisible: Bool = false
    @Published var topHeightKeys: CGFloat = 0
//    @Published var sheetHeight: CGFloat = 0

    init() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isVisible = true
            self?.topHeightKeys = self?.sheetHeight ?? 350
            self?.sheetHeight = self?.largeDetentHeight ?? 350
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isVisible = false
        }
    }

}

struct ShapeSources {
    static var intercityrailshapes = URL(string: "https://birch1.catenarymaps.org/shapes_intercity_rail")!
    static var localcityrailshapes = URL(string: "https://birch2.catenarymaps.org/shapes_local_rail")!
    static var othershapes = URL(string: "https://birch3.catenarymaps.org/shapes_ferry")!
    static var busshapes = URL(string: "https://birch4.catenarymaps.org/shapes_bus")!
    
    static var busstops = URL(string: "https://birch6.catenarymaps.org/busstops")!
    static var stationfeatures = URL(string: "https://birch7.catenarymaps.org/station_features")!
    static var railstops = URL(string: "https://birch5.catenarymaps.org/railstops")!
    static var otherstops = URL(string: "https://birch8.catenarymaps.org/otherstops")!
    static var osmstations = URL(string: "https://birch.catenarymaps.org/osm_stations")!
    static var bulkrealtimefetch = URL(string: "https://birch.catenarymaps.org/bulk_realtime_fetch_v3")!
}

enum shapeTileSources {
    static func intercityRailSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "intercityraillayer",
            configurationURL: ShapeSources.intercityrailshapes
        )
    }
    
    static func localCityRailSource() -> MLNVectorTileSource {
            MLNVectorTileSource(
                identifier: "localcityraillayer",
                configurationURL: ShapeSources.localcityrailshapes
            )
        }
    
    static func otherShapesSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "otherlayer",
            configurationURL: ShapeSources.othershapes
        )
    }
    
    static func busSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "buslayer",
            configurationURL: ShapeSources.busshapes
        )
    }
    
    static func busStopsSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "busstops",
            configurationURL: ShapeSources.busstops
        )
    }
    
    static func stationFeaturesSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "stationfeatures",
            configurationURL: ShapeSources.stationfeatures
        )
    }

    static func railStopsSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "railstops",
            configurationURL: ShapeSources.railstops
        )
    }

    static func otherStopsSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "otherstops",
            configurationURL: ShapeSources.otherstops
        )
    }
    
    static func osmStationsSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "osmstations",
            configurationURL: ShapeSources.osmstations
        )
    }
    
    static func bulkRealTimeFetchSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "bulkrealtimefetch",
            configurationURL: ShapeSources.bulkrealtimefetch
        )
    }
}

struct AllLayerSettings: Equatable {
    var bus: LayerCategorySettings = LayerCategorySettings()
    var localrail: LayerCategorySettings = LayerCategorySettings()
    var intercityrail: LayerCategorySettings = LayerCategorySettings(labelrealtimedots: LabelSettings(trip: true))
    var other: LayerCategorySettings = LayerCategorySettings()
    var more: MoreSettings = MoreSettings()
    
    subscript(index: Int) -> LayerCategorySettings? {
            switch index {
            case 1: return intercityrail
            case 2: return localrail
            case 3: return bus
            case 4: return other
            default: return nil
            }
        }
    
    subscript(name: String) -> LayerCategorySettings? {
            switch name {
            case "Rail": return intercityrail
            case "Metro/Tram": return localrail
            case "Bus": return bus
            case "Other": return other
            default: return nil
            }
        }
    
}

struct LayerCategorySettings: Equatable {
    var visiblerealtimedots: Bool = true
    var labelshapes: Bool = true
    var stops: Bool = true
    var shapes: Bool = true
    var labelstops: Bool = true
    var labelrealtimedots: LabelSettings = LabelSettings()
}

struct LabelSettings: Equatable {
    var route: Bool = true
    var trip: Bool = false
    var vehicle: Bool = false
    var headsign: Bool = false
    var direction: Bool = false
    var speed: Bool = false
    var occupancy: Bool = true
    var delay: Bool = true
}

struct MoreSettings: Equatable {
    var foamermode: FoamermodeSettings = FoamermodeSettings()
    var showstationentrances: Bool = true
    var showstationart: Bool = false
    var showbikelanes: Bool = false
    var showcoords: Bool = false
}

struct FoamermodeSettings: Equatable {
    var infra: Bool = false
    var maxspeed: Bool = false
    var signalling: Bool = false
    var electrification: Bool = false
    var gauge: Bool = false
    var dummy: Bool = true
}

struct RouteCacheEntry: Codable {
    let color: String
    let text_color: String
    let short_name: String?
    let long_name: String?
    let route_id: String
    let agency_id: String?
}

struct TileBounds {
    let min_x: Int
    let max_x: Int
    let min_y: Int
    let max_y: Int
}



enum LayersPerCategory {

    static let Bus = BusCategory()
    static let Other = OtherCategory()
    static let IntercityRail = IntercityRailCategory()
    static let Metro = MetroCategory()
    static let Tram = TramCategory()
    static let TrajectoryBus = TrajectoryCategory(prefix: "trajectory-bus")
    static let TrajectoryMetro = TrajectoryCategory(prefix: "trajectory-metro")
    static let TrajectoryTram = TrajectoryCategory(prefix: "trajectory-tram")
    static let TrajectoryIntercityRail = TrajectoryCategory(prefix: "trajectory-intercityrail")
    static let TrajectoryOther = TrajectoryCategory(prefix: "trajectory-other")

    struct TrajectoryCategory {
        let Livedots: String

        init(prefix: String) {
            Livedots = "\(prefix)-livedots"
        }
    }

    struct BusCategory {
        let Shapes = "bus-shapes"
        let LabelShapes = "bus-labelshapes"
        let Stops = "bus-stops"
        let LabelStops = "bus-labelstops"
        let Livedots = "bus-livedots"
        let Labeldots = "bus-labeldots"
        let Pointing = "bus-pointing"
        let PointingShell = "bus-pointingshell"
    }

    struct OtherCategory {
        let Shapes = "other-shapes"
        let LabelShapes = "other-labelshapes"
        let FerryShapes = "ferryshapes"
        let Stops = "other-stops"
        let LabelStops = "other-labelstops"
        let Livedots = "other-livedots"
        let Labeldots = "other-labeldots"
        let Pointing = "other-pointing"
        let PointingShell = "other-pointingshell"
    }

    struct IntercityRailCategory {
        let Shapes = "intercityrail-shapes"
        let LabelShapes = "intercityrail-labelshapes"
        let Stops = "intercityrail-stops"
        let LabelStops = "intercityrail-labelstops"
        let Livedots = "intercityrail-livedots"
        let Labeldots = "intercityrail-labeldots"
        let Pointing = "intercityrail-pointing"
        let PointingShell = "intercityrail-pointingshell"
    }

    struct MetroCategory {
        let Shapes = "metro-shapes"
        let LabelShapes = "metro-labelshapes"
        let Stops = "metro-stops"
        let LabelStops = "metro-labelstops"
        let Livedots = "metro-livedots"
        let Labeldots = "metro-labeldots"
        let Pointing = "metro-pointing"
        let PointingShell = "metro-pointingshell"
    }

    struct TramCategory {
        let Shapes = "tram-shapes"
        let LabelShapes = "tram-labelshapes"
        let Stops = "tram-stops"
        let LabelStops = "tram-labelstops"
        let Livedots = "tram-livedots"
        let Labeldots = "tram-labeldots"
        let Pointing = "tram-pointing"
        let PointingShell = "tram-pointingshell"
    }
}

