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

class viewObject: ObservableObject {
    @Published var camera: MapViewCamera = MapViewCamera.center(CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), zoom: 5.0)
    @Published var allLayerSettings: AllLayerSettings = AllLayerSettings()
    @Published var tempShow = false
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
}

struct shapeTileSources {
    static let intercityRailSource = MLNVectorTileSource(
        identifier: "intercityraillayer",
        configurationURL: ShapeSources.intercityrailshapes
    )
    
    static let localCityRailSource = MLNVectorTileSource(
        identifier: "localcityraillayer",
        configurationURL: ShapeSources.localcityrailshapes
    )
    
    static let otherShapesSource = MLNVectorTileSource(
        identifier: "otherlayer",
        configurationURL: ShapeSources.othershapes
    )
    
    static let busSource = MLNVectorTileSource(
        identifier: "buslayer",
        configurationURL: ShapeSources.busshapes
    )
    
    static let busStopsSource = MLNVectorTileSource(
        identifier: "busstops",
        configurationURL: ShapeSources.busstops
    )
    
    static let stationFeaturesSource = MLNVectorTileSource(
        identifier: "stationfeatures",
        configurationURL: ShapeSources.stationfeatures
    )
    
    static let railStopsSource = MLNVectorTileSource(
        identifier: "railstops",
        configurationURL: ShapeSources.railstops
    )
    
    static let otherStopsSource = MLNVectorTileSource(
        identifier: "otherstops",
        configurationURL: ShapeSources.otherstops
    )
}


struct AllLayerSettings {
    var bus: LayerCategorySettings = LayerCategorySettings()
    var localrail: LayerCategorySettings = LayerCategorySettings()
    var intercityrail: LayerCategorySettings = LayerCategorySettings(labelrealtimedots: LabelSettings(trip: true))
    var other: LayerCategorySettings = LayerCategorySettings()
    var more: MoreSettings = MoreSettings()
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

struct FoamermodeSettings {
    var infra: Bool = false
    var maxspeed: Bool = false
    var signalling: Bool = false
    var electrification: Bool = false
    var gauge: Bool = false
    var dummy: Bool = true
}

struct MoreSettings {
    var foamermode: FoamermodeSettings = FoamermodeSettings()
    var showstationentrances: Bool = true
    var showstationart: Bool = false
    var showbikelanes: Bool = false
    var showcoords: Bool = false
}



struct VehiclePositionData {
    var latitude: Double
    var longitude: Double
    var bearing: Float?
    var speed: Float?
}

struct VehicleDescriptor {
    var id: String?
    var label: String?
}

struct TripDescriptor {
    var trip_id: String?
    var route_id: String?
    var trip_headsign: String?
    var trip_short_name: String?
    var start_time: String?
    var start_date: String?
    var delay: Int?
}

struct VehiclePosition {
    var position: VehiclePositionData?
    var vehicle: VehicleDescriptor?
    var trip: TripDescriptor?
    var route_type: Int
    var timestamp: Int?
    var occupancy_status: Int?
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
