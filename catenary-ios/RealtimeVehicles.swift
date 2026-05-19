//
//  RealtimeVehicles.swift
//  catenary-ios
//
//  Polls `POST /bulk_realtime_fetch_v3` on a 2.5s timer and exposes a
//  flattened, observable list of vehicle positions for the map to render.
//
//  Wire types mirror `catenary-backend/src/birch/aspenised_data_over_https.rs`
//  and `src/aspen_dataset.rs`.
//

import CoreLocation
import Foundation
import MapLibre

// MARK: - Request wire types (POST body)

struct BulkFetchParamsV3: Encodable {
    let chateaus: [String: ChateauAskParamsV2]
    let categories: [String]
    let bounds_input: BoundsInputV3
}

struct ChateauAskParamsV2: Encodable {
    let category_params: CategoryAskParamsV2
}

struct CategoryAskParamsV2: Encodable {
    let bus: SubCategoryAskParamsV2?
    let metro: SubCategoryAskParamsV2?
    let rail: SubCategoryAskParamsV2?
    let other: SubCategoryAskParamsV2?
}

struct SubCategoryAskParamsV2: Encodable {
    let last_updated_time_ms: UInt64
    let prev_user_min_x: UInt32?
    let prev_user_max_x: UInt32?
    let prev_user_min_y: UInt32?
    let prev_user_max_y: UInt32?
}

struct BoundsInputV3: Encodable {
    let level5: BoundsInputPerLevel
    let level7: BoundsInputPerLevel
    let level8: BoundsInputPerLevel
    let level12: BoundsInputPerLevel
}

struct BoundsInputPerLevel: Encodable {
    let min_x: UInt32
    let max_x: UInt32
    let min_y: UInt32
    let max_y: UInt32
}

// MARK: - Response wire types

struct BulkFetchResponseV2: Decodable {
    let chateaus: [String: EachChateauResponseV2]
}

struct EachChateauResponseV2: Decodable {
    let categories: PositionDataCategoryV2?
}

struct PositionDataCategoryV2: Decodable {
    let metro: EachCategoryPayloadV2?
    let bus: EachCategoryPayloadV2?
    let rail: EachCategoryPayloadV2?
    let other: EachCategoryPayloadV2?
}

struct EachCategoryPayloadV2: Decodable {
    // Nested: x → y → vehicle_id → vehicle
    let vehicle_positions: [String: [String: [String: AspenisedVehiclePositionOutput]]]?
    let last_updated_time_ms: UInt64
    let replaces_all: Bool
    let z_level: UInt8
    let list_of_agency_ids: [String]?
}

struct AspenisedVehiclePositionOutput: Decodable {
    let trip: AspenisedVehicleTripInfoOutput?
    let vehicle: AspenisedVehicleDescriptor?
    let position: CatenaryRtVehiclePosition?
    let timestamp: UInt64?
    let route_type: Int16
    let current_stop_sequence: UInt32?
    let current_status: Int32?
    let congestion_level: Int32?
    let occupancy_status: Int32?
    let occupancy_percentage: UInt32?
}

struct AspenisedVehicleTripInfoOutput: Decodable {
    let trip_id: String?
    let trip_headsign: String?
    let route_id: String?
    let trip_short_name: String?
    let direction_id: UInt32?
    let start_time: String?
    let start_date: String?
    let schedule_relationship: UInt8?
    let delay: Int32?
}

struct AspenisedVehicleDescriptor: Decodable {
    let id: String?
    let label: String?
    let license_plate: String?
    let wheelchair_accessible: Int32?
}

struct CatenaryRtVehiclePosition: Decodable {
    let latitude: Float
    let longitude: Float
    let bearing: Float?
    let odometer: Double?
    let speed: Float?
}

// MARK: - Flattened, view-friendly vehicle

struct RealtimeVehicle: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let routeType: Int16
    let bearing: Double?
    let routeId: String?
    let headsign: String?
    let delay: Int32?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: RealtimeVehicle, r: RealtimeVehicle) -> Bool {
        l.id == r.id
            && l.coordinate.latitude == r.coordinate.latitude
            && l.coordinate.longitude == r.coordinate.longitude
            && l.routeType == r.routeType
    }
}

// MARK: - View model

@MainActor
final class RealtimeVehicles: ObservableObject {
    @Published private(set) var vehicles: [RealtimeVehicle] = []

    private var bounds: MLNCoordinateBounds?
    private var realtimeChateauIDs: [String] = []
    private let pollInterval: Duration = .seconds(2.5)

    private static let bulkFetchURL = URL(string: "https://birch.catenarymaps.org/bulk_realtime_fetch_v3")!
    private static let chateausURL = URL(string: "https://birch.catenarymaps.org/getchateaus")!

