import SwiftUI

/// Full-screen counterpart of Compose's SavedJourneysScreen.
///
/// This deliberately uses PR #56's TripPlannerModel.savedJourneys rather than
/// maintaining a second, incompatible iOS storage format.
struct SavedJourneysScreen: View {
    @ObservedObject var model: TripPlannerModel
    let onBack: () -> Void
    let onOpen: (TripPlannerModel.SavedDirectionsJourney) -> Void

    @Environment(\.scenePhase) private var scenePhase

    private struct Row: Identifiable {
        let id: String
        let snapshot: TripPlannerModel.SavedDirectionsJourney

        var itinerary: DirectionsItinerary { snapshot.itinerary }
        var departure: Date { directionsDate(itinerary.startTime) ?? .distantFuture }

        var dayKey: String { formattedDeparture("yyyy-MM-dd") }
        var dayLabel: String { formattedDeparture("EEEE, MMMM d, yyyy") }
        var originName: String {
            snapshot.origin?.name ?? itinerary.legs.first?.from?.name ?? "Origin"
        }
        var destinationName: String {
            snapshot.destination?.name ?? itinerary.legs.last?.to?.name ?? "Destination"
        }

        private func formattedDeparture(_ format: String) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = directionsTimeZone(itinerary.departureTimezone)
            formatter.locale = .autoupdatingCurrent
            return formatter.string(from: departure)
        }
    }

    private var rows: [Row] {
        model.savedJourneys.map { Row(id: $0.key, snapshot: $0.value) }
            .sorted { $0.departure < $1.departure }
    }

    private var days: [String] {
        Array(Set(rows.map(\.dayKey))).sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    CatenaryUnavailableView {
                        Label("No journeys saved", systemImage: "star")
                    } description: {
                        Text("Star a journey in the planner to find it here.")
                    } actions: {
                        Button("Back to map", action: onBack)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(days, id: \.self) { day in
                            Section {
                                ForEach(rows.filter { $0.dayKey == day }) { row in
                                    Button {
                                        onOpen(row.snapshot)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("\(row.originName) → \(row.destinationName)")
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(2)
                                            JourneyPreview(itinerary: row.itinerary, compact: false)
                                        }
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("trips.saved.\(row.id)")
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button("Remove", systemImage: "star.slash", role: .destructive) {
                                            model.removeSavedJourney(id: row.id)
                                        }
                                        .disabled(model.savingJourney)
                                    }
                                }
                            } header: {
                                Text(rows.first(where: { $0.dayKey == day })?.dayLabel ?? "")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("trips.back")
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onAppear { model.pruneExpiredSavedJourneys() }
        .catenaryOnChange(of: scenePhase) { _, phase in
            if phase == .active { model.pruneExpiredSavedJourneys() }
        }
    }
}
