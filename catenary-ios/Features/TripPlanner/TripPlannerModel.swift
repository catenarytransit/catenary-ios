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
    @Published private(set) var loading = false
    @Published private(set) var searched = false
    @Published private(set) var error: String?
    @Published private(set) var mapState = DirectionsMapState()
    private var request: Task<Void, Never>?
    private var generation = UUID()
    private var visible = false
    private let sessionKey = "tripPlanner.session.v1"

    var chosen: DirectionsItinerary? { itineraries.indices.contains(selected) ? itineraries[selected] : nil }
    var canSearch: Bool { origin?.isValid == true && destination?.isValid == true }

    init() {
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(Session.self, from: data),
           session.origin.isValid, session.destination.isValid,
           !session.itineraries.isEmpty, session.itineraries.count < 100,
           session.itineraries.allSatisfy({ directionsDate($0.startTime) != nil && directionsDate($0.endTime) != nil }) {
            origin = session.origin; destination = session.destination
            originText = session.origin.name; destinationText = session.destination.name
            options = session.options; arriveBy = session.arriveBy; now = session.now; time = session.time
            itineraries = session.itineraries; selected = min(max(0, session.selected), session.itineraries.count - 1)
            details = session.details ?? false; showTransfers = session.showTransfers ?? false
            searched = true
        }
    }
    func appear() { visible = true; publishMap(fit: true) }
    func leave() {
        if loading { searched = false }
        visible = false; request?.cancel(); generation = UUID(); loading = false
        editing = nil; mapPicking = nil; publishMap()
    }
    func invalidate() {
        generation = UUID(); request?.cancel(); loading = false; searched = false; error = nil
        itineraries = []; selected = 0; details = false; showTransfers = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
        publishMap()
    }
    func edit(_ isOrigin: Bool, text: String) {
        invalidate()
        if isOrigin { origin = nil; originText = text } else { destination = nil; destinationText = text }
        editing = isOrigin; publishMap()
    }
    func choose(_ isOrigin: Bool, location: DirectionsLocation) {
        guard location.isValid else { return }
        invalidate()
        if isOrigin { origin = location; originText = location.name } else { destination = location; destinationText = location.name }
        editing = nil; mapPicking = nil; publishMap()
    }
    func swap() {
        invalidate()
        let old = origin; origin = destination; destination = old
        let text = originText; originText = destinationText; destinationText = text
        editing = nil; publishMap()
    }
    func search(session: URLSession = .shared) {
        guard let origin, let destination else { return }
        invalidate(); searched = true; loading = true; editing = nil
        let token = generation
        do {
            let payload = try DirectionsRequest(from: origin, to: destination, date: now ? Date() : time, arriveBy: arriveBy, options: options)
            var urlRequest = URLRequest(url: URL(string: "https://edelweiss.catenarymaps.org/v1/route")!)
            urlRequest.httpMethod = "POST"; urlRequest.timeoutInterval = 120
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(payload)
            request = Task { @MainActor in
                do {
                    let (data, response) = try await session.data(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw DirectionsError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    let plan = try await Task.detached(priority: .userInitiated) {
                        try JSONDecoder().decode(DirectionsPlan.self, from: data)
                    }.value
                    guard token == generation, !Task.isCancelled else { return }
                    itineraries = plan.journeys
                    loading = false; publishMap(fit: true); saveSession()
                } catch {
                    guard token == generation, !Task.isCancelled else { return }
                    self.error = error.localizedDescription; loading = false
                }
            }
        } catch { self.error = error.localizedDescription; loading = false }
    }
    private func publishMap(fit: Bool = false) {
        mapState = DirectionsMapState(visible: visible, origin: origin, destination: destination,
            itineraries: itineraries, selected: selected, details: details, showTransfers: showTransfers, picking: mapPicking,
            fitRevision: fit ? UUID() : mapState.fitRevision)
    }
    private struct Session: Codable {
        var origin: DirectionsLocation; var destination: DirectionsLocation
        var options: DirectionsOptions; var arriveBy: Bool; var now: Bool; var time: Date
        var itineraries: [DirectionsItinerary]; var selected: Int
        var details: Bool?; var showTransfers: Bool?
    }
    private func saveSession() {
        guard !loading, searched, error == nil, !itineraries.isEmpty, let origin, let destination else { return }
        let session = Session(origin: origin, destination: destination, options: options, arriveBy: arriveBy,
            now: now, time: time, itineraries: itineraries, selected: selected, details: details, showTransfers: showTransfers)
        if let data = try? JSONEncoder().encode(session), data.count < 4_000_000 {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }
}

extension DirectionsLocation {
    init(name: String, coordinate: CLLocationCoordinate2D, current: Bool = false) {
        self.init(name: name, lat: coordinate.latitude, lon: coordinate.longitude, isCurrentLocation: current)
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
