//
//  SpruceWebSocket.swift
//  catenary-ios
//
//  Created by Chris Rios on 5/18/26.
//

import Foundation
import Combine

struct MapViewportUpdate: Encodable {
    var type: String = "subscribe_map_v2"
    let categories: [String]
    let bounds_input: BoundsInput
}

struct UnsubscribeMapV2: Encodable {
    var type: String = "unsubscribe_map_v2"
}

struct SubscribeTrip: Encodable {
    var type: String = "subscribe_trip"
    let chateau: String
    let trip_id: String
    let route_id: String?
    let start_date: String?
    let start_time: String?
}

struct UnsubscribeTrip: Encodable {
    var type: String = "unsubscribe_trip"
    let chateau: String
    let trip_id: String?
    let route_id: String?
    let start_date: String?
    let start_time: String?
}

struct SubscribeTrajectories: Encodable {
    var type: String = "subscribe_trajectories"
    let bbox: [Double]
    let zoom: Int
    let modes: [String]
    let precision: Int?
    let client_reference: String
}

struct UnsubscribeTrajectories: Encodable {
    var type: String = "unsubscribe_trajectories"
}

// Common envelope coming back from server (decode-only; we never send this shape).
struct SpruceCommonMessage: Decodable {
    let type: String
    let data: JSONValue?            // for initial_trip and update_trip
    let chateaus: [String: EachChateauResponseV2]? // alternative map_update payload
    let map_update: BulkRealtimeResponseV2? // wrapped map_update
    let message: String?            // for error
    let timestamp: UInt64?
    let client_reference: String?
    let chateau: String?
    let content: [TrajectoryWrapper]?
    let chunk_index: Int?
    let total_chunks: Int?
}

indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .number(let n):
            try container.encode(n)
        case .string(let s):
            try container.encode(s)
        case .array(let arr):
            try container.encode(arr)
        case .object(let obj):
            try container.encode(obj)
        }
    }
}

/// Tile-coordinate bounding box sent to Spruce in `update_map` messages.
struct BoundsInput: Encodable, Equatable {
    let level5: BoundsInputPerLevel
    let level7: BoundsInputPerLevel
    let level8: BoundsInputPerLevel
    let level12: BoundsInputPerLevel
}

struct BulkRealtimeResponseV2: Decodable {
    let chateaus: [String: EachChateauResponseV2]
}

private let TAG = "SpruceWebSocket"

final class SpruceWebSocket: NSObject, ObservableObject {
    static let shared = SpruceWebSocket()

    @Published private(set) var spruceStatus: String = "disconnected"
    @Published private(set) var spruceMapData: BulkRealtimeResponseV2?
    @Published private(set) var spruceTripData: JSONValue?
    @Published private(set) var spruceUpdateData: JSONValue?
    @Published private(set) var spruceError: String?

    /// Chunked trajectory messages are events, not state. A subject guarantees
    /// that every chunk is delivered to the trajectory accumulator in order.
    let trajectoryMessages = PassthroughSubject<TrajectoryBuffer, Never>()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?

    private var activeMapParams: MapViewportUpdate?
    private var activeTripParams: SubscribeTrip?
    private var activeTrajectoryParams: SubscribeTrajectories?

