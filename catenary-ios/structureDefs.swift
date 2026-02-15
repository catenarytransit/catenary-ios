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
    static let catenaryBlue = Color(red: 0 / 255.0, green: 171 / 255.0, blue: 155 / 255.0)
}

extension UIColor {
    static let catenaryBlue = UIColor(red: 0 / 255.0, green: 171 / 255.0, blue: 155 / 255.0, alpha: 1)
}

class viewObject: ObservableObject {
    @Published var camera: MapViewCamera = MapViewCamera.center(CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), zoom: 5.0)
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
    
    @Published var centered: Bool = false
    @Published var showLayerSelector: Bool = false
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
}

struct AllLayerSettings {
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

struct LayerCategorySettings {
    var visiblerealtimedots: Bool = true
    var labelshapes: Bool = true
    var stops: Bool = true
    var shapes: Bool = true
    var labelstops: Bool = true
    var labelrealtimedots: LabelSettings = LabelSettings()
}

struct LabelSettings {
    var route: Bool = true
    var trip: Bool = false
    var vehicle: Bool = false
    var headsign: Bool = false
    var direction: Bool = false
    var speed: Bool = false
    var occupancy: Bool = true
    var delay: Bool = true
}

struct MoreSettings {
    var foamermode: FoamermodeSettings = FoamermodeSettings()
    var showstationentrances: Bool = true
    var showstationart: Bool = false
    var showbikelanes: Bool = false
    var showcoords: Bool = false
}

struct FoamermodeSettings {
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


