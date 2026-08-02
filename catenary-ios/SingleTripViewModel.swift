import Combine
import Foundation

@MainActor
final class SingleTripViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var tripData: SingleTripDataResponse?
    @Published private(set) var stopTimes: [SingleTripStopState] = []
    @Published private(set) var vehicleData: SingleTripVehicleRealtimeData?
    @Published private(set) var currentDate = Date()
    @Published private(set) var lastInactiveStopIndex = -1
    @Published private(set) var currentAtStopIndex = -1
    @Published private(set) var movingDotSegmentIndex = -1
    @Published private(set) var movingDotProgress = 0.0
    @Published private(set) var connectionStatus = "disconnected"

    let selection: SingleTripSelection

    private let socket: RamondaWebSocket
    private var cancellables = Set<AnyCancellable>()
    private var clockTask: Task<Void, Never>?
    private var vehiclePollTask: Task<Void, Never>?
    private var hasStarted = false

    init(selection: SingleTripSelection, socket: RamondaWebSocket? = nil) {
        self.selection = selection
        self.socket = socket ?? RamondaWebSocket.shared
        bindSocket()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard let tripID = selection.tripID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tripID.isEmpty else {
            isLoading = false
            errorMessage = L10n.string(
                "trip.missing_gtfs_id",
                defaultValue: "This trip has no GTFS trip ID and cannot be loaded."
            )
            return
        }

        isLoading = true
        errorMessage = nil
        socket.subscribeTrip(
            chateau: selection.chateauID,
            tripID: tripID,
            routeID: selection.routeID,
            startDate: selection.startDate,
            startTime: selection.startTime
        )
        startClock()
        startVehiclePolling()
    }

    func retry() {
        stop()
        tripData = nil
        stopTimes = []
        vehicleData = nil
        hasStarted = false
        start()
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        clockTask?.cancel()
        clockTask = nil
        vehiclePollTask?.cancel()
        vehiclePollTask = nil
        socket.unsubscribeTrip(chateau: selection.chateauID)
    }

    func activeAlerts(at date: Date = Date()) -> [(String, SingleTripAlert)] {
        let epochSeconds = Int64(date.timeIntervalSince1970)
        return tripData?.alerts
            .filter { $0.value.isActive(at: epochSeconds) }
            .sorted { $0.key < $1.key } ?? []
    }

    private func bindSocket() {
        socket.$status
            .removeDuplicates()
            .sink { [weak self] status in
                self?.connectionStatus = status
            }
            .store(in: &cancellables)

        socket.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                guard let self, self.tripData == nil else { return }
                self.errorMessage = message
                self.isLoading = false
            }
            .store(in: &cancellables)

        socket.$initialTrip
            .compactMap { $0 }
            .sink { [weak self] data in
                self?.handleInitialTrip(data)
            }
            .store(in: &cancellables)

        socket.$tripUpdate
            .compactMap { $0 }
            .sink { [weak self] update in
                self?.handleRealtimeUpdate(update)
            }
            .store(in: &cancellables)
    }

    private func handleInitialTrip(_ data: SingleTripDataResponse) {
        guard data.tripID == selection.tripID else { return }

        tripData = data
        stopTimes = data.stopTimes.map(makeStopState)
        isLoading = false
        errorMessage = nil
        updateStopProgress()

        Task { [weak self] in
            await self?.fetchVehicleInfo()
        }
    }

    private func handleRealtimeUpdate(_ update: SingleTripRealtimeUpdate) {
        guard update.tripID == selection.tripID else { return }
        if let chateau = update.chateau, chateau != selection.chateauID { return }

        let refreshByKey = Dictionary(
            update.stopTimes.map { (refreshKey(sequence: $0.gtfsStopSequence, stopID: $0.stopID), $0) },
            uniquingKeysWith: { _, newest in newest }
        )

        stopTimes = stopTimes.map { existing in
            let key = refreshKey(
                sequence: existing.raw.gtfsStopSequence,
                stopID: existing.raw.stopID
            )
            guard let refresh = refreshByKey[key] else { return existing }
            return merging(existing, with: refresh)
        }
        updateStopProgress()
    }

    private func makeStopState(_ stopTime: SingleTripStopTime) -> SingleTripStopState {
        let realtimeArrival = stopTime.realtimeArrival?.time
        let realtimeDeparture = stopTime.realtimeDeparture?.time
        return SingleTripStopState(
            raw: stopTime,
            realtimeArrivalTime: realtimeArrival,
            realtimeDepartureTime: realtimeDeparture,
            realtimeArrivalDifference: difference(
                realtimeArrival,
                stopTime.scheduledArrivalTimeUnixSeconds
            ),
            realtimeDepartureDifference: difference(
                realtimeDeparture,
                stopTime.scheduledDepartureTimeUnixSeconds
            )
        )
    }

    private func merging(
        _ existing: SingleTripStopState,
        with refresh: SingleTripStopTimeRefresh
    ) -> SingleTripStopState {
        let mergedRaw = SingleTripStopTime(
            name: existing.raw.name,
            stopID: existing.raw.stopID,
            longitude: existing.raw.longitude,
            latitude: existing.raw.latitude,
            timezone: existing.raw.timezone,
            scheduledArrivalTimeUnixSeconds: existing.raw.scheduledArrivalTimeUnixSeconds,
            scheduledDepartureTimeUnixSeconds: existing.raw.scheduledDepartureTimeUnixSeconds,
            interpolatedStoptimeUnixSeconds: existing.raw.interpolatedStoptimeUnixSeconds,
            realtimeArrival: refresh.realtimeArrival ?? existing.raw.realtimeArrival,
            realtimeDeparture: refresh.realtimeDeparture ?? existing.raw.realtimeDeparture,
            realtimePlatformString: refresh.realtimePlatformString ?? existing.raw.realtimePlatformString,
            scheduleRelationship: refresh.scheduleRelationship ?? existing.raw.scheduleRelationship,
            code: existing.raw.code,
            timepoint: existing.raw.timepoint,
            replacedStop: existing.raw.replacedStop,
            gtfsStopSequence: existing.raw.gtfsStopSequence,
            showBothDepartureAndArrival: existing.raw.showBothDepartureAndArrival
        )

        let realtimeArrival = refresh.realtimeArrival?.time ?? existing.realtimeArrivalTime
        let realtimeDeparture = refresh.realtimeDeparture?.time ?? existing.realtimeDepartureTime

        return SingleTripStopState(
            raw: mergedRaw,
            realtimeArrivalTime: realtimeArrival,
            realtimeDepartureTime: realtimeDeparture,
            realtimeArrivalDifference: difference(
                realtimeArrival,
                mergedRaw.scheduledArrivalTimeUnixSeconds
            ),
            realtimeDepartureDifference: difference(
                realtimeDeparture,
                mergedRaw.scheduledDepartureTimeUnixSeconds
            )
        )
    }

    private func refreshKey(sequence: Int?, stopID: String?) -> String {
        if let sequence { return "sequence|\(sequence)" }
        return "stop|\(stopID ?? "")"
    }

    private func difference(_ realtime: Int64?, _ scheduled: Int64?) -> Int64? {
        guard let realtime, let scheduled else { return nil }
        return realtime - scheduled
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.currentDate = Date()
                self.updateStopProgress()
            }
        }
    }

    private func startVehiclePolling() {
        vehiclePollTask?.cancel()
        vehiclePollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchVehicleInfo()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func fetchVehicleInfo() async {
        let vehicleID = tripData?.vehicle?.label
            ?? tripData?.vehicle?.id
            ?? selection.vehicleID
        guard let vehicleID, !vehicleID.isEmpty else { return }

        let chateau = encodedPathComponent(selection.chateauID)
        let vehicle = encodedPathComponent(vehicleID)
        guard let url = URL(
            string: "https://birch.catenarymaps.org/get_vehicle_information_from_label/\(chateau)/\(vehicle)"
        ) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return }
            let decoded = try JSONDecoder().decode(
                SingleTripVehicleRealtimeDataResponse.self,
                from: data
            )
            vehicleData = decoded.data?.first
        } catch is CancellationError {
            return
        } catch {
            // Vehicle metadata is supplementary; keep the trip screen usable.
        }
    }

    private func encodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func updateStopProgress() {
        let nowSeconds = Int64(currentDate.timeIntervalSince1970)
        let hasAnyRealtime = stopTimes.contains {
            $0.realtimeArrivalTime != nil || $0.realtimeDepartureTime != nil
        }

        var lastDeparted = -1
        var atStop = -1

        for (index, stop) in stopTimes.enumerated() {
            let arrival = effectiveArrival(for: stop, hasAnyRealtime: hasAnyRealtime)
            let departure = effectiveDeparture(for: stop, hasAnyRealtime: hasAnyRealtime)

            if let departure, departure <= nowSeconds {
                lastDeparted = index
            } else if let arrival, arrival <= nowSeconds, atStop == -1 {
                atStop = index
            }
        }

        lastInactiveStopIndex = lastDeparted
        currentAtStopIndex = atStop
        movingDotSegmentIndex = -1
        movingDotProgress = 0

        guard atStop == -1,
              lastDeparted >= 0,
              lastDeparted < stopTimes.count - 1 else { return }

        let previous = stopTimes[lastDeparted]
        let next = stopTimes[lastDeparted + 1]
        guard let departure = effectiveDeparture(for: previous, hasAnyRealtime: hasAnyRealtime),
              let arrival = effectiveArrival(for: next, hasAnyRealtime: hasAnyRealtime),
              arrival > departure else { return }

        movingDotSegmentIndex = lastDeparted
        movingDotProgress = min(
            max(Double(nowSeconds - departure) / Double(arrival - departure), 0),
            1
        )
    }

    private func effectiveArrival(
        for stop: SingleTripStopState,
        hasAnyRealtime: Bool
    ) -> Int64? {
        if let realtime = stop.realtimeArrivalTime { return realtime }
        if hasAnyRealtime { return nil }
        return stop.raw.scheduledArrivalTimeUnixSeconds
            ?? stop.raw.interpolatedStoptimeUnixSeconds
    }

    private func effectiveDeparture(
        for stop: SingleTripStopState,
        hasAnyRealtime: Bool
    ) -> Int64? {
        if let realtime = stop.realtimeDepartureTime { return realtime }
        if let realtimeArrival = stop.realtimeArrivalTime { return realtimeArrival }
        if hasAnyRealtime { return nil }
        return stop.raw.scheduledDepartureTimeUnixSeconds
            ?? stop.raw.scheduledArrivalTimeUnixSeconds
            ?? stop.raw.interpolatedStoptimeUnixSeconds
    }
}
