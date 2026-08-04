import CoreLocation
import SwiftUI

struct StationDeparturesScreen: View {
    let destination: CatenaryStackItem

    @EnvironmentObject private var viewObject: viewObject
    @StateObject private var model = StationDeparturesViewModel()
    @State private var selectedDate: Date
    @State private var isNow: Bool
    @State private var now = Date()
    @State private var activeMode: StopTransitMode?
    @State private var enabledTrainCategories = Set<String>()
    @State private var categoryChateauID: String?
    @State private var alertsPresented = false
    @State private var hasCenteredMap = false

    private let source: StopScreenSource

    init(destination: CatenaryStackItem) {
        guard let source = StopScreenSource(destination: destination) else {
            preconditionFailure("StationDeparturesScreen requires a stop or OSM station destination")
        }
        self.destination = destination
        self.source = source

        let selectedEpoch: Int64?
        switch destination {
        case let .stop(_, _, timeEpochSeconds):
            selectedEpoch = timeEpochSeconds
        case let .osmStation(_, _, _, _, _, timeEpochSeconds):
            selectedEpoch = timeEpochSeconds
        default:
            selectedEpoch = nil
        }

        _selectedDate = State(
            initialValue: selectedEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
        _isNow = State(initialValue: selectedEpoch == nil)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                header

                StationTimeSelector(
                    selectedDate: $selectedDate,
                    isNow: $isNow,
                    timezoneID: timezoneID,
                    onSelectionChanged: reloadForSelectedTime
                )

                if availableModes.count > 1 {
                    StopModePicker(availableModes: availableModes, selection: $activeMode)
                }

                if activeMode == .rail, !trainCategories.isEmpty {
                    StopTrainCategoryPicker(
                        categories: trainCategories,
                        enabledCategories: $enabledTrainCategories
                    )
                }

                if model.isLoading, model.events.isEmpty {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                if let errorMessage = model.errorMessage, model.events.isEmpty {
                    ContentUnavailableView(
                        "Unable to load departures",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    departuresList(proxy: proxy)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .task(id: source.id) {
            if await redirectGTFSStopToOSMStationIfNeeded() { return }
            guard !Task.isCancelled else { return }
            await model.reset(source: source, anchor: referenceDate)
            synchronizeFilters()
            updateMapContext()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await model.refreshLoadedPages()
                updateMapContext()
            }
        }
        .task(id: "clock|\(source.id)") {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: model.events) { _, _ in
            synchronizeFilters()
        }
        .onChange(of: model.primary) { _, _ in
            updateMapContext()
        }
        .onChange(of: model.stops) { _, _ in
            updateMapContext()
        }
        .onChange(of: model.primaryChateauID) { _, _ in
            synchronizeTrainCategories()
        }
        .onChange(of: model.redirectToOSMStationID) { _, stationID in
            guard let stationID else { return }
            replaceWithOSMStation(
                id: stationID,
                stationName: nil,
                modeType: nil,
                latitude: nil,
                longitude: nil
            )
        }
        .fullScreenCover(isPresented: $alertsPresented) {
            alertsSheet
        }
        .onDisappear {
            viewObject.clearSelectedStopContext(id: source.id)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stationName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                if let timezoneID {
                    Text(StopDateFormatting.clock(date: now, timezoneID: timezoneID))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(timezoneID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)
        }
    }

    private func departuresList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if totalAlertCount > 0 {
                    alertsButton
                }

                Button {
                    let previousFirstEventID = daySections.first?.events.first?.id
                    let earlierDate = Calendar.current.date(byAdding: .hour, value: -1, to: referenceDate)
                        ?? referenceDate.addingTimeInterval(-3600)
                    isNow = false
                    selectedDate = earlierDate
                    persistSelectedTime()

                    Task {
                        await model.ensureCoverage(around: earlierDate)
                        if let previousFirstEventID {
                            await MainActor.run {
                                proxy.scrollTo(previousFirstEventID, anchor: .top)
                            }
                        }
                    }
                } label: {
                    Label("Earlier", systemImage: "chevron.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                if daySections.isEmpty, !model.isLoading {
                    ContentUnavailableView(
                        "No departures in this time range",
                        systemImage: "clock.badge.xmark"
                    )
                    .padding(.vertical, 28)
                }

                ForEach(daySections) { section in
                    Section {
                        ForEach(section.events) { event in
                            let routeInfo = model.routes[event.chateau]?[event.routeId]
                            let agency = routeInfo?.agencyId.flatMap {
                                model.agencies[event.chateau]?[$0]
                            }
                            let trainDisplayName = StopDeparturePresentation.dbFernverkehrDisplayName(
                                event: event,
                                routeInfo: routeInfo
                            )
                            let mode = StopTransitMode.from(
                                routeType: routeInfo?.routeType ?? event.routeType
                            )

                            if mode == .rail {
                                StationTrainDepartureRow(
                                    event: event,
                                    routeInfo: routeInfo,
                                    agency: agency,
                                    timezoneID: event.timezone ?? timezoneID,
                                    now: now,
                                    layout: departureLayout,
                                    trainDisplayName: trainDisplayName
                                )
                                .id(event.id)
                            } else {
                                StationDepartureRow(
                                    event: event,
                                    routeInfo: routeInfo,
                                    agency: agency,
                                    timezoneID: event.timezone ?? timezoneID,
                                    now: now,
                                    layout: departureLayout,
                                    trainDisplayName: trainDisplayName
                                )
                                .id(event.id)
                            }

                            Divider().padding(.leading, 60)
                        }
                    } header: {
                        Text(StopDateFormatting.dayTitle(date: section.date, timezoneID: timezoneID))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .background(Color(uiColor: .systemBackground))
                            .zIndex(1)
                    }
                }

                Group {
                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            Task { await model.loadNextPage() }
                        } label: {
                            Label("Load later departures", systemImage: "chevron.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .onAppear {
                            Task { await model.loadNextPage() }
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await model.refreshLoadedPages()
        }
    }

    private var alertsButton: some View {
        ServiceAlertsLink(alerts: flattenedNonTripSpecificAlerts) {
            alertsPresented = true
        }
        .padding(.vertical, 8)
    }

    private var alertsSheet: some View {
        NavigationStack {
            ZStack {
                serviceAlertsBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(nonTripSpecificAlerts, id: \.chateauID) { group in
                            AlertsBox(
                                alerts: group.alerts,
                                defaultTimezone: timezoneID,
                                chateauID: group.chateauID
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Service alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(serviceAlertsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { alertsPresented = false }
                }
            }
        }
    }

    private var nonTripSpecificAlerts: [(chateauID: String, alerts: [String: SingleTripAlert])] {
        model.alerts.keys.sorted().compactMap { chateauID in
            guard let alerts = model.alerts[chateauID] else { return nil }
            let filtered = alerts.filter { !$0.value.isTripSpecific() }
            guard !filtered.isEmpty else { return nil }
            return (chateauID, filtered)
        }
    }

    private var flattenedNonTripSpecificAlerts: [SingleTripAlert] {
        nonTripSpecificAlerts.flatMap { group in
            group.alerts.sorted { $0.key < $1.key }.map(\.value)
        }
    }

    private var totalAlertCount: Int {
        flattenedNonTripSpecificAlerts.count
    }

    private var referenceDate: Date {
        isNow ? now : selectedDate
    }

    private var timezoneID: String? {
        model.timezoneID
    }

    private var departureLayout: StopDepartureLayout {
        StopDeparturePresentation.layout(
            for: model.stationCoordinate ?? destinationCoordinate,
            chateauID: model.primaryChateauID
        )
    }

    private var availableModes: [StopTransitMode] {
        let modes = Set(model.events.map { event in
            StopTransitMode.from(
                routeType: model.routes[event.chateau]?[event.routeId]?.routeType ?? event.routeType
            )
        })
        return StopTransitMode.allCases.filter(modes.contains)
    }

    private var trainCategories: [String] {
        StopTrainCategoryClassifier.categories(for: model.primaryChateauID)
    }

    private var filteredEvents: [StopEvent] {
        let cutoff = Int64(referenceDate.timeIntervalSince1970) - 60
        return model.events.filter { event in
            guard !event.isTerminalArrivalOnly,
                  (event.effectiveTime ?? 0) >= cutoff else {
                return false
            }

            let routeInfo = model.routes[event.chateau]?[event.routeId]
            let mode = StopTransitMode.from(routeType: routeInfo?.routeType ?? event.routeType)
            if let activeMode, availableModes.count > 1, mode != activeMode {
                return false
            }

            if mode == .rail, !trainCategories.isEmpty {
                let category = StopDeparturePresentation.trainCategory(
                    chateauID: model.primaryChateauID,
                    routeShortName: routeInfo?.shortName,
                    event: event,
                    routeInfo: routeInfo
                )
                return enabledTrainCategories.contains(category)
            }

            return true
        }
    }

    private var daySections: [StopDaySection] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            StopDateFormatting.day(
                epochSeconds: event.effectiveTime ?? 0,
                timezoneID: event.timezone ?? timezoneID
            )
        }

        return grouped.map { date, events in
            StopDaySection(
                date: date,
                events: events.sorted { ($0.effectiveTime ?? .max) < ($1.effectiveTime ?? .max) }
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var stationName: String {
        if let name = model.primary?.stopName, !name.isEmpty { return name }
        if case let .osmStation(_, stationName, _, _, _, _) = destination,
           let stationName,
           !stationName.isEmpty {
            return stationName
        }
        return source.explicitChateauID == nil
            ? L10n.string("Station")
            : L10n.string("Stop")
    }

    private func synchronizeFilters() {
        if activeMode == nil || !availableModes.contains(activeMode!) {
            activeMode = availableModes.first
        }
        synchronizeTrainCategories()
    }

    private func synchronizeTrainCategories() {
        let chateauID = model.primaryChateauID
        guard categoryChateauID != chateauID else { return }
        categoryChateauID = chateauID
        enabledTrainCategories = Set(StopTrainCategoryClassifier.categories(for: chateauID))
    }

    private func reloadForSelectedTime() {
        persistSelectedTime()
        Task {
            await model.reset(source: source, anchor: referenceDate)
            synchronizeFilters()
            updateMapContext()
        }
    }

    private func persistSelectedTime() {
        viewObject.updateCurrentStopTime(
            isNow ? nil : Int64(selectedDate.timeIntervalSince1970)
        )
    }

    private func redirectGTFSStopToOSMStationIfNeeded() async -> Bool {
        guard case let .stop(chateauID, stopID) = source,
              let lookup = await model.lookupOSMStation(chateauID: chateauID, stopID: stopID),
              lookup.found,
              let stationID = lookup.osmStationId else {
            return false
        }

        replaceWithOSMStation(
            id: stationID,
            stationName: lookup.osmStationInfo?.name,
            modeType: lookup.osmStationInfo?.modeType,
            latitude: lookup.osmStationInfo?.lat,
            longitude: lookup.osmStationInfo?.lon
        )
        return true
    }

    private func replaceWithOSMStation(
        id: Int64,
        stationName: String?,
        modeType: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        viewObject.replaceTop(with: .osmStation(
            osmStationID: String(id),
            stationName: stationName,
            modeType: modeType,
            latitude: latitude,
            longitude: longitude,
            timeEpochSeconds: isNow ? nil : Int64(selectedDate.timeIntervalSince1970)
        ))
    }

    private func updateMapContext() {
        let coordinate = model.stationCoordinate ?? destinationCoordinate
        guard let coordinate else { return }

        viewObject.setSelectedStopContext(
            SelectedStopMapContext(
                id: source.id,
                name: stationName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )

        guard !hasCenteredMap else { return }
        viewObject.camera = .center(coordinate, zoom: 14)
        hasCenteredMap = true
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        guard case let .osmStation(_, _, _, latitude, longitude, _) = destination,
              let latitude,
              let longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct StopModePicker: View {
    let availableModes: [StopTransitMode]
    @Binding var selection: StopTransitMode?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(availableModes) { mode in
                    let isSelected = selection == mode
                    Button {
                        selection = mode
                    } label: {
                        VStack(spacing: 4) {
                            Text(mode.title)
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                            Capsule()
                                .fill(isSelected ? Color.accentColor : Color.clear)
                                .frame(width: 20, height: 2)
                        }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct StopTrainCategoryPicker: View {
    let categories: [String]
    @Binding var enabledCategories: Set<String>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let isEnabled = enabledCategories.contains(category)
                    Button {
                        if isEnabled {
                            enabledCategories.remove(category)
                        } else {
                            enabledCategories.insert(category)
                        }
                    } label: {
                        Text(verbatim: StopTrainCategoryClassifier.localizedTitle(category))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .foregroundStyle(isEnabled ? Color.white : Color.primary)
                            .background(isEnabled ? Color.accentColor : Color.clear, in: Capsule())
                            .overlay {
                                Capsule().stroke(
                                    isEnabled ? Color.accentColor : Color.secondary.opacity(0.4),
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct StationTimeSelector: View {
    @Binding var selectedDate: Date
    @Binding var isNow: Bool
    let timezoneID: String?
    let onSelectionChanged: () -> Void

    @State private var isPresented = false
    @State private var draftDate = Date()

    var body: some View {
        Button {
            draftDate = isNow ? Date() : selectedDate
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(dateAndTimeLabel)
                    .font(.subheadline.weight(.medium))
                if isNow {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Departure time",
                        selection: $draftDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(
                        \.timeZone,
                        timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
                    )

                    Button("Use current time") {
                        selectedDate = Date()
                        isNow = true
                        isPresented = false
                        onSelectionChanged()
                    }
                }
                .navigationTitle("Choose time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            selectedDate = draftDate
                            isNow = false
                            isPresented = false
                            onSelectionChanged()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var dateAndTimeLabel: String {
        let timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        let displayDate = isNow ? Date() : selectedDate

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("EEE d MMM")

        let dateLabel = calendar.isDate(displayDate, inSameDayAs: Date())
            ? L10n.string("Today")
            : dateFormatter.string(from: displayDate)

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_GB_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"

        return "\(dateLabel) \(timeFormatter.string(from: displayDate))"
    }
}
