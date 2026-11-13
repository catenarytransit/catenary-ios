import Combine
import CoreLocation
import Foundation
import SwiftUI

struct DirectionsMapState: Equatable {
    var visible = false
    var origin: DirectionsLocation?
    var destination: DirectionsLocation?
    var itineraries: [DirectionsItinerary] = []
    var selected = 0
    var details = false
    var showTransfers = false
    var picking: Bool?
    var fitRevision = UUID()
}

/// Called off the main thread by the session store's background queue only; keeps route
/// geometry out of UserDefaults/iCloud key-value storage and off the main thread's I/O path.
final class TripPlannerSessionStore {
    private let url: URL
    init(filename: String = "tripPlanner.session.v2.json") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        url = caches.appendingPathComponent(filename)
    }
    func read() -> Data? { try? Data(contentsOf: url) }
    func write(_ data: Data?) {
        guard let data else { try? FileManager.default.removeItem(at: url); return }
        guard data.count < 4_000_000 else { return }
        try? data.write(to: url, options: .atomic)
    }
}

final class TripPlannerModel: ObservableObject {
    @Published private(set) var origin: DirectionsLocation?
    @Published private(set) var destination: DirectionsLocation?
    @Published private(set) var originText = ""
    @Published private(set) var destinationText = ""
    @Published var editing: Bool?
    @Published var mapPicking: Bool? { didSet { publishMap() } }
    @Published var options = DirectionsOptions() { didSet { invalidate() } }
    @Published var arriveBy = false { didSet { invalidate() } }
    @Published var now = true { didSet { invalidate() } }
    @Published var time = Date() { didSet { invalidate() } }
    @Published private(set) var itineraries: [DirectionsItinerary] = []
    @Published var selected = 0 { didSet { publishMap(fit: true); saveSession() } }
    @Published var details = false { didSet { publishMap(fit: true); saveSession() } }
    @Published var showTransfers = false { didSet { publishMap(); saveSession() } }
    @Published var mapMode = false
    @Published private(set) var loading = false
    @Published private(set) var searched = false
    @Published private(set) var error: String?
    @Published private(set) var mapState = DirectionsMapState()
    @Published private(set) var earlierLoading = false
    @Published private(set) var laterLoading = false
    @Published private(set) var previousPageCursor: String?
    @Published private(set) var nextPageCursor: String?
    @Published private(set) var savedJourneys: [String: SavedDirectionsJourney] = [:]
    @Published private(set) var savingJourney = false
    @Published private(set) var saveError: String?
    private static let savedURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("saved-journeys.json")

