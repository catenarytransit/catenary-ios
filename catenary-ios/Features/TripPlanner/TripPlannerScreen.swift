import CoreLocation
import SwiftUI

struct TripPlannerScreen: View {
    @ObservedObject var model: TripPlannerModel
    @ObservedObject var locationManager: LocationManager
    @EnvironmentObject private var navigator: viewObject
    @StateObject private var search = SearchViewModel()
    @FocusState private var focused: Bool?
    @State private var showsOptions = false

    var body: some View {
        VStack(spacing: 8) {
            if !model.details { inputCard }
            if let picking = model.mapPicking {
                Label("Move the map to choose a location", systemImage: "mappin")
                    .font(.subheadline)
                HStack {
                    Button("Cancel") { model.mapPicking = nil; navigator.presDetent = .height(350) }
                    Spacer()
                    Button("Use this location") {
                        let center = navigator.visibleCoordinateBounds.catenarySearchCenter
                        model.choose(picking, location: DirectionsLocation(name: String(format: "%.6f, %.6f", center.latitude, center.longitude), coordinate: center))
                        navigator.presDetent = .height(350)
                    }.buttonStyle(.borderedProminent)
                }
            } else if let editing = model.editing {
                endpointSearch(editing)
            } else if model.details, let itinerary = model.chosen {
                details(itinerary)
            } else {
                results
            }
        }
        .padding(.horizontal, 12)
        .onAppear { model.appear() }
        .onDisappear { model.leave(); search.reset() }
        .catenaryOnChange(of: focused) { _, endpoint in
            if let endpoint { model.editing = endpoint; navigator.presDetent = .large; performSearch(endpoint) }
        }
        .catenaryOnChange(of: model.editing) { _, endpoint in
            if endpoint == nil { focused = nil; search.reset() }
        }
        .sheet(isPresented: $showsOptions) { optionsSheet }
    }
    private var inputCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(spacing: 12) {
                    Image(systemName: "circle.circle")
                    Image(systemName: "record.circle")
                }.foregroundStyle(.secondary)
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
            HStack {
                Picker("Time", selection: $model.arriveBy) {
                    Text("Depart at").tag(false)
                    Text("Arrive by").tag(true)
                }.labelsHidden().pickerStyle(.menu)
                Toggle("Now", isOn: $model.now).fixedSize()
                Spacer(minLength: 0)
            }
            if !model.now { DatePicker("Date and time", selection: $model.time).labelsHidden() }
            HStack {
                Button { focused = nil; showsOptions = true } label: {
                    Label(model.options.cycling ? "Cycling options" : "Walking options", systemImage: model.options.cycling ? "bicycle" : "figure.walk")
                }.font(.subheadline)
                Spacer(minLength: 0)
                Button {
                    focused = nil; search.reset(); model.search()
                    navigator.presDetent = .height(350)
                } label: { Label("Find journeys", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSearch || model.loading)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
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
        .onSubmit { if model.canSearch { focused = nil; model.search() } }
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
        navigator.presDetent = .height(350)
    }
    private func endpointSearch(_ origin: Bool) -> some View {
        ScrollView {
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
                if let coordinate = parseDirectionsCoordinate(origin ? model.originText : model.destinationText) {
                    Button { choose(origin, coordinate) } label: { Label(coordinate.name, systemImage: "number").padding() }
                }
                if search.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
                ForEach(search.rows) { row in
                    if let location = row.directionsLocation {
                        Button { choose(origin, location) } label: {
                            HStack {
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
        case let .stop(_, stop, routes, agencies, distance, _):
            StopSearchResultRow(stop: stop, routes: routes, agencyNames: agencies, distanceMetres: distance)
        case .route: EmptyView()
        }
    }
    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if model.loading { ProgressView("Finding journeys…").padding() }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary).padding()
                    Button("Try again") { model.search() }
                } else if model.searched, !model.loading, model.itineraries.isEmpty {
                    Label("No journeys found. Try another time or increase the access limits.", systemImage: "tram")
                        .padding()
                }
                ForEach(model.itineraries.indices, id: \.self) { index in
                    Button {
                        model.selected = index; model.details = true
                        navigator.presDetent = .height(350)
                    } label: { JourneyPreview(itinerary: model.itineraries[index]) }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    private func details(_ itinerary: DirectionsItinerary) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { model.details = false } label: { Label("Journeys", systemImage: "chevron.backward") }
                Spacer()
                Toggle("Transfer stops", isOn: $model.showTransfers).font(.caption).fixedSize()
            }
            JourneyPreview(itinerary: itinerary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(itinerary.legs.indices, id: \.self) { index in
                        DirectionsLegView(leg: itinerary.legs[index])
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
            Slider(value: value, in: 0...7200, step: 60)
        }
    }
}

extension SearchRow {
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
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .naturalScale
    formatter.numberFormatter.maximumFractionDigits = 1
    return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
}
func directionsClock(_ time: String?) -> String {
    guard let date = directionsDate(time) else { return "—" }
    return date.formatted(date: .omitted, time: .shortened)
}

struct JourneyPreview: View {
    let itinerary: DirectionsItinerary
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(directionsClock(itinerary.startTime))
                Spacer()
                Text("\(Int(ceil(itinerary.seconds / 60))) min").font(.headline)
                Spacer()
                Text(directionsClock(itinerary.endTime))
            }.monospacedDigit()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(itinerary.legs.indices, id: \.self) { index in
                        let leg = itinerary.legs[index]
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                Image(systemName: leg.systemImage)
                                if !leg.street { leg.badge }
                            }.font(.subheadline)
                            Capsule().fill(leg.color).frame(minWidth: 42, idealWidth: max(42, CGFloat(leg.seconds / max(1, itinerary.seconds)) * 230), maxWidth: 150, minHeight: 4, maxHeight: 4)
                            Text("\(Int(ceil(leg.seconds / 60))) min").font(.caption)
                        }
                        if index < itinerary.legs.count - 1 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.padding(10).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DirectionsLegView: View {
    let leg: DirectionsLeg
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: leg.systemImage).foregroundStyle(leg.color)
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
