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


/// Coordinates are stored as Equatable values so map updates do not require
/// making CLLocationCoordinate2D conform to Equatable.
struct TransitMapCoordinate: Equatable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

struct TransitMapStop: Equatable {
    let id: String
    let name: String
    let coordinate: TransitMapCoordinate
}

/// Context for the visible trip or route screen. The owner ID prevents an older
/// screen from clearing the overlay belonging to a newer navigation destination.
struct SelectedTransitMapContext: Equatable {
    let id: String
    let colorHex: String
    let line: [TransitMapCoordinate]
    let stops: [TransitMapStop]
}

/// GTFS/Google encoded polylines use 1e5 coordinates and zig-zag varints.
/// Reject incomplete or invalid polylines instead of drawing misleading lines.
enum TransitPolylineDecoder {
    static func decode(_ encoded: String?) -> [TransitMapCoordinate] {
        guard let encoded, !encoded.isEmpty else { return [] }
        let bytes = Array(encoded.utf8)
        var cursor = 0

        func nextDelta() -> Int64? {
            var value: Int64 = 0
            var shift = 0
            while cursor < bytes.count {
                let byte = bytes[cursor]
                cursor += 1
                guard byte >= 63 && byte <= 126, shift <= 55 else { return nil }
                let chunk = Int64(byte - 63)
                value |= (chunk & 0x1f) << shift
                if (chunk & 0x20) == 0 {
                    return (value & 1) == 0 ? (value >> 1) : ~(value >> 1)
                }
                shift += 5
            }
            return nil
        }

        var latitude: Int64 = 0
        var longitude: Int64 = 0
        var points: [TransitMapCoordinate] = []
        while cursor < bytes.count {
            guard points.count < 100_000,
                  let latDelta = nextDelta(),
                  let lonDelta = nextDelta() else { return [] }
            let (nextLatitude, latOverflow) = latitude.addingReportingOverflow(latDelta)
            let (nextLongitude, lonOverflow) = longitude.addingReportingOverflow(lonDelta)
            guard !latOverflow, !lonOverflow else { return [] }
            latitude = nextLatitude
            longitude = nextLongitude
            let point = TransitMapCoordinate(
                latitude: Double(latitude) / 100_000,
                longitude: Double(longitude) / 100_000
            )
            guard point.isValid else { return [] }
            points.append(point)
        }
        return points
    }
}