    struct SavedDirectionsJourney: Codable, Sendable {
        var itinerary: DirectionsItinerary
        var origin: DirectionsLocation?
        var destination: DirectionsLocation?
    }
    func toggleSavedJourney() {
        guard let journey = chosen, !savingJourney else { return }
        let saved = savedJourneys[journey.identity] != nil
        guard saved || journey.canBeSaved else { return }
        var updated = savedJourneys
        if saved { updated.removeValue(forKey: journey.identity) }
        else { updated[journey.identity] = SavedDirectionsJourney(itinerary: journey, origin: origin, destination: destination) }
        let snapshot = updated
        savingJourney = true; saveError = nil
        Task { @MainActor in
            do {
                let url = Self.savedURL
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
                }.value
                self.savedJourneys = snapshot
            } catch { self.saveError = "Unable to save journey. Please try again." }
            self.savingJourney = false
        }
    }

    private var request: Task<Void, Never>?
    private var pageRequest: Task<Void, Never>?
    private var generation = UUID()
    private var visible = false
    private var awaitingCurrentOrigin = false
    private var baseQuery: DirectionsRequest?
    private var initialPage: DirectionsPlan?
    private var earlierPages: [(id: String, page: DirectionsPlan)] = []
    private var laterPages: [(id: String, page: DirectionsPlan)] = []
    private let store: TripPlannerSessionStore = {
#if DEBUG || SCREENSHOT_AUTOMATION
        if ScreenshotLaunchConfiguration.current.plannerScreen != nil {
            return TripPlannerSessionStore(filename: "tripPlanner.ci-screenshots.json")
        }
#endif
        return TripPlannerSessionStore()
    }()

    var screenshotAutomation: Bool {
#if DEBUG || SCREENSHOT_AUTOMATION
        return ScreenshotLaunchConfiguration.current.plannerScreen != nil
#else
        return false
#endif
    }

    var chosen: DirectionsItinerary? { itineraries.indices.contains(selected) ? itineraries[selected] : nil }
    var canSearch: Bool { origin?.isValid == true && destination?.isValid == true }
    var canLoadEarlier: Bool {
        previousPageCursor != nil && baseQuery != nil && !earlierLoading && !laterLoading && !loading
    }
    var canLoadLater: Bool {
        nextPageCursor != nil && baseQuery != nil && !earlierLoading && !laterLoading && !loading
    }
    /// A chosen itinerary made entirely of walk/bike legs always opens in map mode.
    var streetOnly: Bool {
        let legs = chosen?.legs ?? []
        return !legs.isEmpty && legs.allSatisfy(\.street)
    }
    var usingMap: Bool { details && (mapMode || streetOnly) }

    init() {
        if let data = try? Data(contentsOf: Self.savedURL),
           let saved = try? JSONDecoder().decode([String: SavedDirectionsJourney].self, from: data) {
            savedJourneys = saved
        }
        if let data = store.read(),
           let session = try? JSONDecoder().decode(Session.self, from: data),
           session.origin.isValid, session.destination.isValid,
           !session.itineraries.isEmpty, session.itineraries.count < 100,
           session.itineraries.allSatisfy({ directionsDate($0.startTime) != nil && directionsDate($0.endTime) != nil }) {
            origin = session.origin; destination = session.destination
            originText = session.origin.name; destinationText = session.destination.name
            options = session.options; arriveBy = session.arriveBy; now = session.now; time = session.time
            itineraries = session.itineraries; selected = min(max(0, session.selected), session.itineraries.count - 1)
            details = session.details; showTransfers = session.showTransfers
            baseQuery = session.requestQuery
            initialPage = DirectionsPlan(itineraries: session.itineraries)
            previousPageCursor = session.previousPageCursor
            nextPageCursor = session.nextPageCursor
            searched = true
        }
    }
    /// Prepare a fresh planner without replacing an existing endpoint or session.
    func open(currentLocation: CLLocationCoordinate2D?) {
        visible = true
        Task { await DirectionsSocketPool.shared.preconnect() }
        awaitingCurrentOrigin = origin == nil && destination == nil && originText.isEmpty && destinationText.isEmpty
        if let currentLocation { resolveCurrentOrigin(currentLocation) }
        publishMap(fit: true)
    }
    /// A delayed location fix may complete the default origin until the user edits it.
    func resolveCurrentOrigin(_ coordinate: CLLocationCoordinate2D?) {
        guard awaitingCurrentOrigin, let coordinate else { return }
        choose(true, location: DirectionsLocation(name: "Current location", coordinate: coordinate, current: true))
    }
    func leave() {
        awaitingCurrentOrigin = false
        if loading, itineraries.isEmpty { searched = false }
        visible = false; cancelRequests()
        Task { await DirectionsSocketPool.shared.close() }
        editing = nil; mapPicking = nil; publishMap()
    }
    private func cancelRequests() {
        generation = UUID(); request?.cancel(); pageRequest?.cancel()
        loading = false; earlierLoading = false; laterLoading = false
    }
    func invalidate() {
        cancelRequests(); searched = false; error = nil
        baseQuery = nil; initialPage = nil; earlierPages = []; laterPages = []
        previousPageCursor = nil; nextPageCursor = nil
        itineraries = []; selected = 0; details = false; mapMode = false; showTransfers = false
        store.write(nil)
        publishMap()
    }
    /// Coordinate-based selections become an empty search when the field is focused again.
    func beginEditing(_ isOrigin: Bool) {
        let location = isOrigin ? origin : destination
        if location?.isCurrentLocation == true || location?.isMapLocation == true {
            edit(isOrigin, text: "")
        } else {
            editing = isOrigin
        }
    }
    func edit(_ isOrigin: Bool, text: String) {
        invalidate()
        if isOrigin { awaitingCurrentOrigin = false }
        if isOrigin { origin = nil; originText = text } else { destination = nil; destinationText = text }
        editing = isOrigin; publishMap()
    }
    func choose(_ isOrigin: Bool, location: DirectionsLocation) {
        guard location.isValid else { return }
        invalidate()
        if isOrigin { awaitingCurrentOrigin = false }
        if isOrigin { origin = location; originText = location.name } else { destination = location; destinationText = location.name }
        editing = nil; mapPicking = nil; publishMap()
    }
    func swap() {
        invalidate()
        let old = origin; origin = destination; destination = old
        let text = originText; originText = destinationText; destinationText = text
        editing = nil; publishMap()
    }
    func selectJourney(_ journey: DirectionsItinerary) {
        selected = max(0, itineraries.firstIndex { $0.identity == journey.identity } ?? 0)
        mapMode = false
        showTransfers = true
        details = true
        editing = nil
    }
    func search(session: URLSession = .shared, queryOverride: DirectionsRequest? = nil) {
        guard let origin, let destination else { return }
        invalidate(); searched = true; loading = true; editing = nil
        let token = generation
        do {
            let base = try queryOverride ?? DirectionsRequest(from: origin, to: destination, date: now ? Date() : time, arriveBy: arriveBy, options: options)
            baseQuery = base
            let direction: ConnectionDirection = arriveBy ? .before : .after
            let requestId = queryOverride?.request_id ?? "catenary-ios-\(UUID().uuidString)"
            let query = queryOverride ?? directionsPageQuery(base: base, direction: direction, requestId: requestId)
            request = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await DirectionsStreaming.load(query: query, requestId: requestId, session: session) { [weak self] page in
                        guard let self, token == self.generation else { return }
                        self.initialPage = page
                        if self.earlierPages.isEmpty {
                            self.previousPageCursor = (page.previousPageCursor?.isEmpty == false) ? page.previousPageCursor : nil
                        }
                        if self.laterPages.isEmpty {
                            self.nextPageCursor = (page.nextPageCursor?.isEmpty == false) ? page.nextPageCursor : nil
                        }
                        self.publishPages()
                    }
                } catch {
                    if token == self.generation { self.error = error.localizedDescription }
                }
                if token == self.generation {
                    self.loading = false
                    self.saveSession()
                }
            }
        } catch {
            self.error = error.localizedDescription; loading = false
        }
    }
    func loadConnections(earlier: Bool, session: URLSession = .shared) {
        guard earlier ? canLoadEarlier : canLoadLater else { return }
        guard let cursor = earlier ? previousPageCursor : nextPageCursor, let base = baseQuery else { return }
        let token = generation
        let id = "catenary-ios-\(UUID().uuidString)"
        if earlier { earlierLoading = true } else { laterLoading = true }
        error = nil
        let direction: ConnectionDirection = earlier ? .before : .after
        let query = directionsPageQuery(base: base, direction: direction, cursor: cursor, requestId: id)
        pageRequest = Task { @MainActor [weak self] in
            guard let self else { return }
            var completedPage: DirectionsPlan?
            do {
                try await DirectionsStreaming.load(query: query, requestId: id, session: session) { page in completedPage = page }
                if token == self.generation, let page = completedPage {
                    if earlier {
                        self.earlierPages.append((id: id, page: page))
                        self.previousPageCursor = (page.previousPageCursor?.isEmpty == false && page.previousPageCursor != cursor) ? page.previousPageCursor : nil
                    } else {
                        self.laterPages.append((id: id, page: page))
                        self.nextPageCursor = (page.nextPageCursor?.isEmpty == false && page.nextPageCursor != cursor) ? page.nextPageCursor : nil
                    }
                    self.publishPages()
                    // Persist the final cursors after the busy flag clears below.
                }
            } catch {
                if token == self.generation { self.error = error.localizedDescription }
            }
            if token == self.generation {
                if earlier { self.earlierLoading = false } else { self.laterLoading = false }
                self.saveSession()
            }
        }
    }
    private func publishPages() {
        let selectedIdentity = itineraries.indices.contains(selected) ? itineraries[selected].identity : nil
        let pages = earlierPages.map(\.page) + [initialPage].compactMap { $0 } + laterPages.map(\.page)
        itineraries = mergeDirectionsPages(pages)
        selected = max(0, itineraries.firstIndex { $0.identity == selectedIdentity } ?? 0)
        if details, let selectedIdentity, !itineraries.contains(where: { $0.identity == selectedIdentity }) { details = false }
        publishMap(fit: true); saveSession()
    }
    private func publishMap(fit: Bool = false) {
#if DEBUG || SCREENSHOT_AUTOMATION
        if fit, screenshotAutomation { ScreenshotReadiness.shared.invalidateMapReady() }
#endif
        mapState = DirectionsMapState(visible: visible, origin: origin, destination: destination,
            itineraries: itineraries, selected: selected, details: details, showTransfers: showTransfers, picking: mapPicking,
            fitRevision: fit ? UUID() : mapState.fitRevision)
    }
    /// One completed search, including the exact itinerary being viewed and the cursors needed to keep paging.
    private struct Session: Codable {
        var origin: DirectionsLocation; var destination: DirectionsLocation
        var options: DirectionsOptions; var arriveBy: Bool; var now: Bool; var time: Date
        var itineraries: [DirectionsItinerary]; var selected: Int
        var details = false; var showTransfers = false
        var requestQuery: DirectionsRequest?
        var previousPageCursor: String?; var nextPageCursor: String?
    }
    /// Empty, invalidated and unfinished searches must never reopen an empty planner.
    private func saveSession() {
        guard !loading, !earlierLoading, !laterLoading, searched, error == nil, !itineraries.isEmpty, let origin, let destination else { return }
        let session = Session(origin: origin, destination: destination, options: options, arriveBy: arriveBy,
            now: now, time: time, itineraries: itineraries, selected: selected, details: details, showTransfers: showTransfers,
            requestQuery: baseQuery, previousPageCursor: previousPageCursor, nextPageCursor: nextPageCursor)
        if let data = try? JSONEncoder().encode(session) { store.write(data) }
    }
}

