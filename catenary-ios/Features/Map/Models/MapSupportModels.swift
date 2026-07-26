//
//  MapSupportModels.swift
//  catenary-ios
//

import CoreLocation

struct SelectedStopMapContext: Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
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
