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
                if model.usingMap { mapModeHeader(itinerary) } else { details(itinerary) }
            } else {
                results
            }
        }
        .padding(.horizontal, 12)
        .onAppear { model.open(currentLocation: locationManager.lastKnownLocation); loadRecent() }
        .onDisappear { model.leave(); search.reset() }
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
            navigator.presDetent = usingMap ? .height(160) : .height(350)
        }
        .task(id: debounceKey) {
            guard model.canSearch, !model.searched else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, model.canSearch, !model.searched else { return }
            model.search()
        }
        .sheet(isPresented: $showsOptions) { optionsSheet }
        .sheet(isPresented: $showsTimeSheet) {
            TripPlannerTimeSheet(time: model.time, isNow: model.now, arriveBy: model.arriveBy) { time, isNow, arriveBy in
                model.arriveBy = arriveBy; model.now = isNow; model.time = time
            }
            .presentationDetents([.height(480)])
        }
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
                    .onAppear {
                        if index <= 1, model.canLoadEarlier { model.loadConnections(earlier: true) }
                        if index >= model.itineraries.count - 2, model.canLoadLater { model.loadConnections(earlier: false) }
                    }
                }
                connectionEdge(earlier: false)
            }
        }
    }
    /// Busy/retry indicator at a results edge; pagination itself is triggered by the nearby rows' onAppear.
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
    /// Walk/bike-only journeys and the Map toggle collapse the drawer to a thin header over the persistent map layers.
    private func mapModeHeader(_ itinerary: DirectionsItinerary) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { model.details = false } label: { Label("Journeys", systemImage: "chevron.backward") }
                Spacer()
                if !model.streetOnly {
                    Button { model.mapMode = false } label: { Label("List", systemImage: "list.bullet") }
                }
            }
            JourneyPreview(itinerary: itinerary, compact: true)
            Spacer(minLength: 0)
        }
    }
    private func details(_ itinerary: DirectionsItinerary) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { model.details = false } label: { Label("Journeys", systemImage: "chevron.backward") }
                Spacer()
                Button { model.mapMode = true } label: { Label("Map", systemImage: "map") }
                Toggle("Transfer stops", isOn: $model.showTransfers).font(.caption).fixedSize()
            }
            JourneyPreview(itinerary: itinerary, compact: navigator.presDetent == .large)
            ScrollView {
                let legs = itinerary.detailLegs
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(legs.indices, id: \.self) { index in
                        DirectionsLegView(leg: legs[index])
                    }
                }.padding(.bottom)
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
                    let width = max(proxy.size.width, CGFloat(legs.count) * 64)
                    let widths = directionsTimelineWidths(legs, width: Double(width), minimum: 64)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(legs.indices, id: \.self) { index in
                                DirectionsTimelineSegment(leg: legs[index], trailing: index == legs.count - 1 && index > 0)
                                    .frame(width: CGFloat(widths[index]))
                            }
                        }
                    }
                }.frame(height: 58).transition(.opacity)
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
                Text("\(Int(ceil(leg.seconds / 60)))′" + (directionsDistance(leg).map { " · " + directionsFormattedDistance($0) } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            } else { leg.badge }
            Spacer(minLength: 0)
        }.padding(.trailing, 4)
    }
}

func directionsDurationLabel(_ seconds: Double) -> String {
    let minutes = Int(ceil(seconds / 60))
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
}

private struct DirectionsLegView: View {
    let leg: DirectionsLeg
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LegModeIcon(leg: leg).foregroundStyle(leg.color)
                if leg.street { Text(leg.mode.capitalized).bold() } else { leg.badge }
                if let trip = leg.tripShortName, !trip.isEmpty { Text(trip).bold() }
                Spacer()
                Text("\(Int(ceil(leg.seconds / 60))) min").font(.subheadline)
            }
            if let headsign = leg.headsign { Text(headsign).font(.subheadline) }
            endpoint(leg.from, time: leg.startTime, platform: leg.fromPlatform)
            if let stops = leg.intermediateStops, !stops.isEmpty {
                DisclosureGroup("\(stops.count) stops") {
                    ForEach(stops.indices, id: \.self) { index in
                        HStack {
                            Text(directionsClock(stops[index].departure ?? stops[index].arrival)).monospacedDigit()
                            Text(stops[index].name ?? "Stop")
                        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                }
            }
            endpoint(leg.to, time: leg.endTime, platform: leg.toPlatform)
            if leg.street, let distance = directionsDistance(leg) {
                Text(directionsFormattedDistance(distance)).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func endpoint(_ point: DirectionsPoint?, time: String?, platform: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(directionsClock(time)).monospacedDigit()
            VStack(alignment: .leading) {
                Text(point?.name ?? "")
                if let platform = platform ?? point?.platformCode ?? point?.platform, !platform.isEmpty {
                    Text("Platform \(platform)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.font(.subheadline)
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
    var badge: some View {
        TransitRouteBadge(shortName: routeShortName ?? routeId, longName: routeLongName,
            colorHex: routeColor, textColorHex: routeTextColor, chateauID: chateau)
    }
    var color: Color { Color(uiColor: uiColor) }
    var uiColor: UIColor {
        let value = (routeColor ?? "").replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let hex = UInt32(value, radix: 16) else { return street ? .systemGray : .systemBlue }
        return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
