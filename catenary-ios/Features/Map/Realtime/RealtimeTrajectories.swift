//
//  RealtimeTrajectories.swift
//  catenary-ios
//
//  Receives chunked Spruce trajectory buffers and interpolates synthetic
//  vehicle positions along each active trip. Networking stays in
//  SpruceWebSocket; this type owns map-facing state and lifecycle only.
//

import Combine
import CoreLocation
import Foundation
import MapLibre

// MARK: - Spruce trajectory wire models

struct TrajectoryBuffer {
    let timestamp: UInt64
    let clientReference: String
    let chateau: String
    let content: [TrajectoryWrapper]
    let chunkIndex: Int
    let totalChunks: Int
}

struct TrajectoryWrapper: Decodable {
    let source: String?
    let timestamp: UInt64?
    let client_reference: String?
    let content: TrajectoryItem
}

struct TrajectoryItem: Decodable {
    let trip_id: String?
    let unique_trip_id: String?
    let display_name: String?
    let color: String?
    let route_type: Int?
    let mode: String?
    let chateau_id: String?
    let trip_short_name: String?
    let route_short_name: String?
    let route_long_name: String?
    let route_id: String?
    let text_color: String?
    let start_time: String?
    let start_date: String?
    let stops: [TrajectoryStop]?
    let segments: [TrajectorySegment]?
}

struct TrajectoryStop: Decodable {
    let name: String?
    let departure: String?
    let arrival: String?
}

struct TrajectorySegment: Decodable {
    let coordinates: [[Double]]?
}

// MARK: - Map-facing model

struct RealtimeTrajectoryVehicle: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let routeType: Int
    let bearing: Double
    let chateauID: String
    let tripID: String?
    let routeID: String?
    let displayName: String?
    let headsign: String
    let tripShortName: String?
    let routeShortName: String?
    let routeLongName: String?
    let color: String?
    let textColor: String?
    let startDate: String?
    let startTime: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.bearing == rhs.bearing
    }
}

// MARK: - Store

@MainActor
final class RealtimeTrajectories: ObservableObject {
    @Published private(set) var vehicles: [RealtimeTrajectoryVehicle] = []

    private struct Subscription: Equatable {
        let bbox: [Double]
        let zoom: Int
        let modes: [String]
    }

    private struct ChunkAccumulator {
        let timestamp: UInt64
        var totalChunks: Int
        var chunks: [Int: [TrajectoryWrapper]]
    }

    private struct PreparedTrajectory {
        let id: String
        let departure: Date
        let arrival: Date
        let coordinates: [CLLocationCoordinate2D]
        let routeType: Int
        let chateauID: String
        let tripID: String?
        let routeID: String?
        let displayName: String?
        let headsign: String
        let tripShortName: String?
        let routeShortName: String?
        let routeLongName: String?
        let color: String?
        let textColor: String?
        let startDate: String?
        let startTime: String?
    }

    private var bounds: MLNCoordinateBounds?
    private var currentZoom: Double = 5
    private var layerSettings = AllLayerSettings()

    private var activeSubscription: Subscription?
    private var subscriptionTask: Task<Void, Never>?
    private var subscriptionRefreshTask: Task<Void, Never>?
    private var interpolationTask: Task<Void, Never>?
    private var cameraIdleTask: Task<Void, Never>?
    private var bufferCancellable: AnyCancellable?
    private var isRunning = false
    private var isCameraMoving = false

    private var accumulators: [String: ChunkAccumulator] = [:]
    private var trajectoriesByChateau: [String: [PreparedTrajectory]] = [:]
    private var latestSnapshotTimestampByChateau: [String: UInt64] = [:]

    private let subscriptionDebounce: Duration = .milliseconds(175)
    private let subscriptionRefreshInterval: Duration = .seconds(15)
    private let cameraIdleDelay: Duration = .milliseconds(250)
    private static let clientReference = "trajectories_layer"

