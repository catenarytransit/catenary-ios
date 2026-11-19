import Foundation
import SwiftUI

/// A self-contained trip snapshot, independent of the map or the screen that saved it.
/// The routing planner can later provide an analogous multi-leg journey snapshot.
struct SavedTripSnapshot: Codable, Hashable, Identifiable {
    let id: String
    let chateauID: String
    let tripID: String
    let routeID: String?
    let startTime: String?
    let startDate: String?
    let vehicleID: String?
    let routeType: Int?
    let originName: String
    let destinationName: String
    let routeLabel: String
    let headsign: String?
    let routeColor: String?
    let departure: Int64
    let arrival: Int64
    let timezoneID: String?
    let savedAt: Date

    var selection: SingleTripSelection {
        SingleTripSelection(
            chateauID: chateauID,
            tripID: tripID,
            routeID: routeID,
            startTime: startTime,
            startDate: startDate,
            vehicleID: vehicleID,
            routeType: routeType
        )
    }

    var departureDate: Date {
        Date(timeIntervalSince1970: TimeInterval(departure))
    }

    var arrivalDate: Date {
        Date(timeIntervalSince1970: TimeInterval(arrival))
    }

    var durationMinutes: Int {
        max(0, Int((arrival - departure + 30) / 60))
    }

    var dayKey: String {
        formattedDate("yyyy-MM-dd")
    }

    var dayLabel: String {
        formattedDate("EEEE, MMMM d, yyyy")
    }

    var departureLabel: String {
        formattedDate("HH:mm")
    }

    var arrivalLabel: String {
        formattedDate("HH:mm", for: arrivalDate)
    }

    private func formattedDate(_ format: String, for date: Date? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = format
        return formatter.string(from: date ?? departureDate)
    }

    static func make(
        selection: SingleTripSelection,
        data: SingleTripDataResponse,
        now: Date = Date()
    ) -> SavedTripSnapshot? {
        guard let tripID = selection.tripID ?? data.tripID, !tripID.isEmpty else { return nil }
        let stops = data.stopTimes
        guard let first = stops.first, let last = stops.last else { return nil }

        let firstTime = first.scheduledDepartureTimeUnixSeconds
            ?? first.scheduledArrivalTimeUnixSeconds
            ?? first.realtimeDeparture?.time
            ?? first.realtimeArrival?.time
        let lastTime = last.scheduledArrivalTimeUnixSeconds
            ?? last.scheduledDepartureTimeUnixSeconds
            ?? last.realtimeArrival?.time
            ?? last.realtimeDeparture?.time
        guard let departure = firstTime, let arrival = lastTime, arrival >= departure else {
            return nil
        }

        let origin = first.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = last.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedTripSnapshot(
            id: [
                selection.chateauID, tripID,
                selection.startDate ?? data.serviceDate ?? "",
                selection.startTime ?? ""
            ].joined(separator: "|"),
            chateauID: selection.chateauID,
            tripID: tripID,
            routeID: data.routeID ?? selection.routeID,
            startTime: selection.startTime,
            startDate: selection.startDate ?? data.serviceDate,
            vehicleID: selection.vehicleID,
            routeType: data.routeType ?? selection.routeType,
            originName: origin?.isEmpty == false ? origin! : first.stopID,
            destinationName: destination?.isEmpty == false ? destination! : last.stopID,
            routeLabel: data.routeShortName ?? data.tripShortName ?? data.routeLongName ?? "Trip",
            headsign: data.tripHeadsign,
            routeColor: data.color,
            departure: departure,
            arrival: arrival,
            timezoneID: first.timezone ?? data.timezone,
            savedAt: now
        )
    }
}

/// Mirrors Compose's saved-journey lifecycle: deduplication and expiry 12h after arrival.
/// iOS and Android have separate local storage; there is currently no account sync.
@MainActor
final class SavedTripsStore: ObservableObject {
    @Published private(set) var snapshots: [SavedTripSnapshot] = []
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let storageKey = "catenary.saved-trips.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            do {
                snapshots = try JSONDecoder().decode([SavedTripSnapshot].self, from: data)
            } catch {
                errorMessage = "Unable to read saved trips."
            }
        }
        refresh()
    }

    func contains(_ identity: String) -> Bool {
        snapshots.contains { $0.id == identity }
    }

    func save(_ snapshot: SavedTripSnapshot) {
        guard snapshot.arrivalDate > Date() else { return }
        snapshots.removeAll { $0.id == snapshot.id }
        snapshots.append(snapshot)
        persist()
    }

    func remove(_ identity: String) {
        snapshots.removeAll { $0.id == identity }
        persist()
    }

    func refresh(now: Date = Date()) {
        let expirationCutoff = now.addingTimeInterval(-12 * 60 * 60)
        let active = snapshots.filter { $0.arrivalDate >= expirationCutoff }
        if active.count != snapshots.count {
            snapshots = active
            persist()
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(snapshots), forKey: storageKey)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to save trips."
        }
    }
}