//
//  MapSources.swift
//  catenary-ios
//

import Foundation
import MapLibre

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
    static var osmstationsranked = URL(string: "https://birch.catenarymaps.org/osm_stations_ranked")!
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

    static func osmStationsRankedSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "osmstationsranked",
            configurationURL: ShapeSources.osmstationsranked
        )
    }

    static func bulkRealTimeFetchSource() -> MLNVectorTileSource {
        MLNVectorTileSource(
            identifier: "bulkrealtimefetch",
            configurationURL: ShapeSources.bulkrealtimefetch
        )
    }
}
