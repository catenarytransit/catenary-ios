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

struct BoundsInputPerLevel: Encodable, Equatable {
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
    let chateauID: String
    let coordinate: CLLocationCoordinate2D
    let routeType: Int16
    let bearing: Double?
    let vehicleID: String?
    let vehicleLabel: String?
    let tripID: String?
    let routeId: String?
    let headsign: String?
    let tripShortName: String?
    let startTime: String?
    let startDate: String?
    let delay: Int32?
    let speedMetresPerSecond: Double?
    let occupancyStatus: Int32?
    let color: String
    let textColor: String
    let routeShortName: String?
    let routeLongName: String?

    func applying(route: RouteCacheEntry?) -> RealtimeVehicle {
        guard let route else { return self }
        return RealtimeVehicle(
            id: id,
            chateauID: chateauID,
            coordinate: coordinate,
            routeType: routeType,
            bearing: bearing,
            vehicleID: vehicleID,
            vehicleLabel: vehicleLabel,
            tripID: tripID,
            routeId: routeId,
            headsign: headsign,
            tripShortName: tripShortName,
            startTime: startTime,
            startDate: startDate,
            delay: delay,
            speedMetresPerSecond: speedMetresPerSecond,
            occupancyStatus: occupancyStatus,
            color: route.color,
            textColor: route.text_color,
            routeShortName: route.short_name,
            routeLongName: route.long_name
        )
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: RealtimeVehicle, r: RealtimeVehicle) -> Bool {
        l.id == r.id
            && l.coordinate.latitude == r.coordinate.latitude
            && l.coordinate.longitude == r.coordinate.longitude
            && l.routeType == r.routeType
            && l.bearing == r.bearing
            && l.vehicleID == r.vehicleID
            && l.vehicleLabel == r.vehicleLabel
            && l.tripID == r.tripID
            && l.routeId == r.routeId
            && l.headsign == r.headsign
            && l.tripShortName == r.tripShortName
            && l.startTime == r.startTime
            && l.startDate == r.startDate
            && l.delay == r.delay
            && l.speedMetresPerSecond == r.speedMetresPerSecond
            && l.occupancyStatus == r.occupancyStatus
            && l.color == r.color
            && l.textColor == r.textColor
            && l.routeShortName == r.routeShortName
            && l.routeLongName == r.routeLongName
    }
}

// MARK: - View model

@MainActor
final class RealtimeVehicles: ObservableObject {
    private(set) var vehicles: [RealtimeVehicle] = []
    var onVehiclesChanged: (([RealtimeVehicle]) -> Void)?

    private var bounds: MLNCoordinateBounds?
    private var currentZoom: Double = 5
    private var layerSettings = AllLayerSettings()
    private var activeSubscription: MapSubscription?

    private var routesByChateau: [String: [String: RouteCacheEntry]] = [:]
    private var knownRouteAgencies: [String: Set<String>] = [:]
    private var routeFetchesInFlight: Set<String> = []
    private var fetchedAllRoutesForChateau: Set<String> = []

    private struct AgencyFilterRequest: Encodable {
        let agency_filter: [String]?
        let chateau: String
    }

    /// Accumulator: chateau → category → vehicleID → vehicle.
    /// The Spruce server sends one `map_update` per (chateau, category) pair,
    /// and most are *incremental* (`replaces_all: false` carries only the
    /// changed tiles). We accumulate here and rebuild `vehicles` after every
    /// message so the map shows the full union, not just the last delta.
    private var byChateau: [String: [String: [String: RealtimeVehicle]]] = [:]
    private var lastUpdatedByChateau: [String: [String: UInt64]] = [:]

    private struct MapSubscription: Equatable {
        let categories: [String]
        let boundsInput: BoundsInput
    }

