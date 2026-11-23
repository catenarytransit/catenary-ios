import CoreLocation
import Foundation
import SwiftUI
import UserNotifications

/// A single journey selected for active guidance. It is independent of search results
/// and never changes the planner's history when opened from a notification.
struct TrackedJourney: Codable, Sendable {
    var snapshot: TripPlannerModel.SavedDirectionsJourney
    var startedAt: Date
}

@MainActor
final class ActiveJourneyStore: ObservableObject {
    static let shared = ActiveJourneyStore()

    @Published private(set) var active: TrackedJourney?
    @Published var showingDetails = false
    @Published var switchCandidate: TripPlannerModel.SavedDirectionsJourney?
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("active-journey.json")

    private init() {
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(TrackedJourney.self, from: data),
           !stored.snapshot.itinerary.legs.isEmpty {
            active = stored
        }
    }

    func start(_ snapshot: TripPlannerModel.SavedDirectionsJourney) {
        guard !snapshot.itinerary.legs.isEmpty else { return }
        if let active, active.snapshot.itinerary.identity != snapshot.itinerary.identity {
            switchCandidate = snapshot
            return
        }
        install(snapshot)
    }

    func confirmSwitch() {
        guard let snapshot = switchCandidate else { return }
        switchCandidate = nil
        install(snapshot)
    }

    private func install(_ snapshot: TripPlannerModel.SavedDirectionsJourney) {
        active = TrackedJourney(snapshot: snapshot, startedAt: Date())
        persist()
        JourneyNotifications.shared.requestPermissionForJourney()
        JourneyNotifications.shared.syncSoon()
    }

    func end() {
        active = nil
        switchCandidate = nil
        persist()
        JourneyNotifications.shared.syncSoon()
    }

    private func persist() {
        if let active {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(active).write(to: url, options: .atomic)
            } catch {
                NSLog("Unable to persist active journey: %@", error.localizedDescription)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

enum ActiveJourneyStage {
    case boarding(DirectionsLeg, Int, Bool)
    case riding(DirectionsLeg, Int)
    case finalStreet(Bool, Double?)
    case arriving(String)

    static func evaluate(
        _ snapshot: TripPlannerModel.SavedDirectionsJourney,
        now: Date,
        userCoordinate: CLLocationCoordinate2D?
    ) -> ActiveJourneyStage {
        let journey = snapshot.itinerary
        let legs = journey.legs
        let nextIndex = legs.firstIndex {
            guard let arrival = directionsDate($0.arrivalCurrentTime ?? $0.endTime) else { return true }
            return now < arrival
        }
        guard let current = nextIndex else {
            return .arriving(snapshot.destination?.name ?? legs.last?.to?.name ?? "")
        }
        let leg = legs[current]
        func remaining(_ raw: String?) -> Int {
            guard let at = directionsDate(raw) else { return 0 }
            return max(0, Int(ceil(at.timeIntervalSince(now) / 60)))
        }
        if leg.street {
            if let next = legs.dropFirst(current + 1).first(where: { !$0.street }) {
                return .boarding(next, remaining(next.departureCurrentTime), current > 0)
            }
            let endpoint = snapshot.destination?.coordinate ?? legs.last?.to?.location?.coordinate
            let meters: Double?
            if let userCoordinate, let endpoint {
                meters = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
                    .distance(from: CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude))
            } else {
                meters = nil
            }
            return .finalStreet(leg.mode.uppercased() != "WALK", meters)
        }
        let departure = directionsDate(leg.departureCurrentTime)
        if let departure, now >= departure {
            return .riding(leg, remaining(leg.arrivalCurrentTime))
        }
        return .boarding(leg, remaining(leg.departureCurrentTime), current > 0)
    }

    static func shouldShow(
        _ active: TrackedJourney,
        now: Date,
        userCoordinate: CLLocationCoordinate2D?
    ) -> Bool {
        guard let start = directionsDate(active.snapshot.itinerary.startTime) else { return false }
        if now >= start { return true }
        guard start.timeIntervalSince(now) <= 3 * 3600,
              let userCoordinate,
              let origin = active.snapshot.origin?.coordinate
                ?? active.snapshot.itinerary.legs.first?.from?.location?.coordinate else { return false }
        return CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude)) <= 5_000
    }

