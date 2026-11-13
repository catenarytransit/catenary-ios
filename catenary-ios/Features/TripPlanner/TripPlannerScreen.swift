import CoreLocation
import SwiftUI

private struct SearchDebounceKey: Equatable {
    let origin: DirectionsLocation?
    let destination: DirectionsLocation?
    let time: Date
    let now: Bool
    let arriveBy: Bool
    let options: DirectionsOptions
}

struct TripPlannerScreen: View {
    @ObservedObject var model: TripPlannerModel
    @ObservedObject var locationManager: LocationManager
    @EnvironmentObject private var navigator: viewObject
    @StateObject private var search = SearchViewModel()
    @FocusState private var focused: Bool?
    @State private var showsOptions = false
    @State private var showsTimeSheet = false
    @State private var recent: [DirectionsLocation] = []
    @State private var skeletonPulse = false
    @State private var pagingDirection: ConnectionDirection?
    @State private var visibleJourneys: [String: CGRect] = [:]
    @State private var resultsHeight: CGFloat = 0
    @State private var pagingAnchor: String?

    private var fullscreenDetails: Binding<Bool> {
        Binding(get: { model.details && !model.usingMap }, set: { presented in
            if !presented && !model.usingMap { model.details = false }
        })
    }
    @AppStorage("usUnits") private var usUnits = false
    private let recentKey = "tripPlanner.recent.v1"

    private var debounceKey: SearchDebounceKey {
        SearchDebounceKey(origin: model.origin, destination: model.destination, time: model.time,
            now: model.now, arriveBy: model.arriveBy, options: model.options)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !model.details { inputCard }
            if let picking = model.mapPicking {
                Label("Move the map to choose a location", systemImage: "mappin")
                    .font(.subheadline)
                HStack {
                    Button("Cancel") { model.mapPicking = nil; model.editing = picking; navigator.presDetent = .height(350) }
                    Spacer()
                    Button("Use this location") {
                        let center = navigator.visibleCoordinateBounds.catenarySearchCenter
                        model.choose(picking, location: DirectionsLocation(name: String(format: "%.6f, %.6f", center.latitude, center.longitude), coordinate: center, mapPicked: true))
                        navigator.presDetent = .height(350)
                    }.buttonStyle(.borderedProminent)
                }
            } else if let editing = model.editing {
                endpointSearch(editing)
            } else if model.details, let itinerary = model.chosen {
                mapModeHeader(itinerary)
            } else {
                results
            }
        }
        .padding(.horizontal, 12)
        .onAppear {
            model.open(currentLocation: locationManager.lastKnownLocation); loadRecent()
            markScreenshotReady()
        }
        .catenaryOnChange(of: model.loading) { _, loading in
            if loading { pagingAnchor = nil; pagingDirection = nil }
            markScreenshotReady()
        }
        .onDisappear { if !model.details { model.leave() }; search.reset() }
        .catenaryOnChange(of: focused) { _, endpoint in
            if let endpoint { model.beginEditing(endpoint); navigator.presDetent = .large; performSearch(endpoint) }
        }
        .catenaryOnChange(of: model.editing) { _, endpoint in
            if endpoint == nil { focused = nil; search.reset() }
        }
        .catenaryOnChange(of: locationManager.lastKnownLocation?.latitude) { _, _ in
            model.resolveCurrentOrigin(locationManager.lastKnownLocation)
        }
        .catenaryOnChange(of: model.usingMap) { _, usingMap in
            navigator.presDetent = .height(350)
        }
        .task(id: debounceKey) {
            guard model.canSearch, !model.searched else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, model.canSearch, !model.searched else { return }
            model.search()
        }
        .fullScreenCover(isPresented: fullscreenDetails) {
            if let itinerary = model.chosen {
                details(itinerary)
                    .foregroundStyle(Color.primary)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .sheet(isPresented: $showsOptions) { optionsSheet }
        .sheet(isPresented: $showsTimeSheet) {
            TripPlannerTimeSheet(time: model.time, isNow: model.now, arriveBy: model.arriveBy) { time, isNow, arriveBy in
                model.arriveBy = arriveBy; model.now = isNow; model.time = time
            }
            .presentationDetents([.height(480)])
        }
    }
    private func markScreenshotReady() {
#if DEBUG || SCREENSHOT_AUTOMATION
        guard let screen = ScreenshotLaunchConfiguration.current.plannerScreen else { return }
        ScreenshotReadiness.shared.setPlannerStatus("screen=\(screen) loading=\(model.loading) journeys=\(model.itineraries.count) details=\(model.details) selected=\(model.selected) error=\(model.error ?? "none")")
        guard !model.loading else { return }
        if let error = model.error {
            ScreenshotReadiness.shared.failPlanner("Routing failed: \(error)")
            return
        }
        guard model.itineraries.count >= 3 else {
            ScreenshotReadiness.shared.failPlanner("Routing returned \(model.itineraries.count) journeys; need at least three")
            return
        }
        guard screen == "results" ? !model.details : model.details && model.selected == (Int(screen) ?? 0) - 1 else { return }
        // Route layers and the camera fit are installed on the next SwiftUI update.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ScreenshotReadiness.shared.markPlannerReady()
        }
#endif
    }