    /// Coalesce rapid camera changes. Trajectory subscriptions use a shorter
    /// debounce so Spruce sees their new request before the map subscription
    /// changes the server-side chateau set.
    private var sendDebounceTask: Task<Void, Never>?
    private let sendDebounce: Duration = .milliseconds(250)

    /// Throttle for republishing `vehicles` to SwiftUI. The server can push
    /// ~30 per-chateau map_update messages in a burst on first subscribe;
    /// rebuilding `MLNShapeSource` for each one is wasteful. Publish at most
    /// every 250 ms instead.
    private var rebuildPublishTask: Task<Void, Never>?
    private var rebuildIsDirty = false
    private let rebuildThrottle: Duration = .milliseconds(250)

    func updateViewport(bounds: MLNCoordinateBounds, zoom: Double) {
        self.bounds = bounds
        currentZoom = zoom
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
        defer { stop() }
        SpruceWebSocket.shared.initConnection()
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

    func stop() {
        sendDebounceTask?.cancel()
        sendDebounceTask = nil
        rebuildPublishTask?.cancel()
        rebuildPublishTask = nil
        activeSubscription = nil
        SpruceWebSocket.shared.unsubscribeMap()
        clearVehicles()
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
        guard let payload,
              let activeSubscription,
              activeSubscription.categories.contains(category),
              payload.z_level == Self.zoomLevel(for: category) else { return 0 }

        if let previousTimestamp = lastUpdatedByChateau[chateauID]?[category],
           payload.last_updated_time_ms < previousTimestamp {
            return 0
        }
        lastUpdatedByChateau[chateauID, default: [:]][category] = payload.last_updated_time_ms

        // A response built for an older fast-pan viewport can still arrive after
        // the latest subscribe_map_v2. Never let its out-of-bounds tile set wipe
        // the currently displayed snapshot.
        let replacementMatchesActiveBounds = payload.vehicle_positions?.allSatisfy { xKey, yMap in
            guard let x = UInt32(xKey) else { return false }
            return yMap.keys.allSatisfy { yKey in
                guard let y = UInt32(yKey) else { return false }
                return Self.containsTile(
                    x: x,
                    y: y,
                    category: category,
                    boundsInput: activeSubscription.boundsInput
                )
            }
        } ?? true

        if payload.replaces_all && replacementMatchesActiveBounds {
            byChateau[chateauID, default: [:]][category] = [:]
        }

        guard let xs = payload.vehicle_positions else { return 0 }
        var added = 0
        var hasMissingRoutes = false
        for (xKey, ys) in xs {
            guard let x = UInt32(xKey) else { continue }
            for (yKey, vehicleMap) in ys {
                guard let y = UInt32(yKey),
                      Self.containsTile(
                        x: x,
                        y: y,
                        category: category,
                        boundsInput: activeSubscription.boundsInput
                      ) else { continue }

                for (id, v) in vehicleMap {
                    guard let pos = v.position else { continue }
                    if let routeID = v.trip?.route_id,
                       routesByChateau[chateauID]?[routeID] == nil {
                        hasMissingRoutes = true
                    }
                    byChateau[chateauID, default: [:]][category, default: [:]][id] = RealtimeVehicle(
                        id: "\(chateauID)|\(id)",
                        chateauID: chateauID,
                        coordinate: CLLocationCoordinate2D(
                            latitude: Double(pos.latitude),
                            longitude: Double(pos.longitude)),
                        routeType: v.route_type,
                        bearing: pos.bearing.map(Double.init),
                        vehicleID: v.vehicle?.id ?? id,
                        vehicleLabel: v.vehicle?.label,
                        tripID: v.trip?.trip_id,
                        routeId: v.trip?.route_id,
                        headsign: v.trip?.trip_headsign,
                        tripShortName: v.trip?.trip_short_name,
                        startTime: v.trip?.start_time,
                        startDate: v.trip?.start_date,
                        delay: v.trip?.delay,
                        speedMetresPerSecond: pos.speed.map(Double.init),
                        occupancyStatus: v.occupancy_status,
                        color: "AAAAAA",
                        textColor: "000000",
                        routeShortName: nil,
                        routeLongName: nil
                    )
                    added += 1
                }
            }
        }
        if hasMissingRoutes {
            requestRoutes(for: chateauID, agencyIDs: payload.list_of_agency_ids ?? [])
        }
        return added
    }

    private func requestRoutes(for chateauID: String, agencyIDs: [String]) {
        let suppliedAgencies = Set(agencyIDs)
        let newAgencies = suppliedAgencies.subtracting(knownRouteAgencies[chateauID] ?? [])
        let fetchAll = suppliedAgencies.isEmpty

        if fetchAll {
            guard !fetchedAllRoutesForChateau.contains(chateauID) else { return }
        } else {
            guard !newAgencies.isEmpty else { return }
        }

        let requestAgencies = fetchAll ? [] : newAgencies.sorted()
        let requestKey = "\(chateauID)|\(requestAgencies.joined(separator: ","))"
        guard routeFetchesInFlight.insert(requestKey).inserted else { return }

        Task { [weak self] in
            await self?.fetchRoutes(
                for: chateauID,
                agencyIDs: requestAgencies,
                fetchAll: fetchAll,
                requestKey: requestKey
            )
        }
    }

    private func fetchRoutes(
        for chateauID: String,
        agencyIDs: [String],
        fetchAll: Bool,
        requestKey: String
    ) async {
        defer { routeFetchesInFlight.remove(requestKey) }
        guard let url = URL(string: "https://birch.catenarymaps.org/getroutesofchateauwithagencyv2") else {
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AgencyFilterRequest(
                agency_filter: fetchAll ? nil : agencyIDs,
                chateau: chateauID
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return
            }

            let routes = try JSONDecoder().decode([RouteCacheEntry].self, from: data)
            var chateauRoutes = routesByChateau[chateauID] ?? [:]
            for route in routes {
                chateauRoutes[route.route_id] = route
            }
            routesByChateau[chateauID] = chateauRoutes

            if fetchAll {
                fetchedAllRoutesForChateau.insert(chateauID)
            } else {
                knownRouteAgencies[chateauID, default: []].formUnion(agencyIDs)
            }
            rebuildVehicles()
        } catch {
            print("RealtimeVehicles: route metadata fetch failed for \(chateauID): \(error)")
        }
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
        if let activeSubscription {
            let requestedCategories = Set(activeSubscription.categories)
            for chateauMap in byChateau.values {
                for (category, catMap) in chateauMap
                where requestedCategories.contains(category) {
                    for vehicle in catMap.values
                    where Self.isInsideActiveBounds(
                        vehicle.coordinate,
                        category: category,
                        boundsInput: activeSubscription.boundsInput
                    ) {
                        let route = vehicle.routeId.flatMap {
                            routesByChateau[vehicle.chateauID]?[$0]
                        }
                        out.append(vehicle.applying(route: route))
                    }
                }
            }
        }
        out.sort { $0.id < $1.id }
        guard out != vehicles else { return }
        vehicles = out
        onVehiclesChanged?(out)
    }

    /// Coalesce rapid setter calls into a single WebSocket message.
    private func scheduleSend() {
        sendDebounceTask?.cancel()
        sendDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.sendDebounce ?? .milliseconds(250))
            if Task.isCancelled { return }
            await self?.sendUpdateMap()
        }
    }

    /// Build the viewport subscription parameters from current state and
    /// send an `update_map` over the WebSocket. Mirrors Android's
    /// `FetchRealtimeData.sendMapUpdate`.
    private func sendUpdateMap() async {
        guard let bounds else { return }

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
            activeSubscription = nil
            SpruceWebSocket.shared.unsubscribeMap()
            clearVehicles()
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

        let subscription = MapSubscription(
            categories: categories,
            boundsInput: boundsInput
        )
        guard subscription != activeSubscription else { return }
        activeSubscription = subscription

        // Spruce sends only newly entered tiles for ordinary viewport changes.
        // Keep the completed overlap visible until the replacement arrives;
        // publishVehicles() filters the cache against these latest bounds.
        discardInactiveCategories(keeping: Set(categories))
        rebuildVehicles()

        SpruceWebSocket.shared.updateMap(
            categories: categories,
            boundsInput: boundsInput
        )
    }

    private func discardInactiveCategories(keeping categories: Set<String>) {
        for chateauID in Array(byChateau.keys) {
            guard var categoryMap = byChateau[chateauID] else { continue }
            categoryMap = categoryMap.filter { categories.contains($0.key) }
            if categoryMap.isEmpty {
                byChateau.removeValue(forKey: chateauID)
            } else {
                byChateau[chateauID] = categoryMap
            }
        }

        for chateauID in Array(lastUpdatedByChateau.keys) {
            guard var categoryMap = lastUpdatedByChateau[chateauID] else { continue }
            categoryMap = categoryMap.filter { categories.contains($0.key) }
            if categoryMap.isEmpty {
                lastUpdatedByChateau.removeValue(forKey: chateauID)
            } else {
                lastUpdatedByChateau[chateauID] = categoryMap
            }
        }
    }

    private func clearVehicles() {
        byChateau.removeAll(keepingCapacity: true)
        lastUpdatedByChateau.removeAll(keepingCapacity: true)
        rebuildIsDirty = false
        guard !vehicles.isEmpty else { return }
        vehicles = []
        onVehiclesChanged?([])
    }

    private static func zoomLevel(for category: String) -> UInt8 {
        switch category {
        case "bus": return 12
        case "metro": return 8
        case "rail": return 7
        case "other": return 5
        default: return 0
        }
    }

    private static func bounds(
        for category: String,
        in boundsInput: BoundsInput
    ) -> BoundsInputPerLevel? {
        switch category {
        case "bus": return boundsInput.level12
        case "metro": return boundsInput.level8
        case "rail": return boundsInput.level7
        case "other": return boundsInput.level5
        default: return nil
        }
    }

    private static func containsTile(
        x: UInt32,
        y: UInt32,
        category: String,
        boundsInput: BoundsInput
    ) -> Bool {
        guard let bounds = bounds(for: category, in: boundsInput) else { return false }
        return x >= bounds.min_x
            && x <= bounds.max_x
            && y >= bounds.min_y
            && y <= bounds.max_y
    }

    private static func isInsideActiveBounds(
        _ coordinate: CLLocationCoordinate2D,
        category: String,
        boundsInput: BoundsInput
    ) -> Bool {
        let zoom = Int(zoomLevel(for: category))
        guard zoom > 0,
              let tile = tileCoordinate(for: coordinate, zoom: zoom) else { return false }
        return containsTile(
            x: tile.x,
            y: tile.y,
            category: category,
            boundsInput: boundsInput
        )
    }

    private static func tileCoordinate(
        for coordinate: CLLocationCoordinate2D,
        zoom: Int
    ) -> (x: UInt32, y: UInt32)? {
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else { return nil }

        let n = pow(2.0, Double(zoom))
        let maxIndex = Int(n) - 1
        let longitude = max(-180.0, min(179.999999999, coordinate.longitude))
        let latitude = max(-85.05112878, min(85.05112878, coordinate.latitude))
        let latitudeRadians = latitude * .pi / 180.0
        let x = Int(floor((longitude + 180.0) / 360.0 * n))
        let y = Int(floor(
            (1.0 - log(tan(latitudeRadians) + 1.0 / cos(latitudeRadians)) / .pi)
                / 2.0 * n
        ))

        return (
            x: UInt32(max(0, min(maxIndex, x))),
            y: UInt32(max(0, min(maxIndex, y)))
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
