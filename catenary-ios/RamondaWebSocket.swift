import Foundation

private struct RamondaSubscribeTrip: Encodable, Equatable {
    let type = "subscribe_trip"
    let chateau: String
    let tripID: String
    let routeID: String?
    let startDate: String?
    let startTime: String?

    enum CodingKeys: String, CodingKey {
        case type
        case chateau
        case tripID = "trip_id"
        case routeID = "route_id"
        case startDate = "start_date"
        case startTime = "start_time"
    }
}

private struct RamondaUnsubscribeTrip: Encodable {
    let type = "unsubscribe_trip"
    let chateau: String
    let tripID: String?
    let routeID: String?
    let startDate: String?
    let startTime: String?

    enum CodingKeys: String, CodingKey {
        case type
        case chateau
        case tripID = "trip_id"
        case routeID = "route_id"
        case startDate = "start_date"
        case startTime = "start_time"
    }
}

@MainActor
final class RamondaWebSocket: NSObject, ObservableObject {
    static let shared = RamondaWebSocket()

    @Published private(set) var status = "disconnected"
    @Published private(set) var initialTrip: SingleTripDataResponse?
    @Published private(set) var tripUpdate: SingleTripRealtimeUpdate?
    @Published private(set) var errorMessage: String?

    private let decoder = RamondaMessageDecoder()
    private var subscriptionRevision = 0

    private let encoder = JSONEncoder()
    private var session: URLSession!
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var activeSubscription: RamondaSubscribeTrip?
    private var isStopping = false

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 0
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func subscribeTrip(
        chateau: String,
        tripID: String,
        routeID: String? = nil,
        startDate: String? = nil,
        startTime: String? = nil
    ) {
        let subscription = RamondaSubscribeTrip(
            chateau: chateau,
            tripID: tripID,
            routeID: routeID,
            startDate: startDate,
            startTime: startTime
        )

        if activeSubscription != subscription {
            subscriptionRevision &+= 1
            initialTrip = nil
            tripUpdate = nil
            errorMessage = nil
        }

        activeSubscription = subscription
        isStopping = false
        ensureConnection()

        if status == "connected" {
            send(subscription, context: "trip subscription")
        }
    }

    func unsubscribeTrip(chateau: String) {
        subscriptionRevision &+= 1
        let previous = activeSubscription
        activeSubscription = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        if status == "connected" {
            send(
                RamondaUnsubscribeTrip(
                    chateau: chateau,
                    tripID: previous?.tripID,
                    routeID: previous?.routeID,
                    startDate: previous?.startDate,
                    startTime: previous?.startTime
                ),
                context: "trip unsubscription"
            )
        }

        initialTrip = nil
        tripUpdate = nil
    }

    func disconnect() {
        subscriptionRevision &+= 1
        isStopping = true
        activeSubscription = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        stopLoops()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        status = "disconnected"
    }