    private var inputCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                DirectionsEndpointRail(originIsCurrent: model.origin?.isCurrentLocation == true,
                    destinationIsCurrent: model.destination?.isCurrentLocation == true)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    endpointField(true)
                    Divider()
                    endpointField(false)
                }
                Button { focused = nil; search.reset(); model.swap() } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 44, height: 44)
                }.accessibilityLabel("Swap origin and destination")
            }
            Divider()
            HStack(spacing: 12) {
                timeButton
                Divider().frame(height: 24)
                Button { focused = nil; showsOptions = true } label: {
                    Image(systemName: model.options.cycling ? "bicycle" : "figure.walk")
                        .font(.body)
                        .frame(width: 24, height: 24)
                        .overlay(alignment: .topTrailing) {
                            if model.options != DirectionsOptions() {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: 3, y: -3)
                            }
                        }
                }
                .accessibilityLabel(model.options.cycling ? "Cycling options" : "Walking options")
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private var timeButton: some View {
        Button { focused = nil; showsTimeSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: model.now ? "clock.badge.checkmark" : "calendar.badge.clock")
                Text(timeLabel).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1)
                if model.now {
                    Text("Now").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var timeLabel: String {
        let prefix = L10n.string(model.arriveBy ? "Arrival" : "Departure")
        let reference = model.now ? Date() : model.time
        return "\(prefix) \(tripPlannerDayLabel(reference)) \(tripPlannerClockLabel(reference))"
    }
    private func endpointField(_ origin: Bool) -> some View {
        TextField(origin ? "Origin" : "Destination", text: Binding(
            get: { origin ? model.originText : model.destinationText },
            set: { model.edit(origin, text: $0); performSearch(origin) }
        ))
        .focused($focused, equals: origin)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onSubmit {
            if model.canSearch {
                focused = nil; model.search(); navigator.presDetent = .height(350)
            }
        }
        .frame(minHeight: 40)
    }
    private func performSearch(_ origin: Bool) {
        let query = origin ? model.originText : model.destinationText
        search.query = query
        search.search(query: query, userLocation: locationManager.lastKnownLocation,
            mapCenter: navigator.visibleCoordinateBounds.catenarySearchCenter)
    }
    private func choose(_ origin: Bool, _ location: DirectionsLocation) {
        focused = nil; search.reset(); model.choose(origin, location: location)
        remember(location)
        navigator.presDetent = .height(350)
    }
    private func loadRecent() {
        guard let data = UserDefaults.standard.data(forKey: recentKey),
              let decoded = try? JSONDecoder().decode([DirectionsLocation].self, from: data) else { return }
        recent = decoded.filter(\.isValid)
    }
    /// Only free-form chosen places are worth remembering; pins and current-location are already one tap away.
    private func remember(_ location: DirectionsLocation) {
        guard !location.isCurrentLocation, !location.isMapLocation else { return }
        let updated = Array((([location] + recent.filter {
            $0.name != location.name || abs($0.lat - location.lat) > 0.00001 || abs($0.lon - location.lon) > 0.00001
        })).prefix(20))
        recent = updated
        if let data = try? JSONEncoder().encode(updated) { UserDefaults.standard.set(data, forKey: recentKey) }
    }
    private func endpointSearch(_ origin: Bool) -> some View {
        let query = origin ? model.originText : model.destinationText
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button {
                    if let coordinate = locationManager.lastKnownLocation {
                        choose(origin, DirectionsLocation(name: "Current location", coordinate: coordinate, current: true))
                    } else { locationManager.checkLocationAuthorization() }
                } label: { Label("Current location", systemImage: "location.fill").padding() }
                Button {
                    focused = nil; search.reset(); model.editing = nil; model.mapPicking = origin
                    navigator.presDetent = .height(350)
                } label: { Label("Choose on map", systemImage: "mappin.and.ellipse").padding() }
                if let coordinate = parseDirectionsCoordinate(query) {
                    Button { choose(origin, coordinate) } label: { Label(coordinate.name, systemImage: "number").padding() }
                }
                if search.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
                if query.isEmpty {
                    ForEach(Array(recent.prefix(12).enumerated()), id: \.offset) { _, location in
                        Button { choose(origin, location) } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").frame(width: 24).foregroundStyle(.secondary)
                                Text(location.name)
                                Spacer(minLength: 4)
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
                ForEach(search.rows) { row in
                    if let location = row.directionsLocation {
                        Button { choose(origin, location) } label: {
                            HStack {
                                Image(systemName: row.directionsSystemImage)
                                    .frame(width: 24).foregroundStyle(.secondary)
                                    .padding()
                                plannerSearchRow(row)
                                Spacer(minLength: 4)
                                if let current = locationManager.lastKnownLocation {
                                    Text(directionsFormattedDistance(CLLocation(latitude: location.lat, longitude: location.lon).distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
    @ViewBuilder private func plannerSearchRow(_ row: SearchRow) -> some View {
        switch row {
        case let .cypress(feature, _): CypressSearchResultRow(feature: feature)
        case let .osmStation(station, _): OsmStationSearchResultRow(station: station)
        case let .stop(_, stop, routes, agencies, _, _):
            StopSearchResultRow(stop: stop, routes: routes, agencyNames: agencies, distanceMetres: nil)
        case .route: EmptyView()
        }
    }
    private func dateHeading(for index: Int) -> String? {
        guard index > 0, model.itineraries.indices.contains(index) else { return nil }
        guard let previous = directionsDate(model.itineraries[index - 1].startTime),
              let date = directionsDate(model.itineraries[index].startTime) else { return nil }
        guard !Calendar.current.isDate(previous, inSameDayAs: date) else { return nil }
        return date.formatted(date: .complete, time: .omitted)
    }
    private var results: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 8) {
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary).padding()
                    Button("Try again") { model.search() }
                } else if model.searched, !model.loading, model.itineraries.isEmpty {
                    Label("No journeys found. Try another time or increase the access limits.", systemImage: "tram")
                        .padding()
                }
                connectionEdge(earlier: true)
                if model.loading, model.itineraries.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in connectionSkeleton }
                }
                ForEach(Array(model.itineraries.enumerated()), id: \.element.identity) { index, itinerary in
                    VStack(alignment: .leading, spacing: 4) {
                        if let heading = dateHeading(for: index) {
                            Text(heading).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                        Button {
                            model.selectJourney(itinerary)
                            navigator.presDetent = .height(350)
                        } label: { JourneyPreview(itinerary: itinerary) }
                        .buttonStyle(.plain)
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: JourneyBoundsKey.self,
                            value: [itinerary.identity: geometry.frame(in: .named("connections"))])
                    })
                }
                connectionEdge(earlier: false)
            }
        }
        .coordinateSpace(name: "connections")
        .catenaryOnGeometryChange(for: CGFloat.self) { $0.size.height } action: { _, height in resultsHeight = height }
        .onPreferenceChange(JourneyBoundsKey.self) { bounds in
            visibleJourneys = bounds
            requestVisiblePage()
        }
        .simultaneousGesture(DragGesture().onChanged { gesture in
            guard abs(gesture.translation.height) > 20 else { return }
            pagingDirection = gesture.translation.height > 0 ? .before : .after
            requestVisiblePage()
        })
        .catenaryOnChange(of: model.itineraries.first?.identity) { _, _ in
            if let pagingAnchor {
                proxy.scrollTo(pagingAnchor, anchor: .top)
                self.pagingAnchor = nil
            }
        }
        }
    }
    private func requestVisiblePage() {
        guard !model.screenshotAutomation, model.error == nil, !model.loading else { return }
        let visible = model.itineraries.indices.filter {
            guard let frame = visibleJourneys[model.itineraries[$0].identity] else { return false }
            return frame.maxY > 0 && frame.minY < resultsHeight
        }
        if pagingDirection == .before, (visible.first ?? Int.max) <= 1, model.canLoadEarlier {
            pagingAnchor = visible.first.map { model.itineraries[$0].identity }
            pagingDirection = nil
            model.loadConnections(earlier: true)
        } else if pagingDirection == .after, (visible.last ?? -1) >= model.itineraries.count - 2, model.canLoadLater {
            pagingDirection = nil
            model.loadConnections(earlier: false)
        }
    }
    /// Retrying a failed page keeps the current results and cursor intact.
    private func connectionEdge(earlier: Bool) -> some View {
        let busy = earlier ? model.earlierLoading : model.laterLoading
        let canRetry = model.error != nil && (earlier ? model.canLoadEarlier : model.canLoadLater)
        return Group {
            if busy {
                ProgressView().frame(maxWidth: .infinity).padding(8)
            } else if canRetry {
                Button { model.loadConnections(earlier: earlier) } label: { Image(systemName: "arrow.clockwise") }
                    .frame(maxWidth: .infinity).padding(8)
            }
        }
    }
    private var connectionSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).frame(width: 140, height: 18)
            RoundedRectangle(cornerRadius: 6).frame(height: 28)
        }
        .foregroundStyle(Color.secondary.opacity(skeletonPulse ? 0.65 : 0.25))
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { skeletonPulse = true }
        }
    }
    /// The same summary and controls remain available above the map and in fullscreen details.
    private func mapModeHeader(_ itinerary: DirectionsItinerary) -> some View {
        VStack {
            journeySummary(itinerary)
            Spacer(minLength: 0)
        }
    }
    private func summaryAction(_ label: String, icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 2)
        }
        .buttonStyle(.plain).foregroundStyle(Color.primary)
        .accessibilityLabel(label).disabled(!enabled)
    }
    private func journeySummary(_ itinerary: DirectionsItinerary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryAction("Journeys", icon: "arrow.backward") { model.details = false }
            VStack(alignment: .leading, spacing: 0) {
                Text("\(model.originText) → \(model.destinationText)")
                    .font(.headline).lineLimit(2).padding(.horizontal, 12).padding(.top, 12)
                JourneyPreview(itinerary: itinerary)
                Color.clear.frame(height: 12)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 12) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let saved = model.savedJourneys[itinerary.identity] != nil
                        summaryAction(saved ? "Unsave journey" : "Save journey", icon: saved ? "star.fill" : "star",
                            enabled: !model.savingJourney && (saved || itinerary.canBeSaved)) { model.toggleSavedJourney() }
                    }
                    if !model.streetOnly {
                        summaryAction(model.usingMap ? "List" : "Map", icon: model.usingMap ? "list.bullet" : "map") {
                            model.mapMode.toggle()
                        }
                    }
                }.padding(.leading, 12).offset(y: 22)
            }
            .padding(.bottom, 22)
            if let error = model.saveError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private func details(_ itinerary: DirectionsItinerary) -> some View {
        VStack(spacing: 4) {
            journeySummary(itinerary).padding(.horizontal, 20).padding(.top, 4)
            ScrollView {
                let legs = itinerary.detailLegs
                LazyVStack(alignment: .leading, spacing: 12) {
                    DirectionsJourneyEndpoint(name: model.originText, first: true)
                    ForEach(legs.indices, id: \.self) { index in
                        DirectionsLegView(leg: legs[index])
                    }
                    DirectionsJourneyEndpoint(name: model.destinationText, first: false)
                }.padding(12)
            }
        }
    }
    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Toggle("Cycle to and from transit", isOn: $model.options.cycling)
                Section("Speed") {
                    Text("Walking pace: \(model.options.walkingPace / 60, specifier: "%.1f") min/km")
                    Slider(value: $model.options.walkingPace, in: 240...1800, step: 30)
                    Text("Cycling speed: \(model.options.cyclingKmh, specifier: "%.0f") km/h")
                    Slider(value: $model.options.cyclingKmh, in: 5...40, step: 1)
                }
                Section("Maximum travel time") {
                    limit("To first stop", value: $model.options.accessSeconds)
                    limit("From last stop", value: $model.options.egressSeconds)
                    limit("Direct walk or cycle", value: $model.options.directSeconds)
                }
            }
            .navigationTitle("Travel options")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsOptions = false } } }
        }
    }
    private func limit(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue / 60)) min")
            // Match Edelweiss's 1...3600-second budget contract.
            Slider(value: value, in: 60...3600, step: 60)
        }
    }
}