    func updateBounds(_ bounds: MLNCoordinateBounds) {
        self.bounds = bounds
        markCameraMoving()
        scheduleSubscription()
    }

    func updateZoom(_ zoom: Double) {
        currentZoom = zoom
        scheduleSubscription()
    }

    func updateLayerSettings(_ settings: AllLayerSettings) {
        layerSettings = settings
        scheduleSubscription()
    }

    private func markCameraMoving() {
        isCameraMoving = true
        cameraIdleTask?.cancel()
        cameraIdleTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: cameraIdleDelay)
            if Task.isCancelled { return }
            isCameraMoving = false
        }
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        SpruceWebSocket.shared.initConnection()

        bufferCancellable = SpruceWebSocket.shared.trajectoryMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.apply(message)
            }

        interpolationTask = Task { [weak self] in
            await self?.interpolationLoop()
        }
        subscriptionRefreshTask = Task { [weak self] in
            await self?.subscriptionRefreshLoop()
        }
        scheduleSubscription()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
        }
        stop()
    }

    func stop() {
        guard isRunning || activeSubscription != nil || !vehicles.isEmpty else { return }
        isRunning = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        subscriptionRefreshTask?.cancel()
        subscriptionRefreshTask = nil
        interpolationTask?.cancel()
        interpolationTask = nil
        cameraIdleTask?.cancel()
        cameraIdleTask = nil
        isCameraMoving = false
        bufferCancellable?.cancel()
        bufferCancellable = nil
        activeSubscription = nil
        SpruceWebSocket.shared.unsubscribeTrajectories()
        clear()
    }

    private func scheduleSubscription() {
        guard isRunning else { return }
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: subscriptionDebounce)
            if Task.isCancelled { return }
            sendSubscription()
        }
    }

    private func subscriptionRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: subscriptionRefreshInterval)
            if Task.isCancelled { return }
            sendSubscription(forceRefresh: true)
        }
    }

    private func sendSubscription(forceRefresh: Bool = false) {
        guard isRunning else { return }
        guard let bounds else { return }

        var modes: [String] = []
        if layerSettings.bus.visiblerealtimedots && currentZoom >= 9 {
            modes += ["bus", "trolleybus"]
        }
        if layerSettings.intercityrail.visiblerealtimedots && currentZoom >= 3 {
            modes.append("rail")
        }
        if layerSettings.localrail.visiblerealtimedots && currentZoom >= 4 {
            modes += ["tram", "subway", "metro", "funicular"]
        }
        if layerSettings.other.visiblerealtimedots && currentZoom >= 3 {
            modes += ["ferry", "cable_car", "gondola", "monorail"]
        }

        guard !modes.isEmpty else {
            if activeSubscription != nil {
                activeSubscription = nil
                SpruceWebSocket.shared.unsubscribeTrajectories()
            }
            clear()
            return
        }

        let bbox = [
            bounds.sw.longitude,
            bounds.sw.latitude,
            bounds.ne.longitude,
            bounds.ne.latitude
        ]
        let subscription = Subscription(
            bbox: bbox,
            zoom: max(0, min(255, Int(currentZoom.rounded(.down)))),
            modes: modes
        )
        guard forceRefresh || subscription != activeSubscription else { return }

        activeSubscription = subscription
        // Keep the previous completed snapshot visible until each chateau's new
        // chunk set is complete. This prevents dots from disappearing while the
        // user pans or zooms, matching the Compose trajectory manager.
        SpruceWebSocket.shared.subscribeTrajectories(
            bbox: subscription.bbox,
            zoom: subscription.zoom,
            modes: subscription.modes,
            clientReference: Self.clientReference
        )
    }

    private func apply(_ message: TrajectoryBuffer) {
        guard message.clientReference == Self.clientReference else { return }

        // A delayed chunk from an older subscription must never replace a newer,
        // already-published snapshot for the same chateau.
        if let latestTimestamp = latestSnapshotTimestampByChateau[message.chateau],
           message.timestamp < latestTimestamp {
            return
        }

        // Spruce uses total_chunks == 0 for an unchunked/empty snapshot. Treat
        // its content as the complete replacement rather than always deleting
        // the chateau; this mirrors the Compose implementation.
        if message.totalChunks == 0 {
            accumulators.removeValue(forKey: message.chateau)
            let trajectories = message.content.compactMap {
                Self.prepare($0.content, fallbackChateau: message.chateau)
            }
            latestSnapshotTimestampByChateau[message.chateau] = message.timestamp
            if trajectories.isEmpty {
                trajectoriesByChateau.removeValue(forKey: message.chateau)
            } else {
                trajectoriesByChateau[message.chateau] = trajectories
            }
            publishCurrentPositions()
            return
        }

        guard message.chunkIndex >= 0,
              message.chunkIndex < message.totalChunks else {
            return
        }

        var accumulator: ChunkAccumulator
        if let existing = accumulators[message.chateau] {
            if existing.timestamp > message.timestamp {
                return
            }

            if existing.timestamp == message.timestamp,
               existing.totalChunks == message.totalChunks {
                accumulator = existing
            } else {
                accumulator = ChunkAccumulator(
                    timestamp: message.timestamp,
                    totalChunks: message.totalChunks,
                    chunks: [:]
                )
            }
        } else {
            accumulator = ChunkAccumulator(
                timestamp: message.timestamp,
                totalChunks: message.totalChunks,
                chunks: [:]
            )
        }

        accumulator.chunks[message.chunkIndex] = message.content
        accumulators[message.chateau] = accumulator

        let expectedChunks = 0..<accumulator.totalChunks
        guard expectedChunks.allSatisfy({ accumulator.chunks[$0] != nil }) else { return }

        let wrappers = expectedChunks.flatMap { accumulator.chunks[$0] ?? [] }
        let trajectories = wrappers.compactMap {
            Self.prepare($0.content, fallbackChateau: message.chateau)
        }
        latestSnapshotTimestampByChateau[message.chateau] = message.timestamp
        if trajectories.isEmpty {
            trajectoriesByChateau.removeValue(forKey: message.chateau)
        } else {
            trajectoriesByChateau[message.chateau] = trajectories
        }
        accumulators.removeValue(forKey: message.chateau)
        publishCurrentPositions()
    }

    private func interpolationLoop() async {
        while !Task.isCancelled {
            let interval: Duration
            if currentZoom < 7 {
                interval = .seconds(2)
            } else if isCameraMoving {
                interval = .seconds(1)
            } else if currentZoom > 12 {
                interval = .milliseconds(200)
            } else {
                interval = .milliseconds(300)
            }
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            publishCurrentPositions()
        }
    }

    private func publishCurrentPositions(now: Date = Date()) {
        var output: [RealtimeTrajectoryVehicle] = []

        for trajectories in trajectoriesByChateau.values {
            for trajectory in trajectories {
                let start = trajectory.departure.addingTimeInterval(-30)
                let end = trajectory.arrival.addingTimeInterval(30)
                guard now >= start, now <= end else { continue }

                let duration = trajectory.arrival.timeIntervalSince(trajectory.departure)
                guard duration > 0 else { continue }
                let progress = max(0, min(1, now.timeIntervalSince(trajectory.departure) / duration))
                guard let interpolated = Self.interpolate(trajectory.coordinates, progress: progress) else {
                    continue
                }

                output.append(RealtimeTrajectoryVehicle(
                    id: "trajectory_\(trajectory.id)",
                    coordinate: interpolated.coordinate,
                    routeType: trajectory.routeType,
                    bearing: interpolated.bearing,
                    chateauID: trajectory.chateauID,
                    tripID: trajectory.tripID,
                    routeID: trajectory.routeID,
                    displayName: trajectory.displayName,
                    headsign: trajectory.headsign,
                    tripShortName: trajectory.tripShortName,
                    routeShortName: trajectory.routeShortName,
                    routeLongName: trajectory.routeLongName,
                    color: trajectory.color,
                    textColor: trajectory.textColor,
                    startDate: trajectory.startDate,
                    startTime: trajectory.startTime
                ))
            }
        }

        if output != vehicles {
            vehicles = output
        }
    }

    private func clear() {
        accumulators.removeAll(keepingCapacity: true)
        trajectoriesByChateau.removeAll(keepingCapacity: true)
        latestSnapshotTimestampByChateau.removeAll(keepingCapacity: true)
        if !vehicles.isEmpty { vehicles = [] }
    }

    private static func prepare(_ item: TrajectoryItem, fallbackChateau: String) -> PreparedTrajectory? {
        let identifier = item.unique_trip_id ?? item.trip_id
        guard let identifier, !identifier.isEmpty,
              let stops = item.stops, let first = stops.first, let last = stops.last,
              let departure = parseDate(first.departure ?? first.arrival),
              let arrival = parseDate(last.arrival ?? last.departure),
              arrival > departure
        else { return nil }

        var coordinates: [CLLocationCoordinate2D] = []
        for segment in item.segments ?? [] {
            for pair in segment.coordinates ?? [] where pair.count >= 2 {
                let coordinate = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                if coordinates.last?.latitude != coordinate.latitude
                    || coordinates.last?.longitude != coordinate.longitude {
                    coordinates.append(coordinate)
                }
            }
        }
        guard !coordinates.isEmpty else { return nil }

        return PreparedTrajectory(
            id: identifier,
            departure: departure,
            arrival: arrival,
            coordinates: coordinates,
            routeType: item.route_type ?? routeType(for: item.mode),
            chateauID: item.chateau_id ?? fallbackChateau,
            tripID: item.trip_id,
            routeID: item.route_id,
            displayName: item.display_name,
            headsign: stops.last?.name ?? "",
            tripShortName: item.trip_short_name,
            routeShortName: item.route_short_name,
            routeLongName: item.route_long_name,
            color: item.color,
            textColor: item.text_color,
            startDate: item.start_date,
            startTime: item.start_time
        )
    }

    private static func routeType(for mode: String?) -> Int {
        switch mode {
        case "tram", "cable_car", "funicular": return 0
        case "subway", "metro": return 1
        case "rail": return 2
        case "bus", "trolleybus": return 3
        case "ferry": return 4
        default: return 3
        }
    }

    private static let iso8601 = ISO8601DateFormatter()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return iso8601.date(from: value) ?? iso8601Fractional.date(from: value)
    }

    private struct InterpolationResult {
        let coordinate: CLLocationCoordinate2D
        let bearing: Double
    }

    private static func interpolate(
        _ coordinates: [CLLocationCoordinate2D],
        progress: Double
    ) -> InterpolationResult? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return InterpolationResult(coordinate: first, bearing: 0)
        }

        var lengths: [Double] = []
        lengths.reserveCapacity(coordinates.count - 1)
        var total = 0.0
        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let dx = end.longitude - start.longitude
            let dy = end.latitude - start.latitude
            let length = hypot(dx, dy)
            lengths.append(length)
            total += length
        }
        guard total > 0 else {
            return InterpolationResult(coordinate: first, bearing: 0)
        }

        let target = progress * total
        var accumulated = 0.0
        for index in lengths.indices {
            let length = lengths[index]
            if accumulated + length >= target {
                let start = coordinates[index]
                let end = coordinates[index + 1]
                let localProgress = length > 0 ? (target - accumulated) / length : 0
                return InterpolationResult(
                    coordinate: CLLocationCoordinate2D(
                        latitude: start.latitude + localProgress * (end.latitude - start.latitude),
                        longitude: start.longitude + localProgress * (end.longitude - start.longitude)
                    ),
                    bearing: bearing(from: start, to: end)
                )
            }
            accumulated += length
        }

        let end = coordinates[coordinates.count - 1]
        let previous = coordinates[coordinates.count - 2]
        return InterpolationResult(coordinate: end, bearing: bearing(from: previous, to: end))
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
