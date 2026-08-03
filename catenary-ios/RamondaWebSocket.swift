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

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

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
                    guard let self else { return }
                    self.handle(message)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self else { return }
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

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(receivedData):
            data = receivedData
        @unknown default:
            data = nil
        }

        guard let data else { return }

        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                throw RamondaSocketError.invalidEnvelope
            }

            switch type {
            case "initial_trip":
                let payload = try payloadData(from: object)
                initialTrip = try decoder.decode(SingleTripDataResponse.self, from: payload)
                errorMessage = nil

            case "update_trip":
                let payload = try payloadData(from: object)
                tripUpdate = try decoder.decode(SingleTripRealtimeUpdate.self, from: payload)

            case "pong":
                break

            case "error":
                errorMessage = object["message"] as? String ?? L10n.string(
                    "ramonda.unknown_error",
                    defaultValue: "The live trip service returned an unknown error."
                )

            default:
                break
            }
        } catch {
            errorMessage = L10n.format(
                "ramonda.decode_error",
                defaultValue: "Unable to decode live trip data: %@",
                error.localizedDescription
            )
        }
    }

    private func payloadData(from object: [String: Any]) throws -> Data {
        guard let payload = object["data"], !(payload is NSNull) else {
            throw RamondaSocketError.missingPayload
        }
        return try JSONSerialization.data(withJSONObject: payload)
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
