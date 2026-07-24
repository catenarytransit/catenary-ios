import Combine
import CoreLocation
import Foundation

@MainActor
final class StationDeparturesViewModel: ObservableObject {
    private struct IndexedEvent {
        let event: StopEvent
        let refreshedAt: Int64
    }

    struct PageState: Identifiable, Equatable {
        let id: String
        let start: Int64
        let end: Int64
        var isLoading: Bool
        var errorDescription: String?
    }

    private enum Paging {
        static let overlapSeconds: Int64 = 5 * 60
        static let initialLookbackSeconds: Int64 = 30 * 60
        static let highDensityThreshold = 150
        static let lowDensityThreshold = 40
        static let maximumPageHours = 24
        static let maximumAutomaticPages = 6
    }

    @Published private(set) var primary: StopPrimary?
    @Published private(set) var stops: [StopPrimary] = []
    @Published private(set) var routes: [String: [String: StopRouteInfo]] = [:]
    @Published private(set) var agencies: [String: [String: StopAgencyInfo]] = [:]
    @Published private(set) var events: [StopEvent] = []
    @Published private(set) var pages: [PageState] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var redirectToOSMStationID: Int64?

    private let apiClient: StopAPIClient
    private var source: StopScreenSource?
    private var pageIndex: [String: PageState] = [:]
    private var eventIndex: [String: IndexedEvent] = [:]
    private var currentPageHours = 1
    private var revision = 0

    init(apiClient: StopAPIClient = StopAPIClient()) {
        self.apiClient = apiClient
    }

    var isLoading: Bool {
        pages.contains(where: \.isLoading)
    }

    var timezoneID: String? {
        primary?.timezone
            ?? stops.first?.timezone
            ?? agencies.values.lazy.flatMap { $0.values }.compactMap { $0.agencyTimezone }.first
            ?? events.compactMap(\.timezone).first
    }