    func updateBounds(_ bounds: MLNCoordinateBounds) {
        self.bounds = bounds
    }

    /// Long-running polling loop. Call from `.task { await vm.run() }` so SwiftUI
    /// auto-cancels when the view leaves the hierarchy.
    func run() async {
        await loadChateaus()
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func loadChateaus() async {
        struct Geo: Decodable {
            let features: [Feature]
            struct Feature: Decodable { let properties: Props }
            struct Props: Decodable { let chateau: String; let realtime_feeds: [String] }
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.chateausURL)
            let geo = try JSONDecoder().decode(Geo.self, from: data)
            self.realtimeChateauIDs = geo.features
                .filter { !$0.properties.realtime_feeds.isEmpty && !$0.properties.chateau.isEmpty }
                .map { $0.properties.chateau }
        } catch {
            print("RealtimeVehicles: error fetching chateaus:", error)
        }
    }

    private func pollOnce() async {
        guard let bounds, !realtimeChateauIDs.isEmpty else { return }

        let empty = SubCategoryAskParamsV2(
            last_updated_time_ms: 0,
            prev_user_min_x: nil, prev_user_max_x: nil,
            prev_user_min_y: nil, prev_user_max_y: nil
        )
        let askParams = ChateauAskParamsV2(category_params: CategoryAskParamsV2(
            bus: empty, metro: empty, rail: empty, other: empty
        ))
        let chateausMap = Dictionary(uniqueKeysWithValues: realtimeChateauIDs.map { ($0, askParams) })

        let request = BulkFetchParamsV3(
            chateaus: chateausMap,
            categories: ["bus", "metro", "rail", "other"],
            bounds_input: BoundsInputV3(
                level5: Self.tileBoundsForLevel(bounds, zoom: 5),
                level7: Self.tileBoundsForLevel(bounds, zoom: 7),
                level8: Self.tileBoundsForLevel(bounds, zoom: 8),
                level12: Self.tileBoundsForLevel(bounds, zoom: 12)
            )
        )

        do {
            var req = URLRequest(url: Self.bulkFetchURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(request)
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(BulkFetchResponseV2.self, from: data)
            self.vehicles = Self.flatten(resp)
        } catch {
            print("RealtimeVehicles: error fetching vehicles:", error)
        }
    }

    private static func flatten(_ resp: BulkFetchResponseV2) -> [RealtimeVehicle] {
        var out: [RealtimeVehicle] = []
        for chateau in resp.chateaus.values {
            guard let cats = chateau.categories else { continue }
            for payload in [cats.metro, cats.bus, cats.rail, cats.other].compactMap({ $0 }) {
                guard let xs = payload.vehicle_positions else { continue }
                for ys in xs.values {
                    for vehicleMap in ys.values {
                        for (id, v) in vehicleMap {
                            guard let pos = v.position else { continue }
                            out.append(RealtimeVehicle(
                                id: id,
                                coordinate: CLLocationCoordinate2D(
                                    latitude: Double(pos.latitude),
                                    longitude: Double(pos.longitude)),
                                routeType: v.route_type,
                                bearing: pos.bearing.map(Double.init),
                                routeId: v.trip?.route_id,
                                headsign: v.trip?.trip_headsign,
                                delay: v.trip?.delay
                            ))
                        }
                    }
                }
            }
        }
        return out
    }

    /// Convert a lat/lon bounding box into a tile-coordinate rectangle for a given zoom.
    /// Uses the standard slippy-map tile math.
    private static func tileBoundsForLevel(_ bounds: MLNCoordinateBounds, zoom: Double) -> BoundsInputPerLevel {
        let n = pow(2.0, zoom)
        func latToTileY(_ lat: Double) -> Int {
            let clamped = max(-85.05112878, min(85.05112878, lat))
            let latRad = clamped * .pi / 180.0
            return Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
        }
        func lonToTileX(_ lon: Double) -> Int {
            Int(floor((lon + 180.0) / 360.0 * n))
        }
        let maxIdx = Int(n) - 1
        let minX = max(0, min(maxIdx, lonToTileX(bounds.sw.longitude)))
        let maxX = max(0, min(maxIdx, lonToTileX(bounds.ne.longitude)))
        // Latitude inverts: higher latitude → smaller tile Y.
        let minY = max(0, min(maxIdx, latToTileY(bounds.ne.latitude)))
        let maxY = max(0, min(maxIdx, latToTileY(bounds.sw.latitude)))
        return BoundsInputPerLevel(
            min_x: UInt32(minX),
            max_x: UInt32(maxX),
            min_y: UInt32(minY),
            max_y: UInt32(maxY)
        )
    }
}