extension SearchRow {
    var directionsSystemImage: String {
        switch self {
        case .cypress: return "mappin.and.ellipse"
        case .stop: return "tram.fill"
        case .osmStation: return "building.2.fill"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
    var directionsLocation: DirectionsLocation? {
        let result: DirectionsLocation?
        switch self {
        case let .cypress(feature, _):
            result = feature.coordinate.map { DirectionsLocation(name: feature.properties?.name ?? "Location", coordinate: $0) }
        case let .stop(_, stop, _, _, _, _):
            result = stop.point.map { DirectionsLocation(name: stop.name ?? "Stop", lat: $0.y, lon: $0.x) }
        case let .osmStation(station, _):
            result = station.point.map { DirectionsLocation(name: station.name ?? "Station", lat: $0.y, lon: $0.x) }
        case .route: result = nil
        }
        return result?.isValid == true ? result : nil
    }
}

func directionsFormattedDistance(_ meters: Double) -> String {
    TransitFormatting.distance(meters, useImperial: UserDefaults.standard.bool(forKey: "usUnits"))
}
func directionsClock(_ time: String?) -> String {
    guard let date = directionsDate(time) else { return "—" }
    return date.formatted(date: .omitted, time: .shortened)
}

struct JourneyPreview: View {
    let itinerary: DirectionsItinerary
    var compact = false
    var body: some View {
        let times = itinerary.previewTimeGroups
        VStack(spacing: compact ? 0 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                timeGroup(times.departure)
                Spacer(minLength: 2)
                Text(directionsDurationLabel(itinerary.seconds)).font(.subheadline.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                timeGroup(times.arrival)
            }.monospacedDigit()
            if !compact {
                GeometryReader { proxy in
                    let legs = itinerary.previewLegs
                    let width = max(proxy.size.width, CGFloat(directionsTimelineMinimums(legs).reduce(0, +)))
                    let widths = directionsTimelineWidths(legs, width: Double(width))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(legs.indices, id: \.self) { index in
                                DirectionsTimelineSegment(leg: legs[index], trailing: index == legs.count - 1 && index > 0)
                                    .frame(width: CGFloat(widths[index]))
                            }
                        }
                    }
                }.frame(height: 44).transition(.opacity)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.22), value: compact)
    }
    private func timeGroup(_ markers: [DirectionsTimeMarker]) -> some View {
        HStack(spacing: 4) {
            ForEach(markers.indices, id: \.self) { index in
                Text(directionsClock(markers[index].time))
                    .font(markers[index].transit ? .subheadline.bold() : .caption)
                    .foregroundStyle(markers[index].transit ? Color.primary : Color.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

private struct DirectionsTimelineSegment: View {
    let leg: DirectionsLeg
    let trailing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if !(trailing && leg.street) { LegModeIcon(leg: leg, preview: true) }
                Canvas { context, size in
                    if leg.street {
                        // Round dots match the Android timeline's walk/bike connector.
                        let radius: CGFloat = 1.5, spacing: CGFloat = 7
                        var x = radius
                        while x + radius <= size.width {
                            let dot = Path(ellipseIn: CGRect(x: x - radius, y: size.height / 2 - radius, width: radius * 2, height: radius * 2))
                            context.fill(dot, with: .color(leg.color))
                            x += spacing
                        }
                    } else {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: size.height / 2))
                        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        context.stroke(line, with: .color(leg.color), lineWidth: 2)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if trailing && leg.street { LegModeIcon(leg: leg, preview: true) }
            }.frame(height: 22)
            if leg.street {
                Text("\(Int(ceil(leg.seconds / 60)))′")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else { leg.routeBadge(compact: true) }
            Spacer(minLength: 0)
        }.padding(.trailing, 4).clipped().foregroundStyle(Color.primary)
    }
}

func directionsDurationLabel(_ seconds: Double) -> String {
    let minutes = Int(ceil(seconds / 60))
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
}

private struct JourneyBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Every row stretches its rail to its measured height, including wrapped station names.
private struct DirectionsConnectionRow<Content: View>: View {
    var color: Color = .primary
    var time = ""
    var platform: String? = nil
    var pearl = false
    var first = false
    var last = false
    var dotted = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(time).font(.system(size: 14, weight: .bold)).monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            Color.clear.frame(width: 20)
                .overlay(GeometryReader { geometry in
                    Canvas { context, size in
                        let x = size.width / 2
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: first ? size.height / 2 : 0))
                        path.addLine(to: CGPoint(x: x, y: last ? size.height / 2 : size.height))
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: dotted ? [2, 4] : []))
                        if pearl {
                            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: size.height / 2 - 4, width: 8, height: 8)), with: .color(color))
                        }
                    }.frame(height: geometry.size.height)
                })
            content().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
            if let platform, !platform.isEmpty {
                Text(platform).font(.caption).frame(maxWidth: 48, alignment: .trailing)
                    .accessibilityLabel("Platform \(platform)")
            }
        }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 28)
    }
}