    private func ensureConnection() {
        guard webSocketTask == nil, status != "connecting", status != "connected" else { return }
        guard let url = URL(string: "wss://ramonda.catenarymaps.org/ws/") else {
            errorMessage = L10n.string(
                "ramonda.invalid_url",
                defaultValue: "The live trip service URL is invalid."
            )
            status = "error"
            return
        }

        status = "connecting"
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        startReceiveLoop(for: task)
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self, weak task] in
            guard let task else { return }

            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self, !Task.isCancelled, task === self.webSocketTask else { return }
                    await self.handle(message, task: task)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, !Task.isCancelled, task === self.webSocketTask else { return }
                    self.handleFailure(error)
                    return
                }
            }
        }
    }

    private func startPingLoop(for task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self, weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, let task, self.status == "connected" else { return }

                do {
                    try await task.send(.string("{\"type\":\"ping\"}"))
                } catch {
                    self.handleFailure(error)
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, task: URLSessionWebSocketTask) async {
        let revision = subscriptionRevision
        do {
            let decoded = try await decoder.decode(message)
            guard !Task.isCancelled, task === webSocketTask, revision == subscriptionRevision else { return }
            switch decoded {
            case .initial(let trip):
                guard trip.tripID == activeSubscription?.tripID else { return }
                initialTrip = trip
                errorMessage = nil
            case .update(let update):
                guard update.tripID == activeSubscription?.tripID else { return }
                if let chateau = update.chateau, chateau != activeSubscription?.chateau { return }
                tripUpdate = update
            case .error(let message):
                errorMessage = message ?? L10n.string(
                    "ramonda.unknown_error",
                    defaultValue: "The live trip service returned an unknown error."
                )
            case .ignored:
                break
            }
        } catch {
            guard !Task.isCancelled, task === webSocketTask, revision == subscriptionRevision else { return }
            errorMessage = L10n.format(
                "ramonda.decode_error",
                defaultValue: "Unable to decode live trip data: %@",
                error.localizedDescription
            )
        }
    }

    private func send<T: Encodable>(_ value: T, context: String) {
        guard let webSocketTask else { return }

        do {
            let data = try encoder.encode(value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw RamondaSocketError.invalidUTF8
            }

            Task { [weak self, weak webSocketTask] in
                guard let webSocketTask else { return }
                do {
                    try await webSocketTask.send(.string(text))
                } catch {
                    self?.errorMessage = L10n.format(
                        "ramonda.send_error",
                        defaultValue: "Unable to send %@: %@",
                        L10n.string(context),
                        error.localizedDescription
                    )
                    self?.handleFailure(error)
                }
            }
        } catch {
            errorMessage = L10n.format(
                "ramonda.encode_error",
                defaultValue: "Unable to encode %@: %@",
                L10n.string(context),
                error.localizedDescription
            )
        }
    }

    private func didOpen(_ task: URLSessionWebSocketTask) {
        guard task === webSocketTask else { return }
        status = "connected"
        reconnectTask?.cancel()
        reconnectTask = nil
        startPingLoop(for: task)

        if let activeSubscription {
            send(activeSubscription, context: "trip subscription")
        }
    }

    private func didClose(_ task: URLSessionWebSocketTask) {
        guard task === webSocketTask else { return }
        stopLoops()
        webSocketTask = nil
        status = "disconnected"
        scheduleReconnectIfNeeded()
    }

    private func handleFailure(_ error: Error) {
        guard webSocketTask != nil else { return }
        errorMessage = error.localizedDescription
        status = "error"
        stopLoops()
        webSocketTask?.cancel()
        webSocketTask = nil
        scheduleReconnectIfNeeded()
    }

    private func scheduleReconnectIfNeeded() {
        guard !isStopping, activeSubscription != nil else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.ensureConnection()
        }
    }

    private func stopLoops() {
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
    }
}

extension RamondaWebSocket: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            self?.didOpen(webSocketTask)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            self?.didClose(webSocketTask)
        }
    }
}

private enum RamondaSocketError: LocalizedError {
    case invalidEnvelope
    case missingPayload
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return L10n.string(
                "ramonda.invalid_envelope",
                defaultValue: "The server returned an invalid message."
            )
        case .missingPayload:
            return L10n.string(
                "ramonda.missing_payload",
                defaultValue: "The server message did not contain trip data."
            )
        case .invalidUTF8:
            return L10n.string(
                "ramonda.invalid_utf8",
                defaultValue: "The outgoing message could not be encoded as UTF-8."
            )
        }
    }
}

private enum RamondaMessage: Decodable {
    case initial(SingleTripDataResponse)
    case update(SingleTripRealtimeUpdate)
    case error(String?)
    case ignored

    private enum CodingKeys: String, CodingKey { case type, data, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "initial_trip":
            self = .initial(try container.decode(SingleTripDataResponse.self, forKey: .data))
        case "update_trip":
            self = .update(try container.decode(SingleTripRealtimeUpdate.self, forKey: .data))
        case "error":
            self = .error(try? container.decode(String.self, forKey: .message))
        default:
            self = .ignored
        }
    }
}

/// Keep decoding serial and outside the main actor; the receive loop awaits each frame.
private actor RamondaMessageDecoder {
    private let decoder = JSONDecoder()

    func decode(_ message: URLSessionWebSocketTask.Message) throws -> RamondaMessage {
        switch message {
        case .string(let text):
            return try decoder.decode(RamondaMessage.self, from: Data(text.utf8))
        case .data(let data):
            return try decoder.decode(RamondaMessage.self, from: data)
        @unknown default:
            return .ignored
        }
    }
}
