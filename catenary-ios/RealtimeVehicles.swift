//
//  RealtimeVehicles.swift
//  catenary-ios
//
//  Drives the Spruce WebSocket subscription and exposes a flattened,
//  observable list of vehicle positions for the map to render. Mirrors the
//  Android `FetchRealtimeData.kt`: on every viewport / zoom / toggle change
//  we compute the appropriate categories + chateaus + tile bounds and call
//  `SpruceWebSocket.updateMap`. Vehicle updates arrive pushed from the
//  server via `SpruceWebSocket.shared.$spruceMapData`.
//
//  Response wire types mirror `catenary-backend/src/birch/aspenised_data_over_https.rs`
//  and `src/aspen_dataset.rs`.
//

import Combine
import CoreLocation
import Foundation
import MapLibre

// MARK: - Tile-bounds wire type (shared with SpruceWebSocket.BoundsInput)

struct BoundsInputPerLevel: Encodable {
    let min_x: UInt32
    let max_x: UInt32
    let min_y: UInt32
    let max_y: UInt32
}

// MARK: - Response wire types (received via SpruceWebSocket `map_update`)

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
    private var currentZoom: Double = 5
    private var layerSettings = AllLayerSettings()
    private var realtimeChateaus: [ChateauInfo] = []

    /// Accumulator: chateau → category → vehicleID → vehicle.
    /// The Spruce server sends one `map_update` per (chateau, category) pair,
    /// and most are *incremental* (`replaces_all: false` carries only the
    /// changed tiles). We accumulate here and rebuild `vehicles` after every
    /// message so the map shows the full union, not just the last delta.
    private var byChateau: [String: [String: [String: RealtimeVehicle]]] = [:]

    /// Minimal info we keep about each realtime-enabled chateau so that
    /// `sendUpdateMap` can quickly filter to chateaus that intersect the viewport.
    private struct ChateauInfo {
        let id: String
        let bbox: MLNCoordinateBounds
    }

    /// Coalesces back-to-back context changes (a pan gesture fires
    /// `onMapViewProxyUpdate` ~60×/s) into a single WebSocket message.
    private var sendDebounceTask: Task<Void, Never>?
    private let sendDebounce: Duration = .milliseconds(50)

    /// Throttle for republishing `vehicles` to SwiftUI. The server can push
    /// ~30 per-chateau map_update messages in a burst on first subscribe;
    /// rebuilding `MLNShapeSource` for each one is wasteful. Publish at most
    /// every 250 ms instead.
    private var rebuildPublishTask: Task<Void, Never>?
    private var rebuildIsDirty = false
    private let rebuildThrottle: Duration = .milliseconds(250)

    private static let chateausURL = URL(string: "https://birch.catenarymaps.org/getchateaus")!

    func updateBounds(_ bounds: MLNCoordinateBounds) {
        self.bounds = bounds
        scheduleSend()
    }

    func updateZoom(_ zoom: Double) {
        self.currentZoom = zoom
        scheduleSend()
    }

    func updateLayerSettings(_ settings: AllLayerSettings) {
        self.layerSettings = settings
        scheduleSend()
    }

    /// Connect to Spruce, kick off the first subscription, and stream incoming
    /// `map_update` messages into `self.vehicles`. Call from
    /// `.task { await vm.run() }` so SwiftUI auto-cancels when the view leaves
    /// the hierarchy.
    func run() async {
        // Open the WebSocket eagerly so its TLS handshake runs in parallel
        // with the ~1.6 MB chateau-geometry fetch below.
        SpruceWebSocket.shared.initConnection()
        await loadChateaus()
        // Send the first update now that chateaus are loaded. If the WS isn't
        // open yet, SpruceWebSocket queues the message and replays it on connect.
        scheduleSend()

        // Observe spruceMapData pushes. Server sends one chateau per message
        // and most are incremental, so we accumulate.
        for await mapData in SpruceWebSocket.shared.$spruceMapData.values {
            if Task.isCancelled { break }
            if let mapData {
                apply(mapData)
            }
        }
    }

    /// Merge a `map_update` payload into `byChateau`, respecting `replaces_all`,
    /// then republish the flattened vehicle list.
    private func apply(_ resp: BulkRealtimeResponseV2) {
        var touched = 0
        for (chateauID, chateauResp) in resp.chateaus {
            guard let cats = chateauResp.categories else { continue }
            touched += applyCategory(chateauID, "metro", cats.metro)
            touched += applyCategory(chateauID, "bus",   cats.bus)
            touched += applyCategory(chateauID, "rail",  cats.rail)
            touched += applyCategory(chateauID, "other", cats.other)
        }
        rebuildVehicles()
        print("RealtimeVehicles: applied msg (touched=\(touched), total=\(vehicles.count))")
    }

    /// Apply one category's payload. Returns the number of vehicles ingested.
    private func applyCategory(_ chateauID: String, _ category: String, _ payload: EachCategoryPayloadV2?) -> Int {
        guard let payload else { return 0 }
        if payload.replaces_all {
            // Clear this (chateau, category) slot before merging new tiles.
            byChateau[chateauID, default: [:]][category] = [:]
        }
        guard let xs = payload.vehicle_positions else { return 0 }
        var added = 0
        for ys in xs.values {
            for vehicleMap in ys.values {
                for (id, v) in vehicleMap {
                    guard let pos = v.position else { continue }
                    byChateau[chateauID, default: [:]][category, default: [:]][id] = RealtimeVehicle(
                        id: id,
                        coordinate: CLLocationCoordinate2D(
                            latitude: Double(pos.latitude),
                            longitude: Double(pos.longitude)),
                        routeType: v.route_type,
                        bearing: pos.bearing.map(Double.init),
                        routeId: v.trip?.route_id,
                        headsign: v.trip?.trip_headsign,
                        delay: v.trip?.delay
                    )
                    added += 1
                }
            }
        }
        return added
    }

    /// Mark the accumulator dirty and schedule a single throttled publish.
    /// Multiple `apply()` calls inside one throttle window only result in one
    /// `MLNShapeSource.shape` rebuild.
    private func rebuildVehicles() {
        rebuildIsDirty = true
        if rebuildPublishTask == nil {
            rebuildPublishTask = Task { [weak self] in
                try? await Task.sleep(for: self?.rebuildThrottle ?? .milliseconds(250))
                self?.publishVehicles()
            }
        }
    }

    private func publishVehicles() {
        rebuildPublishTask = nil
        guard rebuildIsDirty else { return }
        rebuildIsDirty = false
        var out: [RealtimeVehicle] = []
        for chateauMap in byChateau.values {
            for catMap in chateauMap.values {
                out.append(contentsOf: catMap.values)
            }
        }
        self.vehicles = out
    }

    private func loadChateaus() async {
        struct Geo: Decodable {
            let features: [Feature]
            struct Feature: Decodable {
                let geometry: Geometry?
                let properties: Props
            }
            struct Geometry: Decodable {
                // Decode coordinates as a generic JSONValue tree so we handle
                // both `Polygon` ([[[lon,lat]]]) and `MultiPolygon`
                // ([[[[lon,lat]]]]) without separate decoders.
                let coordinates: JSONValue
            }
            struct Props: Decodable {
                let chateau: String
                let realtime_feeds: [String]
            }
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.chateausURL)
            let geo = try JSONDecoder().decode(Geo.self, from: data)
            self.realtimeChateaus = geo.features.compactMap { f in
                guard !f.properties.realtime_feeds.isEmpty,
                      !f.properties.chateau.isEmpty,
                      let geom = f.geometry else { return nil }
                var minLon = Double.infinity, maxLon = -Double.infinity
                var minLat = Double.infinity, maxLat = -Double.infinity
                Self.walkCoords(geom.coordinates,
                                minLon: &minLon, maxLon: &maxLon,
                                minLat: &minLat, maxLat: &maxLat)
                guard minLon.isFinite, maxLon.isFinite, minLat.isFinite, maxLat.isFinite else {
                    return nil
                }
                return ChateauInfo(
                    id: f.properties.chateau,
                    bbox: MLNCoordinateBounds(
                        sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                        ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
                )
            }
            print("RealtimeVehicles: loaded \(realtimeChateaus.count) chateaus with realtime + geometry")
        } catch {
            print("RealtimeVehicles: error fetching chateaus:", error)
        }
    }

    /// Recursively walk a GeoJSON coordinates tree and update the running bbox
    /// for any `[lon, lat]` pair encountered. Works for any geometry depth.
    private static func walkCoords(_ value: JSONValue,
                                   minLon: inout Double, maxLon: inout Double,
                                   minLat: inout Double, maxLat: inout Double) {
        if case .array(let arr) = value, arr.count == 2,
           case .number(let lon) = arr[0], case .number(let lat) = arr[1] {
            if lon < minLon { minLon = lon }
            if lon > maxLon { maxLon = lon }
            if lat < minLat { minLat = lat }
            if lat > maxLat { maxLat = lat }
            return
        }
        if case .array(let arr) = value {
            for item in arr {
                walkCoords(item, minLon: &minLon, maxLon: &maxLon, minLat: &minLat, maxLat: &maxLat)
            }
        }
    }

    /// AABB intersection test, ignoring antimeridian wrap.
    private static func boundsIntersect(_ a: MLNCoordinateBounds, _ b: MLNCoordinateBounds) -> Bool {
        a.ne.longitude >= b.sw.longitude && a.sw.longitude <= b.ne.longitude
            && a.ne.latitude >= b.sw.latitude && a.sw.latitude <= b.ne.latitude
    }

    /// Coalesce rapid setter calls into a single WebSocket message.
    private func scheduleSend() {
        sendDebounceTask?.cancel()
        sendDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.sendDebounce ?? .milliseconds(150))
            if Task.isCancelled { return }
            await self?.sendUpdateMap()
        }
    }

    /// Build the viewport subscription parameters from current state and
    /// send an `update_map` over the WebSocket. Mirrors Android's
    /// `FetchRealtimeData.sendMapUpdate`.
    private func sendUpdateMap() async {
        guard let bounds, !realtimeChateaus.isEmpty else { return }

        // Zoom-based category filter + toggle gate
        //   - bus only at zoom >= 8 (massive volume otherwise)
        //   - rail at zoom >= 3
        //   - metro at zoom >= 4
        //   - other at zoom >= 3
        var categories: [String] = []
        if layerSettings.bus.visiblerealtimedots          && currentZoom >= 8 { categories.append("bus") }
        if layerSettings.intercityrail.visiblerealtimedots && currentZoom >= 3 { categories.append("rail") }
        if layerSettings.localrail.visiblerealtimedots    && currentZoom >= 4 { categories.append("metro") }
        if layerSettings.other.visiblerealtimedots        && currentZoom >= 3 { categories.append("other") }
        guard !categories.isEmpty else {
            if !self.vehicles.isEmpty { self.vehicles = [] }
            return
        }

        // Filter to chateaus whose bbox overlaps the visible viewport.
        let visibleChateauIDs = realtimeChateaus
            .filter { Self.boundsIntersect($0.bbox, bounds) }
            .map { $0.id }
        guard !visibleChateauIDs.isEmpty else {
            if !self.vehicles.isEmpty { self.vehicles = [] }
            return
        }

        // Tile-bounds padding to avoid edge clipping when zoomed out
        // (same heuristic as the Android client).
        let zoom = currentZoom
        let padFor: (Double) -> Int = { tileZoom in
            if tileZoom == 12 { return zoom > 11 ? 0 : 1 }
            return zoom > 9 ? 0 : 1
        }

        let boundsInput = BoundsInput(
            level5: Self.tileBoundsForLevel(bounds, zoom: 5, padding: padFor(5)),
            level7: Self.tileBoundsForLevel(bounds, zoom: 7, padding: padFor(7)),
            level8: Self.tileBoundsForLevel(bounds, zoom: 8, padding: padFor(8)),
            level12: Self.tileBoundsForLevel(bounds, zoom: 12, padding: padFor(12))
        )

        // Drop accumulator entries for chateaus no longer in the subscription,
        // so old ghosts don't linger after the user pans away.
        let visibleSet = Set(visibleChateauIDs)
        let beforeKeys = byChateau.keys.count
        byChateau = byChateau.filter { visibleSet.contains($0.key) }
        if byChateau.keys.count != beforeKeys { rebuildVehicles() }

        print("RealtimeVehicles: ws update chateaus=\(visibleChateauIDs.count)/\(realtimeChateaus.count) cats=\(categories) zoom=\(String(format: "%.1f", currentZoom))")

        SpruceWebSocket.shared.updateMap(
            categories: categories,
            chateaus: visibleChateauIDs,
            boundsInput: boundsInput
        )
    }

    /// Convert a lat/lon bounding box into a tile-coordinate rectangle for a given zoom.
    /// Uses the standard slippy-map tile math. `padding` extends the rectangle outward
    /// by N tiles in each direction so vehicles just outside the visible viewport
    /// still get fetched (used when zoomed out).
    private static func tileBoundsForLevel(_ bounds: MLNCoordinateBounds, zoom: Double, padding: Int = 0) -> BoundsInputPerLevel {
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
        let minX = max(0, min(maxIdx, lonToTileX(bounds.sw.longitude) - padding))
        let maxX = max(0, min(maxIdx, lonToTileX(bounds.ne.longitude) + padding))
        // Latitude inverts: higher latitude → smaller tile Y.
        let minY = max(0, min(maxIdx, latToTileY(bounds.ne.latitude) - padding))
        let maxY = max(0, min(maxIdx, latToTileY(bounds.sw.latitude) + padding))
        return BoundsInputPerLevel(
            min_x: UInt32(minX),
            max_x: UInt32(maxX),
            min_y: UInt32(minY),
            max_y: UInt32(maxY)
        )
    }
}
