import CoreLocation
import SwiftUI

private struct RouteV2Endpoint {
    let name: String
    let latitude: Double
    let longitude: Double
}

@MainActor
struct RouteV2PlannerScreen: View {
    let initialCoordinate: CLLocationCoordinate2D?
    let onBack: () -> Void

    @StateObject private var routing = RouteV2Session()
    @StateObject private var searchModel = SearchViewModel()
    @State private var origin: RouteV2Endpoint?
    @State private var destination: RouteV2Endpoint?
    @State private var editingOrigin = false
    @State private var editingDestination = false
    @State private var originText = ""
    @State private var destinationText = ""
    @State private var selectedJourney: RouteV2Journey?
    @State private var arriveBy = false

    private var canPlan: Bool { origin != nil && destination != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                endpointFields
                if editingOrigin || editingDestination {
                    searchContent
                } else {
                    resultsContent
                }
            }
            .navigationTitle("Plan a journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedJourney != nil },
                set: { if !$0 { selectedJourney = nil } }
            )) {
                if let journey = selectedJourney {
                    RouteV2JourneyDetails(journey: journey)
                }
            }
        }
        .task {
            // Starts before the user can submit endpoints or calculate a route.
            routing.connect()
            if origin == nil, let location = initialCoordinate {
                origin = RouteV2Endpoint(
                    name: "Current location",
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                originText = "Current location"
            }
        }
        .onDisappear {
            routing.close()
        }
    }

    private var endpointFields: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "circle")
                    .foregroundStyle(.green)
                TextField("Origin", text: $originText)
                    .onTapGesture { startEditing(origin: true) }
                    .onChange(of: originText) { _, value in
                        guard editingOrigin else { return }
                        origin = nil
                        updateSearch(query: value)
                    }
                    .accessibilityIdentifier("route.origin")
            }
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.red)
                TextField("Destination", text: $destinationText)
                    .onTapGesture { startEditing(origin: false) }
                    .onChange(of: destinationText) { _, value in
                        guard editingDestination else { return }
                        destination = nil
                        updateSearch(query: value)
                    }
                    .accessibilityIdentifier("route.destination")
            }
            HStack {
                Toggle("Arrive by", isOn: $arriveBy)
                    .font(.subheadline)
                Spacer()
                Button("Find connections") { plan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlan || routing.loading)
            }
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var searchContent: some View {
        CatenarySearchResultsView(
            viewModel: searchModel,
            onCypressClick: { feature in
                guard let coord = feature.coordinate else { return }
                select(RouteV2Endpoint(
                    name: feature.properties?.name ?? "Place",
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ))
            },
            onStopClick: { ranking in
                guard let selected = searchModel.rows.compactMap({ row -> SearchStopInfo? in
                    if case let .stop(value, stop, _, _, _, _) = row,
                       value.chateau == ranking.chateau, value.gtfsID == ranking.gtfsID {
                        return stop
                    }
                    return nil
                }).first, let point = selected.point else { return }
                select(RouteV2Endpoint(name: selected.name ?? "Stop", latitude: point.y, longitude: point.x))
            },
            onRouteClick: { _ in },
            onOsmStationClick: { station in
                guard let point = station.point else { return }
                select(RouteV2Endpoint(
                    name: station.name ?? "Station",
                    latitude: point.y,
                    longitude: point.x
                ))
            },
            onRecentClick: { _ in }
        )
    }

    @ViewBuilder
    private var resultsContent: some View {
        if routing.loading && routing.journeys.isEmpty {
            ProgressView("Finding connections")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = routing.errorMessage {
            ContentUnavailableView(
                "Unable to plan journey",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if routing.journeys.isEmpty {
            ContentUnavailableView(
                "Where would you like to go?",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                description: Text("Select an origin and destination to find connections.")
            )
        } else {
            List(routing.journeys, id: \.stableID) { journey in
                Button {
                    selectedJourney = journey
                } label: {
                    RouteV2JourneyPreview(journey: journey)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay(alignment: .bottom) {
                if routing.loading { ProgressView().padding(12).background(.regularMaterial, in: Capsule()) }
            }
        }
    }

    private func startEditing(origin: Bool) {
        editingOrigin = origin
        editingDestination = !origin
        searchModel.query = origin ? originText : destinationText
        updateSearch(query: searchModel.query)
    }

    private func updateSearch(query: String) {
        guard editingOrigin || editingDestination else { return }
        let center = initialCoordinate ?? CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)
        searchModel.query = query
        searchModel.search(query: query, userLocation: initialCoordinate, mapCenter: center)
    }

    private func select(_ selected: RouteV2Endpoint) {
        if editingOrigin {
            origin = selected
            originText = selected.name
        } else {
            destination = selected
            destinationText = selected.name
        }
        editingOrigin = false
        editingDestination = false
        searchModel.reset()
        if canPlan { plan() }
    }

    private func plan() {
        guard let origin, let destination else { return }
        editingOrigin = false
        editingDestination = false
        routing.route(
            from: (origin.latitude, origin.longitude),
            to: (destination.latitude, destination.longitude),
            arriveBy: arriveBy
        )
    }
}

/// The summary follows Compose's endpoint / transit clocks / delay ordering.
struct RouteV2JourneyPreview: View {
    let journey: RouteV2Journey

    private var boarding: RouteV2Leg? { journey.boardingLeg }
    private var alighting: RouteV2Leg? { journey.alightingLeg }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(RouteV2Time.clock(journey.startTime, timezoneID: journey.departureTimezone))
                    .fontWeight(.bold)
                if let boarding, boarding.startTime != journey.startTime {
                    Text(RouteV2Time.clock(boarding.departureTime, timezoneID: boarding.from?.timezone))
                        .foregroundStyle(.secondary)
                }
                if let delay = RouteV2Time.delay(boarding?.departureEvent?.delaySeconds) {
                    Text(delay)
                        .foregroundStyle((boarding?.departureEvent?.delaySeconds ?? 0) > 0 ? Color.orange : Color.secondary)
                        .accessibilityLabel("Departure delay \(delay)")
                }
                Spacer(minLength: 4)
                Text("\(journey.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let alighting, alighting.endTime != journey.endTime {
                    Text(RouteV2Time.clock(alighting.arrivalTime, timezoneID: alighting.to?.timezone))
                        .foregroundStyle(.secondary)
                }
                Text(RouteV2Time.clock(journey.endTime, timezoneID: journey.arrivalTimezone))
                    .fontWeight(.bold)
            }
            .font(.subheadline.monospacedDigit())
            HStack(spacing: 8) {
                ForEach(journey.legs) { leg in
                    Label(leg.label, systemImage: leg.street ? "figure.walk" : "tram.fill")
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

struct RouteV2JourneyDetails: View {
    let journey: RouteV2Journey
    @EnvironmentObject private var savedRoutes: SavedRouteJourneysStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                RouteV2JourneyPreview(journey: journey)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                ForEach(journey.legs) { leg in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(leg.label, systemImage: leg.street ? "figure.walk" : "tram.fill")
                            .font(.headline)
                        if leg.cancelled == true {
                            Label("Cancelled", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                        RouteV2StopRow(
                            name: leg.from?.name ?? "Departure",
                            time: leg.departureTime,
                            event: leg.departureEvent,
                            timezone: leg.from?.timezone,
                            quay: leg.from?.estimatedQuay ?? leg.from?.plannedQuay,
                            skipped: leg.from?.notServicedStop == true
                        )
                        ForEach(leg.intermediateStops ?? []) { stop in
                            RouteV2StopRow(
                                name: stop.name ?? "Stop",
                                time: stop.serviceDeparture?.effectiveTime ?? stop.departure ?? stop.arrival,
                                event: stop.serviceDeparture ?? stop.serviceArrival,
                                timezone: stop.timezone,
                                quay: stop.estimatedQuay ?? stop.plannedQuay,
                                skipped: stop.notServicedStop == true
                            )
                        }
                        RouteV2StopRow(
                            name: leg.to?.name ?? "Arrival",
                            time: leg.arrivalTime,
                            event: leg.arrivalEvent,
                            timezone: leg.to?.timezone,
                            quay: leg.to?.estimatedQuay ?? leg.to?.plannedQuay,
                            skipped: leg.to?.notServicedStop == true
                        )
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Journey details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if savedRoutes.contains(journey.stableID) {
                        savedRoutes.remove(journey.stableID)
                    } else {
                        savedRoutes.save(journey)
                    }
                } label: {
                    Image(systemName: savedRoutes.contains(journey.stableID) ? "star.fill" : "star")
                }
                .accessibilityLabel(savedRoutes.contains(journey.stableID) ? "Remove saved journey" : "Save journey")
            }
        }
    }
}

private struct RouteV2StopRow: View {
    let name: String
    let time: String?
    let event: RouteV2Event?
    let timezone: String?
    let quay: String?
    let skipped: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(RouteV2Time.clock(time, timezoneID: timezone))
                    .font(.subheadline.monospacedDigit())
                if let delay = RouteV2Time.delay(event?.delaySeconds) {
                    Text(delay)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle((event?.delaySeconds ?? 0) > 0 ? Color.orange : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(width: 54, alignment: .trailing)
            Circle().fill(skipped ? Color.gray : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline)
                    .strikethrough(skipped)
                if let quay { Text("Platform \(quay)").font(.caption).foregroundStyle(.secondary) }
                if skipped { Text("Not serviced").font(.caption).foregroundStyle(.red) }
            }
            Spacer(minLength: 0)
        }
    }
}