extension DirectionsLocation {
    init(name: String, coordinate: CLLocationCoordinate2D, current: Bool = false, mapPicked: Bool = false) {
        self.init(name: name, lat: coordinate.latitude, lon: coordinate.longitude, isCurrentLocation: current, isMapLocation: mapPicked)
    }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

struct TripPlannerLocationActions: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    @EnvironmentObject private var navigator: viewObject
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                action(true, title: "As origin")
                action(false, title: "As destination")
            }
        }
    }
    private func action(_ origin: Bool, title: String) -> some View {
        Button {
            let planner = navigator.tripPlanner
            let location = DirectionsLocation(name: name, coordinate: coordinate)
            planner.choose(origin, location: location)
            if let current = navigator.userCoordinate,
               CLLocation(latitude: current.latitude, longitude: current.longitude).distance(from:
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 500_000 {
                planner.choose(!origin, location: DirectionsLocation(name: "Current location", coordinate: current, current: true))
            }
            navigator.push(.tripPlanner)
            navigator.presDetent = .height(350)
        } label: {
            HStack(spacing: 6) {
                DirectionsEndpointGlyph(origin: origin)
                Text(title)
            }.font(.subheadline)
        }
        .buttonStyle(.bordered)
    }
}

/// Adaptive vector glyph matching the Android origin/destination action icons.
struct DirectionsEndpointGlyph: View {
    let origin: Bool
    var body: some View {
        Canvas { context, _ in
            let center = origin ? 8.0 : 16.0
            let ring = Path(ellipseIn: CGRect(x: center - 6, y: 4, width: 12, height: 12))
            context.stroke(ring, with: .foreground, lineWidth: 1.5)
            let inner = Path(ellipseIn: CGRect(x: center - 2, y: 8, width: 4, height: 4))
            if origin { context.stroke(inner, with: .foreground, lineWidth: 1.2) }
            else { context.fill(inner, with: .foreground) }
            var stem = Path()
            stem.move(to: CGPoint(x: origin ? 14 : 0, y: 10))
            stem.addLine(to: CGPoint(x: origin ? 24 : 10, y: 10))
            context.stroke(stem, with: .foreground, lineWidth: 1.5)
        }.frame(width: 24, height: 20).accessibilityHidden(true)
    }
}

