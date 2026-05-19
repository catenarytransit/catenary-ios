//
//  SpruceWebSocket.swift
//  catenary-ios
//
//  Created by Chris Rios on 5/18/26.
//

import Foundation
import Combine

// MARK: - Wire formats (Codable)

struct MapViewportUpdate: Codable {
    var type: String = "update_map"
    let chateaus: [String]
    let categories: [String]
    let bounds_input: BoundsInput
}

struct SubscribeTrip: Codable {
    var type: String = "subscribe_trip"
    let chateau: String
    let trip_id: String
    let route_id: String?
    let start_date: String?
    let start_time: String?
}

struct UnsubscribeTrip: Codable {
    var type: String = "unsubscribe_trip"
    let chateau: String
    let trip_id: String?
    let route_id: String?
    let start_date: String?
    let start_time: String?
}

// Common envelope coming back from server (decode-only; we never send this shape).
struct SpruceCommonMessage: Decodable {
    let type: String
    let data: JSONValue?            // for initial_trip and update_trip
    let chateaus: [String: EachChateauResponseV2]? // alternative map_update payload
    let map_update: BulkRealtimeResponseV2? // wrapped map_update
    let message: String?            // for error
}

// MARK: - JSON helper for arbitrary payloads

/// A lightweight JSON value enum to carry arbitrary data akin to Kotlin's JsonElement.
/// If your project already has such a type, feel free to replace this.
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

// MARK: - Wire types used by the WebSocket

/// Lat/lon bounding box sent to Spruce in `update_map` messages.
/// (Distinct from the tile-coordinate `BoundsInputV3` used by the HTTP API.)
struct BoundsInput: Codable, Equatable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
}

/// `map_update` payload from Spruce. Re-uses `EachChateauResponseV2` from
/// `RealtimeVehicles.swift` (same wire format as the HTTP `bulk_realtime_fetch_v3`).
struct BulkRealtimeResponseV2: Decodable {
    let chateaus: [String: EachChateauResponseV2]
}

// MARK: - SpruceWebSocket (Swift)

private let TAG = "SpruceWebSocket"

final class SpruceWebSocket: NSObject, ObservableObject {
    static let shared = SpruceWebSocket()

    // StateFlow analogues — @Published gives SwiftUI views the same
    // "latest value, multi-subscriber, observe-from-anywhere" semantics
    // that Kotlin's MutableStateFlow provides.
    @Published private(set) var spruceStatus: String = "disconnected"
    @Published private(set) var spruceMapData: BulkRealtimeResponseV2?
    @Published private(set) var spruceTripData: JSONValue?
    @Published private(set) var spruceUpdateData: JSONValue?
    @Published private(set) var spruceError: String?

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

    // Keep last-sent params to resend on reconnect
    private var activeMapParams: MapViewportUpdate?
    private var activeTripParams: SubscribeTrip?

    // Reconnect control
    private var reconnectWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "SpruceWebSocket.queue")

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 0 // keep-alive
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    func initConnection() {
        ensureConnection()
    }

    func updateMap(categories: [String], chateaus: [String], boundsInput: BoundsInput) {
        ensureConnection()
        let params = MapViewportUpdate(chateaus: chateaus, categories: categories, bounds_input: boundsInput)
        activeMapParams = params
        sendMapUpdate(params)
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
        // Clear active subscription so it doesn't resend on reconnect
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

    // MARK: - Connection lifecycle

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
                // Continue listening
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
                    publish { self.spruceMapData = map }
                } else if let chateaus = msg.chateaus {
                    let wrapped = BulkRealtimeResponseV2(chateaus: chateaus)
                    publish { self.spruceMapData = wrapped }
                }
            case "error":
                publish { self.spruceError = msg.message }
                print("\(TAG): Spruce WS Error: \(msg.message ?? "")")
            default:
                break
            }
        } catch {
            // Match Kotlin: parse errors are logged only, not surfaced via spruceError
            print("\(TAG): Error parsing Spruce WS message: \(error)")
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

    // MARK: - Sending

    private func sendMapUpdate(_ params: MapViewportUpdate) {
        guard spruceStatus == "connected" else { return }
        sendCodable(params, errorContext: "map update")
    }

    private func sendTripSubscription(_ params: SubscribeTrip) {
        guard spruceStatus == "connected" else { return }
        sendCodable(params, errorContext: "trip subscription")
    }

    private func sendCodable<T: Encodable>(_ value: T, errorContext: String) {
        do {
            let data = try encoder.encode(value)
            if let text = String(data: data, encoding: .utf8) {
                task?.send(.string(text)) { error in
                    if let error { print("\(TAG): Error sending \(errorContext): \(error)") }
                }
            }
        } catch {
            print("\(TAG): Error sending \(errorContext): \(error)")
        }
    }

    // MARK: - Helpers

    /// Mirror `MutableStateFlow.value =`: only emit when the value actually changes.
    private func setStatus(_ newValue: String) {
        guard spruceStatus != newValue else { return }
        publish { self.spruceStatus = newValue }
    }

    /// Publish `@Published` writes on the main thread to keep SwiftUI happy.
    private func publish(_ apply: @escaping () -> Void) {
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SpruceWebSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("\(TAG): Spruce WS Connected")
        setStatus("connected")
        // Resend active subscriptions
        if let map = activeMapParams {
            print("\(TAG): Resending active map params")
            sendMapUpdate(map)
        }
        if let trip = activeTripParams {
            print("\(TAG): Resending active trip params")
            sendTripSubscription(trip)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("\(TAG): Spruce WS Closing: \(closeCode.rawValue)")
        // Match Kotlin onClosing: do NOT schedule a reconnect here; only onFailure does.
        setStatus("disconnected")
        task = nil
    }
}
