import Foundation
import SwiftUI

/// Save a complete, self-contained v2 itinerary rather than just one GTFS trip.
struct SavedRouteJourney: Codable, Identifiable {
    let id: String
    let journey: RouteV2Journey
    let originName: String
    let destinationName: String
    let savedAt: Date

    var departureDate: Date? { RouteV2Time.parse(journey.startTime) }
    var arrivalDate: Date? { RouteV2Time.parse(journey.endTime) }

    var dayKey: String { formatted("yyyy-MM-dd") }
    var dayLabel: String { formatted("EEEE, MMMM d, yyyy") }

    private func formatted(_ format: String) -> String {
        guard let departureDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale.current
        formatter.timeZone = journey.departureTimezone.flatMap(TimeZone.init(identifier:)) ?? .current
        return formatter.string(from: departureDate)
    }
}

@MainActor
final class SavedRouteJourneysStore: ObservableObject {
    @Published private(set) var journeys: [SavedRouteJourney] = []
    @Published private(set) var errorMessage: String?

    private let key = "catenary.saved-route-journeys.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let bytes = defaults.data(forKey: key) {
                journeys = try JSONDecoder().decode([SavedRouteJourney].self, from: bytes)
            }
        } catch {
            errorMessage = "Unable to read saved journeys."
        }
        refresh()
    }

    func contains(_ id: String) -> Bool { journeys.contains { $0.id == id } }

    func save(_ journey: RouteV2Journey) {
        guard let arrival = RouteV2Time.parse(journey.endTime), arrival > Date() else { return }
        let snapshot = SavedRouteJourney(
            id: journey.stableID,
            journey: journey,
            originName: journey.legs.first?.from?.name ?? "Origin",
            destinationName: journey.legs.last?.to?.name ?? "Destination",
            savedAt: Date()
        )
        journeys.removeAll { $0.id == snapshot.id }
        journeys.append(snapshot)
        persist()
    }

    func remove(_ identity: String) {
        journeys.removeAll { $0.id == identity }
        persist()
    }

    func refresh(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-12 * 60 * 60)
        let active = journeys.filter {
            guard let end = $0.arrivalDate else { return false }
            return end >= cutoff
        }
        if active.count != journeys.count {
            journeys = active
            persist()
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(journeys), forKey: key)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to save journeys."
        }
    }
}
