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
    let content: TrajectoryItem?
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

struct RealtimeTrajectoryVehicle: Identifiable, Hashable, @unchecked Sendable {
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

private struct PreparedTrajectory: @unchecked Sendable {
    let id: String
    let departure: Date
    let arrival: Date
    let coordinates: [CLLocationCoordinate2D]
    let cumulativeLengths: [Double]
    let totalLength: Double
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

private struct TrajectoryInterpolationResult: Sendable {
    let latitude: Double
    let longitude: Double
    let bearing: Double
}

private actor TrajectoryInterpolationWorker {
    func positions(
        for trajectories: [PreparedTrajectory],
        at now: Date
    ) -> [RealtimeTrajectoryVehicle] {
        makeCurrentTrajectoryPositions(trajectories: trajectories, now: now)
    }
}

private func makeCurrentTrajectoryPositions(
    trajectories: [PreparedTrajectory],
    now: Date
) -> [RealtimeTrajectoryVehicle] {
    var output: [RealtimeTrajectoryVehicle] = []
    output.reserveCapacity(trajectories.count)

    for trajectory in trajectories {
        if Task.isCancelled { return [] }

        let start = trajectory.departure.addingTimeInterval(-30)
        let end = trajectory.arrival.addingTimeInterval(30)
        guard now >= start, now <= end else { continue }

        let duration = trajectory.arrival.timeIntervalSince(trajectory.departure)
        guard duration > 0 else { continue }
        let progress = max(0, min(1, now.timeIntervalSince(trajectory.departure) / duration))
        guard let interpolated = interpolateTrajectory(trajectory, progress: progress) else {
            continue
        }

        output.append(RealtimeTrajectoryVehicle(
            id: "trajectory_\(trajectory.id)",
            coordinate: CLLocationCoordinate2D(
                latitude: interpolated.latitude,
                longitude: interpolated.longitude
            ),
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

    output.sort { $0.id < $1.id }
    return output
}

private func interpolateTrajectory(
    _ trajectory: PreparedTrajectory,
    progress: Double
) -> TrajectoryInterpolationResult? {
    guard let first = trajectory.coordinates.first else { return nil }
    guard trajectory.coordinates.count > 1 else {
        return TrajectoryInterpolationResult(
            latitude: first.latitude,
            longitude: first.longitude,
            bearing: 0
        )
    }
    guard trajectory.totalLength > 0 else {
        return TrajectoryInterpolationResult(
            latitude: first.latitude,
            longitude: first.longitude,
            bearing: 0
        )
    }

    let target = progress * trajectory.totalLength
    var low = 1
    var high = trajectory.cumulativeLengths.count - 1
    while low < high {
        let middle = (low + high) / 2
        if trajectory.cumulativeLengths[middle] < target {
            low = middle + 1
        } else {
            high = middle
        }
    }

    let endIndex = low
    let startIndex = endIndex - 1
    let start = trajectory.coordinates[startIndex]
    let end = trajectory.coordinates[endIndex]
    let startDistance = trajectory.cumulativeLengths[startIndex]
    let segmentLength = trajectory.cumulativeLengths[endIndex] - startDistance
    let localProgress = segmentLength > 0 ? (target - startDistance) / segmentLength : 0

    return TrajectoryInterpolationResult(
        latitude: start.latitude + localProgress * (end.latitude - start.latitude),
        longitude: start.longitude + localProgress * (end.longitude - start.longitude),
        bearing: trajectoryBearing(from: start, to: end)
    )
}

private func trajectoryBearing(
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

// MARK: - Store

@MainActor
final class RealtimeTrajectories: ObservableObject {
    private(set) var vehicles: [RealtimeTrajectoryVehicle] = []
    var onVehiclesChanged: (([RealtimeTrajectoryVehicle]) -> Void)?

    private struct Subscription {
        let bbox: [Double]
        let zoom: Int
        let modes: [String]
        let clientReference: String

        func matches(bbox: [Double], zoom: Int, modes: [String]) -> Bool {
            self.bbox == bbox && self.zoom == zoom && self.modes == modes
        }
    }

    private struct ChunkAccumulator {
        let timestamp: UInt64
        var totalChunks: Int
        var chunks: [Int: [TrajectoryWrapper]]
    }

    private var bounds: MLNCoordinateBounds?
    private var currentZoom: Double = 5
    private var layerSettings = AllLayerSettings()

    private var activeSubscription: Subscription?
    private var subscriptionTask: Task<Void, Never>?
    private var subscriptionRefreshTask: Task<Void, Never>?
    private var interpolationTask: Task<Void, Never>?
    private var positionPublishTask: Task<Void, Never>?
    private var snapshotCommitTask: Task<Void, Never>?
    private var bufferCancellable: AnyCancellable?
    private var isRunning = false
    private var subscriptionGeneration: UInt64 = 0
    private var renderGeneration: UInt64 = 0

    private var accumulators: [String: ChunkAccumulator] = [:]
    /// Completed chateau snapshots for the newest subscription are staged here
    /// while the old rendered snapshot remains visible.
    private var stagedTrajectoriesByChateau: [String: [PreparedTrajectory]] = [:]
    private var pendingSnapshotClientReference: String?
    private var trajectoriesByChateau: [String: [PreparedTrajectory]] = [:]
    private var latestSnapshotTimestampByChateau: [String: UInt64] = [:]
    private let interpolationWorker = TrajectoryInterpolationWorker()

    private let subscriptionDebounce: Duration = .milliseconds(125)
    private let subscriptionRefreshInterval: Duration = .seconds(15)
    private let snapshotCommitDelay: Duration = .milliseconds(400)
    private static let clientReferencePrefix = "trajectories_layer"

    func updateViewport(bounds: MLNCoordinateBounds, zoom: Double) {
        self.bounds = bounds
        currentZoom = zoom
        scheduleSubscription()
    }

    func updateLayerSettings(_ settings: AllLayerSettings) {
        guard settings != layerSettings else { return }
        layerSettings = settings
        scheduleSubscription()
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
        positionPublishTask?.cancel()
        positionPublishTask = nil
        snapshotCommitTask?.cancel()
        snapshotCommitTask = nil
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
        guard currentZoom.isFinite else { return }

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
        guard bbox.allSatisfy({ $0.isFinite }) else { return }
        let requestedZoom = Int(currentZoom.rounded(.down))
        let zoom = max(0, min(255, requestedZoom))
        if !forceRefresh,
           activeSubscription?.matches(bbox: bbox, zoom: zoom, modes: modes) == true {
            return
        }

        subscriptionGeneration &+= 1
        let subscription = Subscription(
            bbox: bbox,
            zoom: zoom,
            modes: modes,
            clientReference: "\(Self.clientReferencePrefix)-\(subscriptionGeneration)"
        )

        snapshotCommitTask?.cancel()
        snapshotCommitTask = nil
        activeSubscription = subscription
        accumulators.removeAll(keepingCapacity: true)
        stagedTrajectoriesByChateau.removeAll(keepingCapacity: true)
        pendingSnapshotClientReference = subscription.clientReference

        // Keep the previous completed snapshot visible until each chateau's new
        // chunk set is complete. A unique reference prevents late chunks from a
        // superseded fast-pan request from replacing the newest snapshot.
        SpruceWebSocket.shared.subscribeTrajectories(
            bbox: subscription.bbox,
            zoom: subscription.zoom,
            modes: subscription.modes,
            clientReference: subscription.clientReference
        )
    }

    private func apply(_ message: TrajectoryBuffer) {
        guard message.clientReference == activeSubscription?.clientReference else { return }

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
            let trajectories = Self.prepareTrajectories(
                message.content,
                fallbackChateau: message.chateau
            )
            stageCompletedSnapshot(
                trajectories,
                chateau: message.chateau,
                timestamp: message.timestamp,
                clientReference: message.clientReference
            )
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
        let trajectories = Self.prepareTrajectories(
            wrappers,
            fallbackChateau: message.chateau
        )
        accumulators.removeValue(forKey: message.chateau)
        stageCompletedSnapshot(
            trajectories,
            chateau: message.chateau,
            timestamp: message.timestamp,
            clientReference: message.clientReference
        )
    }

    private func stageCompletedSnapshot(
        _ trajectories: [PreparedTrajectory],
        chateau: String,
        timestamp: UInt64,
        clientReference: String
    ) {
        guard activeSubscription?.clientReference == clientReference else { return }
        latestSnapshotTimestampByChateau[chateau] = timestamp
        stagedTrajectoriesByChateau[chateau] = trajectories
        pendingSnapshotClientReference = clientReference
        scheduleSnapshotCommit(for: clientReference)
    }

    /// Apply every completed chateau received during the Spruce burst in one
    /// main-actor transaction. Empty chateau snapshots remove old data, while
    /// chateaus that have not responded yet keep their previous positions.
    private func scheduleSnapshotCommit(for clientReference: String) {
        snapshotCommitTask?.cancel()
        snapshotCommitTask = Task { [weak self] in
            try? await Task.sleep(for: self?.snapshotCommitDelay ?? .milliseconds(400))
            if Task.isCancelled { return }
            guard let self else { return }
            self.snapshotCommitTask = nil

            guard self.activeSubscription?.clientReference == clientReference,
                  self.pendingSnapshotClientReference == clientReference else { return }

            let staged = self.stagedTrajectoriesByChateau
            self.stagedTrajectoriesByChateau.removeAll(keepingCapacity: true)
            self.pendingSnapshotClientReference = nil

            for (chateau, trajectories) in staged {
                if trajectories.isEmpty {
                    self.trajectoriesByChateau.removeValue(forKey: chateau)
                } else {
                    self.trajectoriesByChateau[chateau] = trajectories
                }
            }

            self.schedulePositionPublish()
        }
    }

    private func interpolationLoop() async {
        while !Task.isCancelled {
            let interval: Duration
            if currentZoom < 7 {
                interval = .seconds(2)
            } else if currentZoom > 12 {
                interval = .milliseconds(200)
            } else {
                interval = .milliseconds(300)
            }
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            schedulePositionPublish()
        }
    }

    private func schedulePositionPublish(now: Date = Date()) {
        let snapshot = trajectoriesByChateau.values.flatMap { $0 }
        renderGeneration &+= 1
        let generation = renderGeneration
        let worker = interpolationWorker

        positionPublishTask?.cancel()
        positionPublishTask = Task { [weak self] in
            let output = await worker.positions(for: snapshot, at: now)
            guard let self,
                  !Task.isCancelled,
                  generation == self.renderGeneration else { return }

            self.positionPublishTask = nil
            guard output != self.vehicles else { return }
            self.vehicles = output
            self.onVehiclesChanged?(output)
        }
    }

    private func clear() {
        snapshotCommitTask?.cancel()
        snapshotCommitTask = nil
        accumulators.removeAll(keepingCapacity: true)
        stagedTrajectoriesByChateau.removeAll(keepingCapacity: true)
        pendingSnapshotClientReference = nil
        trajectoriesByChateau.removeAll(keepingCapacity: true)
        latestSnapshotTimestampByChateau.removeAll(keepingCapacity: true)
        renderGeneration &+= 1
        positionPublishTask?.cancel()
        positionPublishTask = nil
        guard !vehicles.isEmpty else { return }
        vehicles = []
        onVehiclesChanged?([])
    }

    private static func prepareTrajectories(
        _ wrappers: [TrajectoryWrapper],
        fallbackChateau: String
    ) -> [PreparedTrajectory] {
        wrappers.compactMap { wrapper in
            guard let content = wrapper.content else { return nil }
            return prepare(content, fallbackChateau: fallbackChateau)
        }
    }

    private static func prepare(_ item: TrajectoryItem, fallbackChateau: String) -> PreparedTrajectory? {
        let identifier = item.unique_trip_id ?? item.trip_id
        guard let identifier, !identifier.isEmpty,
              let stops = item.stops, let first = stops.first, let last = stops.last,
              let departure = parseDate(first.departure ?? first.arrival),
              let arrival = parseDate(last.arrival ?? last.departure),
              arrival > departure
        else { return nil }

        let chateauID = item.chateau_id.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackChateau
        var coordinates: [CLLocationCoordinate2D] = []
        for segment in item.segments ?? [] {
            for pair in segment.coordinates ?? [] where pair.count >= 2 {
                let longitude = pair[0]
                let latitude = pair[1]
                guard longitude.isFinite,
                      latitude.isFinite,
                      (-180.0...180.0).contains(longitude),
                      (-90.0...90.0).contains(latitude)
                else { continue }

                let coordinate = CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: longitude
                )
                if coordinates.last?.latitude != coordinate.latitude
                    || coordinates.last?.longitude != coordinate.longitude {
                    coordinates.append(coordinate)
                }
            }
        }
        guard !coordinates.isEmpty else { return nil }

        var cumulativeLengths = [0.0]
        cumulativeLengths.reserveCapacity(coordinates.count)
        var totalLength = 0.0
        if coordinates.count > 1 {
            for index in 0..<(coordinates.count - 1) {
                let start = coordinates[index]
                let end = coordinates[index + 1]
                totalLength += hypot(
                    end.longitude - start.longitude,
                    end.latitude - start.latitude
                )
                cumulativeLengths.append(totalLength)
            }
        }

        return PreparedTrajectory(
            id: "\(chateauID)|\(identifier)",
            departure: departure,
            arrival: arrival,
            coordinates: coordinates,
            cumulativeLengths: cumulativeLengths,
            totalLength: totalLength,
            routeType: item.route_type ?? routeType(for: item.mode),
            chateauID: chateauID,
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

}