/// Matching double-ring markers for the origin and destination rows, joined by a shared rail.
/// Ported from Compose's `EndpointPearls`.
struct DirectionsEndpointRail: View {
    var originIsCurrent = false
    var destinationIsCurrent = false
    // Matches endpointField's minHeight plus the divider between the two rows in TripPlannerScreen's inputCard.
    private let rowHeight: CGFloat = 44
    var body: some View {
        ZStack {
            Canvas { context, size in
                let x = size.width / 2
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height * 0.25))
                line.addLine(to: CGPoint(x: x, y: size.height * 0.75))
                context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 2))
            }
            VStack(spacing: 0) {
                marker(current: originIsCurrent).frame(maxWidth: .infinity, maxHeight: .infinity)
                marker(current: destinationIsCurrent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: rowHeight * 2)
        .accessibilityHidden(true)
    }
    @ViewBuilder private func marker(current: Bool) -> some View {
        if current {
            Image(systemName: "location.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.13, green: 0.59, blue: 0.95))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
        } else {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                func ring(radius: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                }
                context.fill(ring(radius: 6), with: .color(Color(uiColor: .secondarySystemBackground)))
                context.stroke(ring(radius: 6), with: .foreground, lineWidth: 2)
                context.stroke(ring(radius: 2.5), with: .foreground, lineWidth: 1)
            }.frame(width: 16, height: 16)
        }
    }
}