    var stationCoordinate: CLLocationCoordinate2D? {
        if let primary { return primary.coordinate }
        guard !stops.isEmpty else { return nil }

        let latitude = stops.map(\.stopLat).reduce(0, +) / Double(stops.count)
        let longitude = stops.map(\.stopLon).reduce(0, +) / Double(stops.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var primaryChateauID: String? {
        if let explicit = source?.explicitChateauID { return explicit }
        let keys = Set(routes.keys)
        for preferred in ["deutschland", "schweiz", "île~de~france~mobilités"] where keys.contains(preferred) {
            return preferred
        }
        return keys.first
    }

    func reset(source: StopScreenSource, anchor: Date) async {
        revision += 1
        let activeRevision = revision
        self.source = source
        currentPageHours = 1
        primary = nil
        stops = []
        routes = [:]
        agencies = [:]
        events = []
        pages = []
        pageIndex = [:]
        eventIndex = [:]
        errorMessage = nil
        redirectToOSMStationID = nil

        let anchorSeconds = Int64(anchor.timeIntervalSince1970)
        let start = anchorSeconds - Paging.initialLookbackSeconds
        let end = start + Int64(currentPageHours * 3600)
        await fetchPage(start: start, end: end, revision: activeRevision)

        var automaticPageCount = 1
        while activeRevision == revision,
              events.count < Paging.lowDensityThreshold,
              automaticPageCount < Paging.maximumAutomaticPages,
              !pages.contains(where: { $0.errorDescription != nil }) {
            await loadNextPage(revision: activeRevision)
            if redirectToOSMStationID != nil { break }
            automaticPageCount += 1
        }
    }

    func refreshLoadedPages() async {
        let activeRevision = revision
        let windows = pages.map { ($0.start, $0.end) }
        for window in windows where activeRevision == revision {
            await fetchPage(start: window.0, end: window.1, revision: activeRevision)
        }
    }

    func loadEarlierPage() async {
        guard !isLoading else { return }
        let activeRevision = revision
        guard let earliestStart = pages.map(\.start).min() else { return }
        let span = Int64(max(currentPageHours, 1) * 3600)
        let end = earliestStart + Paging.overlapSeconds
        let start = end - span
        await fetchPage(start: start, end: end, revision: activeRevision)
    }

    func ensureCoverage(around date: Date) async {
        let target = Int64(date.timeIntervalSince1970) - Paging.initialLookbackSeconds
        var guardCount = 0
        while let earliest = pages.map(\.start).min(),
              target < earliest,
              guardCount < 12,
              !isLoading {
            await loadEarlierPage()
            guardCount += 1
        }
    }

    func loadNextPage() async {
        await loadNextPage(revision: revision)
    }

    func lookupOSMStation(chateauID: String, stopID: String) async -> OSMStationLookupResponse? {
        do {
            return try await apiClient.lookupOSMStation(chateauID: chateauID, stopID: stopID)
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private func loadNextPage(revision activeRevision: Int) async {
        guard activeRevision == revision, !isLoading else { return }
        guard let latestEnd = pages.map(\.end).max() else { return }
        let start = latestEnd - Paging.overlapSeconds
        let end = start + Int64(max(currentPageHours, 1) * 3600)
        await fetchPage(start: start, end: end, revision: activeRevision)
    }

    private func fetchPage(start: Int64, end: Int64, revision activeRevision: Int) async {
        guard activeRevision == revision, let source else { return }
        let pageID = "\(start)_\(end)"
        if pageIndex[pageID]?.isLoading == true { return }

        pageIndex[pageID] = PageState(
            id: pageID,
            start: start,
            end: end,
            isLoading: true,
            errorDescription: nil
        )
        publishPages()

        do {
            let result = try await apiClient.fetchDepartures(source: source, start: start, end: end)
            guard activeRevision == revision else { return }

            switch result {
            case let .redirect(osmStationID):
                redirectToOSMStationID = osmStationID

            case let .departures(response):
                merge(response: response, refreshedAt: Int64(Date().timeIntervalSince1970))
                updatePageHours(eventCount: response.events?.count ?? 0)
            }

            pageIndex[pageID] = PageState(
                id: pageID,
                start: start,
                end: end,
                isLoading: false,
                errorDescription: nil
            )
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeRevision == revision else { return }
            pageIndex[pageID] = PageState(
                id: pageID,
                start: start,
                end: end,
                isLoading: false,
                errorDescription: error.localizedDescription
            )
            if events.isEmpty { errorMessage = error.localizedDescription }
        }

        publishPages()
    }

    private func merge(response: DeparturesAtStopResponse, refreshedAt: Int64) {
        if let responsePrimary = response.primary { primary = responsePrimary }
        if let responseStops = response.stops, !responseStops.isEmpty { stops = responseStops }

        for (chateauID, incomingRoutes) in response.routes ?? [:] {
            routes[chateauID, default: [:]].merge(incomingRoutes) { _, new in new }
        }
        for (chateauID, incomingAgencies) in response.agencies ?? [:] {
            agencies[chateauID, default: [:]].merge(incomingAgencies) { _, new in new }
        }

        for rawEvent in response.events ?? [] {
            let event = rawEvent.normalizedForStationDisplay
            let existing = eventIndex[event.eventKey]
            if existing == nil || refreshedAt >= existing!.refreshedAt {
                eventIndex[event.eventKey] = IndexedEvent(event: event, refreshedAt: refreshedAt)
            }
        }

        events = eventIndex.values
            .map(\.event)
            .sorted { ($0.effectiveTime ?? .max) < ($1.effectiveTime ?? .max) }
    }

    private func updatePageHours(eventCount: Int) {
        if eventCount >= Paging.highDensityThreshold {
            currentPageHours = 2
        } else if eventCount <= Paging.lowDensityThreshold {
            currentPageHours = min(max(currentPageHours * 2, 1), Paging.maximumPageHours)
        }
    }

    private func publishPages() {
        pages = pageIndex.values.sorted { $0.start < $1.start }
    }
}