private struct DirectionsJourneyEndpoint: View {
    let name: String
    let first: Bool
    var body: some View {
        DirectionsConnectionRow(pearl: true, first: first, last: !first) {
            Text(name).font(.body.bold())
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DirectionsLegView: View {
    let leg: DirectionsLeg
    @State private var expanded = false
    @Environment(\.colorScheme) private var colorScheme
    private var rail: Color {
        if leg.street { return .secondary }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        leg.uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return (colorScheme == .light && brightness > 0.85) || (colorScheme == .dark && brightness < 0.2) ? .primary : leg.color
    }
    private var shortenStation: Bool {
        let names = [leg.from?.name] + (leg.intermediateStops ?? []).map(\.name) + [leg.to?.name]
        return [0, 1, 2].contains(leg.routeType ?? -1) && names.allSatisfy { $0?.hasSuffix(" Station") == true }
    }
    private func stationName(_ name: String?) -> String {
        let name = name ?? ""
        return shortenStation ? String(name.dropLast(8)) : name
    }
    var body: some View {
        VStack(spacing: 0) {
            if leg.street {
                DirectionsConnectionRow(color: rail, time: directionsDurationLabel(leg.seconds), dotted: true) {
                    HStack(spacing: 6) {
                        LegModeIcon(leg: leg)
                        Text(directionsDistance(leg).map { directionsFormattedDistance($0) } ?? "Distance unavailable")
                    }
                }
            } else {
                endpoint(leg.from, time: leg.startTime, platform: leg.fromPlatform, first: true)
                DirectionsConnectionRow(color: rail) {
                    HStack(spacing: 6) {
                        LegModeIcon(leg: leg)
                        leg.badge
                        if let trip = leg.tripShortName, !trip.isEmpty { Text(trip).bold() }
                    }
                }
                if let headsign = leg.headsign ?? leg.routeLongName, !headsign.isEmpty {
                    DirectionsConnectionRow(color: rail) { Text(headsign).font(.subheadline) }
                }
                let stops = leg.intermediateStops ?? []
                DirectionsConnectionRow(color: rail) {
                    if stops.isEmpty {
                        Text("0 stops · \(directionsDurationLabel(leg.seconds))").font(.subheadline)
                    } else {
                        Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                            HStack {
                                Text("\(stops.count) stops · \(directionsDurationLabel(leg.seconds))")
                                Spacer()
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            }.font(.subheadline).frame(minHeight: 32)
                        }.buttonStyle(.plain).accessibilityLabel(expanded ? "Hide stops" : "Show stops")
                            .accessibilityValue("\(stops.count) stops · \(directionsDurationLabel(leg.seconds))")
                    }
                }
                if expanded {
                    ForEach(stops.indices, id: \.self) { index in
                        DirectionsConnectionRow(color: rail,
                            time: directionsClock(stops[index].departure ?? stops[index].arrival ?? stops[index].scheduledDeparture ?? stops[index].scheduledArrival), pearl: true) {
                            Text(stationName(stops[index].name)).font(.subheadline)
                        }
                    }
                }
                endpoint(leg.to, time: leg.endTime, platform: leg.toPlatform, first: false)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(leg.street ? Color.primary.opacity(0.15) : .clear))
    }
    private func endpoint(_ point: DirectionsPoint?, time: String?, platform: String?, first: Bool) -> some View {
        DirectionsConnectionRow(color: rail, time: directionsClock(time),
            platform: platform ?? point?.platformCode ?? point?.platform, pearl: true, first: first, last: !first) {
            Text(stationName(point?.name)).font(.body.weight(.medium))
        }
    }
}

extension DirectionsLeg {
    var systemImage: String {
        switch mode.uppercased() {
        case "WALK": return "figure.walk"
        case "BIKE", "BICYCLE": return "bicycle"
        case "BUS": return "bus.fill"
        case "FERRY": return "ferry.fill"
        default: return "tram.fill"
        }
    }
    var badge: some View { routeBadge() }
    func routeBadge(compact: Bool = false) -> some View {
        TransitRouteBadge(shortName: routeShortName ?? routeId, longName: routeLongName,
            colorHex: routeColor, textColorHex: routeTextColor, chateauID: chateau, compact: compact)
    }
    var color: Color { Color(uiColor: uiColor) }
    var uiColor: UIColor {
        let value = (routeColor ?? "").replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let hex = UInt32(value, radix: 16) else { return street ? .systemGray : .systemBlue }
        return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
