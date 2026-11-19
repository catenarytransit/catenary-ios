import SwiftUI

/// Full-screen counterpart of Compose's SavedJourneysScreen.
/// The list is grouped by the trip's departure date and each snapshot can be reopened.
struct SavedTripsScreen: View {
    let onBack: () -> Void

    @EnvironmentObject private var store: SavedTripsStore
    @EnvironmentObject private var savedRoutes: SavedRouteJourneysStore
    @Environment(\.scenePhase) private var scenePhase

    private var orderedSnapshots: [SavedTripSnapshot] {
        store.snapshots.sorted {
            if $0.departure != $1.departure { return $0.departure < $1.departure }
            return $0.id < $1.id
        }
    }

    private var orderedRoutes: [SavedRouteJourney] {
        savedRoutes.journeys.sorted { $0.journey.startTime < $1.journey.startTime }
    }

    private var days: [(String, [SavedTripSnapshot])] {
        let grouped = Dictionary(grouping: orderedSnapshots, by: \.dayKey)
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if orderedSnapshots.isEmpty && orderedRoutes.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(Dictionary(grouping: orderedRoutes, by: \.dayKey).keys.sorted()), id: \.self) { day in
                            Section {
                                ForEach(orderedRoutes.filter { $0.dayKey == day }) { snapshot in
                                    NavigationLink {
                                        RouteV2JourneyDetails(journey: snapshot.journey)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("\(snapshot.originName) → \(snapshot.destinationName)")
                                                .font(.headline)
                                            RouteV2JourneyPreview(journey: snapshot.journey)
                                        }
                                        .padding(.vertical, 8)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("Remove", systemImage: "star.slash", role: .destructive) {
                                            savedRoutes.remove(snapshot.id)
                                        }
                                    }
                                }
                            } header: {
                                Text(orderedRoutes.first(where: { $0.dayKey == day })?.dayLabel ?? "")
                            }
                        }
                        ForEach(days.indices, id: \.self) { index in
                            let trips = days[index].1
                            Section {
                                ForEach(trips) { trip in
                                    NavigationLink(value: trip) {
                                        SavedTripPreview(trip: trip)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("Remove", systemImage: "star.slash", role: .destructive) {
                                            store.remove(trip.id)
                                        }
                                    }
                                }
                            } header: {
                                Text(trips.first?.dayLabel ?? "")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .overlay(alignment: .top) {
                        if let error = store.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("saved-trips.back")
                }
            }
            .navigationDestination(for: SavedTripSnapshot.self) { trip in
                SavedTripDetailsScreen(trip: trip)
            }
            .onAppear {
                store.refresh()
                savedRoutes.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.refresh()
                    savedRoutes.refresh()
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No journeys saved", systemImage: "star")
        } description: {
            Text("Save a journey or trip with the star. Saved journeys appear here and are removed 12 hours after arrival.")
        } actions: {
            Button("Back to map", action: onBack)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct SavedTripPreview: View {
    let trip: SavedTripSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(trip.originName) → \(trip.destinationName)")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(trip.routeLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color(catenaryHex: trip.routeColor) ?? .secondary.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                if let headsign = trip.headsign {
                    Text(headsign)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trip.departureLabel)
                    .fontWeight(.bold)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(trip.arrivalLabel)
                    .fontWeight(.bold)
                Spacer()
                Text("\(trip.durationMinutes) min")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct SavedTripDetailsScreen: View {
    let trip: SavedTripSnapshot
    @EnvironmentObject private var store: SavedTripsStore

    var body: some View {
        VStack(spacing: 0) {
            SingleTripScreen(selection: trip.selection)
            Button {
                if store.contains(trip.id) {
                    store.remove(trip.id)
                } else {
                    store.save(trip)
                }
            } label: {
                Label(
                    store.contains(trip.id) ? "Remove saved trip" : "Save trip",
                    systemImage: store.contains(trip.id) ? "star.fill" : "star"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .navigationTitle("Trip details")
        .navigationBarTitleDisplayMode(.inline)
    }
}