    private var reconnectWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "SpruceWebSocket.queue")

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 0 // keep-alive
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func initConnection() {
        ensureConnection()
    }

    func updateMap(categories: [String], boundsInput: BoundsInput) {
        ensureConnection()
        let params = MapViewportUpdate(categories: categories, bounds_input: boundsInput)
        activeMapParams = params
        sendMapUpdate(params)
    }

    func unsubscribeMap() {
        guard activeMapParams != nil else { return }
        activeMapParams = nil
        guard spruceStatus == "connected" else { return }
        sendCodable(UnsubscribeMapV2(), errorContext: "map unsubscribe")
    }

    func subscribeTrajectories(
        bbox: [Double],
        zoom: Int,
        modes: [String],
        precision: Int? = nil,
        clientReference: String = "trajectories_layer"
    ) {
        ensureConnection()
        let params = SubscribeTrajectories(
            bbox: bbox,
            zoom: zoom,
            modes: modes,
            precision: precision,
            client_reference: clientReference
        )
        activeTrajectoryParams = params
        sendTrajectorySubscription(params)
    }

    func unsubscribeTrajectories() {
        guard activeTrajectoryParams != nil else { return }
        activeTrajectoryParams = nil
        guard spruceStatus == "connected" else { return }
        sendCodable(
            UnsubscribeTrajectories(),
            errorContext: "trajectory unsubscribe"
        )
    }

    func subscribeTrip(chateau: String,
                       tripId: String,
                       routeId: String? = nil,
                       startDate: String? = nil,
                       startTime: String? = nil) {
        ensureConnection()
        let params = SubscribeTrip(chateau: chateau, trip_id: tripId, route_id: routeId, start_date: startDate, start_time: startTime)
        activeTripParams = params
        sendTripSubscription(params)
    }

    func unsubscribeTrip(chateau: String) {
        let paramsToSend = activeTripParams
        activeTripParams = nil
        guard spruceStatus == "connected" else { return }
        let msg = UnsubscribeTrip(chateau: chateau,
                                  trip_id: paramsToSend?.trip_id,
                                  route_id: paramsToSend?.route_id,
                                  start_date: paramsToSend?.start_date,
                                  start_time: paramsToSend?.start_time)
        sendCodable(msg, errorContext: "unsubscribe trip")
    }

    private func ensureConnection() {
        if task != nil, spruceStatus == "connected" || spruceStatus == "connecting" { return }
        connect()
    }

    private func connect() {
        setStatus("connecting")
        var request = URLRequest(url: URL(string: "wss://spruce.catenarymaps.org/ws/")!)
        request.timeoutInterval = 60
        task = session.webSocketTask(with: request)
        task?.resume()
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleFailure(error: error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncoming(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncoming(text: text)
                    } else {
                        // Non-UTF8 payloads not expected
                    }
                @unknown default:
                    break
                }
                self.listen()
            }
        }
    }

    private func handleIncoming(text: String) {
        do {
            let msg = try decoder.decode(SpruceCommonMessage.self, from: Data(text.utf8))
            switch msg.type {
            case "initial_trip":
                publish { self.spruceTripData = msg.data }
            case "update_trip":
                publish { self.spruceUpdateData = msg.data }
            case "map_update":
                if let map = msg.map_update {
                    print("\(TAG): map_update received (chateaus=\(map.chateaus.count))")
                    publish { self.spruceMapData = map }
                } else if let chateaus = msg.chateaus {
                    print("\(TAG): map_update received (top-level chateaus=\(chateaus.count))")
                    let wrapped = BulkRealtimeResponseV2(chateaus: chateaus)
                    publish { self.spruceMapData = wrapped }
                } else {
                    print("\(TAG): map_update received but neither map_update nor chateaus populated")
                }
            case "buffer":
                guard let timestamp = msg.timestamp,
                      let content = msg.content,
                      let totalChunks = msg.total_chunks
                else { return }

                let chunkIndex: Int
                if totalChunks == 0 {
                    chunkIndex = msg.chunk_index ?? 0
                } else {
                    guard let value = msg.chunk_index else { return }
                    chunkIndex = value
                }

                let buffer = TrajectoryBuffer(
                    timestamp: timestamp,
                    clientReference: msg.client_reference ?? "trajectories_layer",
                    chateau: msg.chateau ?? "unknown",
                    content: content,
                    chunkIndex: chunkIndex,
                    totalChunks: totalChunks
                )
                publish { self.trajectoryMessages.send(buffer) }
            case "pong":
                break
            case "error":
                publish { self.spruceError = msg.message }
                print("\(TAG): Spruce WS Error: \(msg.message ?? "")")
            default:
                print("\(TAG): Unhandled WS message type: \(msg.type)")
            }
        } catch {
            print("\(TAG): Error parsing Spruce WS message: \(error)")
            print("\(TAG): Raw: \(text.prefix(300))")
        }
    }

    private func handleFailure(error: Error) {
        print("\(TAG): Spruce WS Failure: \(error)")
        setStatus("error")
        task = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.ensureConnection() }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // NOTE: we don't gate sends on `spruceStatus == "connected"` because the
    // status update is dispatched to main async (so it lags behind the actual
    // connection by one runloop). URLSessionWebSocketTask.send() will queue
    // messages until the handshake completes, then flush them. Gating here
    // was silently dropping the first `update_map` on every fresh connect.
    private func sendMapUpdate(_ params: MapViewportUpdate) {
        sendCodable(params, errorContext: "map update")
    }

    private func sendTrajectorySubscription(_ params: SubscribeTrajectories) {
        sendCodable(params, errorContext: "trajectory subscription")
    }

    private func sendTripSubscription(_ params: SubscribeTrip) {
        sendCodable(params, errorContext: "trip subscription")
    }

    private func sendCodable<T: Encodable>(_ value: T, errorContext: String) {
        guard let task else {
            print("\(TAG): Dropping \(errorContext) — no task yet")
            return
        }
        do {
            let data = try encoder.encode(value)
            if let text = String(data: data, encoding: .utf8) {
                print("\(TAG): Sending \(errorContext) (\(data.count) bytes)")
                task.send(.string(text)) { error in
                    if let error { print("\(TAG): Error sending \(errorContext): \(error)") }
                }
            }
        } catch {
            print("\(TAG): Error sending \(errorContext): \(error)")
        }
    }

    private func setStatus(_ newValue: String) {
        guard spruceStatus != newValue else { return }
        publish { self.spruceStatus = newValue }
    }

    private func publish(_ apply: @escaping () -> Void) {
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

extension SpruceWebSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("\(TAG): Spruce WS Connected")
        setStatus("connected")
        if let map = activeMapParams {
            print("\(TAG): Resending active map params")
            sendMapUpdate(map)
        }
        if let trip = activeTripParams {
            print("\(TAG): Resending active trip params")
            sendTripSubscription(trip)
        }
        if let trajectory = activeTrajectoryParams {
            print("\(TAG): Resending active trajectory params")
            sendTrajectorySubscription(trajectory)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("\(TAG): Spruce WS Closing: \(closeCode.rawValue)")
        setStatus("disconnected")
        task = nil
    }
}
