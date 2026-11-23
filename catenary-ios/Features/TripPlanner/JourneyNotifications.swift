import CryptoKit
import FirebaseCore
import FirebaseMessaging
import Foundation
import Security
import UIKit
import UserNotifications

/// Mirrors Compose's journey-notifier /v1/devices and /v1/journeys/sync protocol.
/// Device authorization credentials are installation-scoped and stored in Keychain.
@MainActor
final class JourneyNotifications {
    static let shared = JourneyNotifications()

    private let credentialAccount = "journey-notifier-device"
    private let credentialService = "org.catenarymaps.maps.journey-notifier"
    private var registrationToken: String?
    private var reconciliation: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    /// Can be changed at build time via the app's Info.plist.
    var endpoint: URL? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "JourneyNotifierBaseURL") as? String)
            ?? "https://notify1.catenarymaps.org"
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else {
            return nil
        }
        return url
    }

    private init() {}

    func receivedToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        registrationToken = token
        syncSoon()
    }

    func requestPermissionForJourney() {
        guard FirebaseApp.app() != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
            } else {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    func syncSoon() {
        reconciliation?.cancel()
        reconciliation = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await synchronize()
            } catch {
                NSLog("Journey notifier sync failed: %@", error.localizedDescription)
            }
        }
    }

    private struct DeviceCredentials: Codable {
        let id: String
        let secret: String
    }

    private func savedCredentials() -> DeviceCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: credentialAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceCredentials.self, from: data)
    }

    private func store(_ credentials: DeviceCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: credentialAccount
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            values.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw NotifierError.keychain
            }
        } else if status != errSecSuccess {
            throw NotifierError.keychain
        }
    }

    enum NotifierError: Error {
        case keychain
        case http(Int)
        case invalidResponse
    }

    private func send(_ method: String, path: String, json: [String: Any],
                      credentials: DeviceCredentials?) async throws -> Data {
        guard let endpoint else { throw NotifierError.invalidResponse }
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        if let credentials {
            request.setValue(credentials.id, forHTTPHeaderField: "X-Device-Id")
            request.setValue("Bearer \(credentials.secret)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NotifierError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw NotifierError.http(response.statusCode) }
        return data
    }

    private static func epoch(_ raw: String?) -> Int? {
        directionsDate(raw).map { Int($0.timeIntervalSince1970) }
    }

    static func stableID(_ itinerary: DirectionsItinerary) -> String {
        SHA256.hash(data: Data(itinerary.identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Return nil for a journey the notifier cannot identify without guessing.
    static func payload(_ snapshot: TripPlannerModel.SavedDirectionsJourney) -> [String: Any]? {
        let itinerary = snapshot.itinerary
        guard let scheduledEnd = epoch(itinerary.endTime) else { return nil }
        let transit = itinerary.legs.enumerated().filter { !$0.element.street }
        guard !transit.isEmpty else { return nil }
        var entries: [[String: Any]] = []
        for (index, current) in transit.enumerated() {
            let leg = current.element
            guard let date = leg.tripStartDate, let chateau = leg.chateau,
                  let trip = leg.tripId, let from = leg.from, let to = leg.to,
                  let departure = epoch(leg.departureEvent?.timetabledTime ?? leg.startTime),
                  let arrival = epoch(leg.arrivalEvent?.timetabledTime ?? leg.endTime) else {
                return nil
            }
            var transfer = 120
            if index > 0 {
                let previousIndex = transit[index - 1].offset
                let middle = itinerary.legs[(previousIndex + 1)..<current.offset]
                let explicitWalk = middle.reduce(0.0) { $0 + max(0, $1.duration ?? 0) }
                if explicitWalk > 0 { transfer = min(3600, Int(explicitWalk)) }
            }
            func nullable(_ value: Any?) -> Any { value ?? NSNull() }
            entries.append([
                "chateau": chateau, "tripId": trip, "tripStartDate": date,
                "tripStartTime": nullable(leg.tripStartTime),
                "fromStopSequence": nullable(leg.fromStopSequence),
                "toStopSequence": nullable(leg.toStopSequence),
                "fromStopId": nullable(from.stopId),
                "toStopId": nullable(to.stopId),
                "fromName": nullable(from.name), "toName": nullable(to.name),
                "routeName": leg.label, "tripShortName": nullable(leg.tripShortName),
                "timeZone": nullable(from.timezone),
                "scheduledDeparture": departure, "scheduledArrival": arrival,
                "expectedDeparture": epoch(leg.departureCurrentTime) ?? departure,
                "expectedArrival": epoch(leg.arrivalCurrentTime) ?? arrival,
                "expectedPlatform": nullable(from.estimatedQuay ?? leg.fromPlatform ?? from.platform),
                "transferSeconds": transfer
            ])
        }
        return [
            "journeyId": stableID(itinerary),
            "scheduledEnd": scheduledEnd,
            "legs": entries
        ]
    }

    /// A sync is a complete replacement; include the current active journey even
    /// when it is not bookmarked. Deduplicate by itinerary identity.
    func synchronize() async throws {
        guard FirebaseApp.app() != nil, let token = registrationToken ?? Messaging.messaging().fcmToken,
              !token.isEmpty, endpoint != nil else { return }
        var credentials = savedCredentials()
        if credentials == nil {
            let data = try await send("POST", path: "v1/devices",
                                      json: ["fcmToken": token], credentials: nil)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["deviceId"] as? String, !id.isEmpty,
                  let secret = object["deviceSecret"] as? String, !secret.isEmpty else {
                throw NotifierError.invalidResponse
            }
            credentials = DeviceCredentials(id: id, secret: secret)
            try store(credentials!)
        } else if defaults.string(forKey: "journey-notifier.fcm-token") != token {
            _ = try await send("PUT", path: "v1/devices/\(credentials!.id)",
                               json: ["fcmToken": token], credentials: credentials)
        }
        defaults.set(token, forKey: "journey-notifier.fcm-token")

        var snapshots: [TripPlannerModel.SavedDirectionsJourney] = []
        let bookmarks = GlobalViewObject.tripPlanner.savedJourneys
        for saved in bookmarks.values { snapshots.append(saved) }
        if let active = ActiveJourneyStore.shared.active {
            snapshots.append(active.snapshot)
        }
        var seen = Set<String>()
        let bodies = snapshots.compactMap { snapshot -> [String: Any]? in
            guard seen.insert(snapshot.itinerary.identity).inserted else { return nil }
            return Self.payload(snapshot)
        }
        _ = try await send("POST", path: "v1/journeys/sync",
                           json: ["journeys": bodies], credentials: credentials)
    }
}

/// Firebase is configured only if the actual iOS client plist is bundled.
/// Never bundle a Firebase Admin service-account key in the application.
enum JourneyFirebaseBootstrap {
    @MainActor static func configureIfAvailable() {
        guard FirebaseApp.app() == nil,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else { return }
        FirebaseApp.configure(options: options)
    }
}