    /// Estimates leg completion from the timetable, without background GPS access.
    static func legProgress(_ itinerary: DirectionsItinerary, now: Date) -> (Int, Int, Int)? {
        let legs = itinerary.legs
        guard !legs.isEmpty else { return nil }
        let current = legs.firstIndex {
            guard let arrival = directionsDate($0.arrivalCurrentTime ?? $0.endTime) else { return true }
            return now < arrival
        } ?? (legs.count - 1)
        let leg = legs[current]
        let start = directionsDate(leg.departureCurrentTime) ?? directionsDate(leg.startTime)
        let end = directionsDate(leg.arrivalCurrentTime) ?? directionsDate(leg.endTime)
        guard let start, let end, end > start else { return (current + 1, legs.count, 0) }
        let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return (current + 1, legs.count, max(0, min(100, Int((fraction * 100).rounded()))))
    }
}

struct ActiveJourneyBar: View {
    let active: TrackedJourney
    let location: CLLocationCoordinate2D?
    let open: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if ActiveJourneyStage.shouldShow(active, now: context.date, userCoordinate: location) {
                Button(action: open) {
                    HStack(spacing: 6) {
                        guidance(ActiveJourneyStage.evaluate(active.snapshot, now: context.date, userCoordinate: location))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .padding(.horizontal, 12)
                    .background(.black)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journey.active.bar")
            }
        }
    }

    @ViewBuilder private func guidance(_ stage: ActiveJourneyStage) -> some View {
        switch stage {
        case let .boarding(leg, minutes, transfer):
            HStack(spacing: 4) {
                Text(leg.label).bold()
                Text(transfer ? "Next from" : "Departing")
                Text(leg.from?.name ?? "")
                Text("in \(minutes) min")
            }
        case let .riding(leg, minutes):
            Text("Alight at \(leg.to?.name ?? "") in \(minutes) min")
        case let .finalStreet(cycling, remaining):
            Image(systemName: cycling ? "bicycle" : "figure.walk")
            if let remaining {
                Text("\(directionsFormattedDistance(remaining)) remaining")
            } else {
                Text(cycling ? "Cycle to destination" : "Walk to destination")
            }
        case let .arriving(destination):
            Text("Arriving at \(destination)")
        }
    }
}

struct ActiveJourneyDetails: View {
    @ObservedObject var store: ActiveJourneyStore
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let active = store.active {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("\(active.snapshot.origin?.name ?? "Origin") → \(active.snapshot.destination?.name ?? "Destination")")
                                .font(.headline)
                            JourneyPreview(itinerary: active.snapshot.itinerary)
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                if let progress = ActiveJourneyStage.legProgress(active.snapshot.itinerary, now: context.date) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Leg \(progress.0) of \(progress.1)")
                                        ProgressView(value: Double(progress.2), total: 100)
                                            .accessibilityLabel("Journey progress")
                                    }
                                }
                            }
                            ForEach(active.snapshot.itinerary.legs.indices, id: \.self) { index in
                                let leg = active.snapshot.itinerary.legs[index]
                                HStack(spacing: 10) {
                                    LegModeIcon(leg: leg)
                                    VStack(alignment: .leading, spacing: 4) {
                                        if !leg.street { leg.badge }
                                        Text("\(leg.from?.name ?? "") → \(leg.to?.name ?? "")")
                                            .font(.subheadline)
                                        Text("\(directionsClock(leg.departureCurrentTime ?? leg.startTime)) – \(directionsClock(leg.arrivalCurrentTime ?? leg.endTime))")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                        }.padding(20)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button(role: .destructive) {
                            store.end()
                            close()
                        } label: {
                            Text("End").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .clipShape(Capsule())
                        .padding()
                    }
                } else {
                    Label("No active journey", systemImage: "tram")
                }
            }
            .navigationTitle("Active journey")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", action: close)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        close()
                        GlobalViewObject.home()
                    } label: {
                        Image(systemName: "house")
                    }.accessibilityLabel("Home")
                }
            }
        }
    }
}
