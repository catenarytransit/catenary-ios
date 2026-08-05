import Combine
import Foundation
import SwiftUI

private struct RouteScreenResponse: Decodable, Sendable {
    let color: String
    let textColor: String
    let agencyName: String?
    let shortName: String?
    let longName: String?
    let url: String?
    let routeType: Int?
    let gtfsDescription: String?
    let alerts: [String: SingleTripAlert]

    enum CodingKeys: String, CodingKey {
        case color
        case textColor = "text_color"
        case agencyName = "agency_name"
        case shortName = "short_name"
        case longName = "long_name"
        case url
        case routeType = "route_type"
        case gtfsDescription = "gtfs_desc"
        case alerts = "alert_id_to_alert"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "007AFF"
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor) ?? "FFFFFF"
        agencyName = try container.decodeIfPresent(String.self, forKey: .agencyName)
        shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
        longName = try container.decodeIfPresent(String.self, forKey: .longName)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        routeType = try container.decodeIfPresent(Int.self, forKey: .routeType)
        gtfsDescription = try container.decodeIfPresent(String.self, forKey: .gtfsDescription)
        alerts = try container.decodeIfPresent([String: SingleTripAlert].self, forKey: .alerts) ?? [:]
    }
}

@MainActor
private final class RouteScreenViewModel: ObservableObject {
    @Published private(set) var route: RouteScreenResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let chateauID: String
    private let routeID: String

    init(chateauID: String, routeID: String) {
        self.chateauID = chateauID
        self.routeID = routeID
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        var components = URLComponents(string: "https://birch.catenarymaps.org/route_info")!
        components.queryItems = [
            URLQueryItem(name: "chateau", value: chateauID),
            URLQueryItem(name: "route_id", value: routeID)
        ]

        guard let url = components.url else {
            isLoading = false
            errorMessage = URLError(.badURL).localizedDescription
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            route = try JSONDecoder().decode(RouteScreenResponse.self, from: data)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct RouteScreen: View {
    let chateauID: String
    let routeID: String

    @StateObject private var model: RouteScreenViewModel
    @State private var alertsPresented = false

    init(chateauID: String, routeID: String) {
        self.chateauID = chateauID
        self.routeID = routeID
        _model = StateObject(
            wrappedValue: RouteScreenViewModel(chateauID: chateauID, routeID: routeID)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let route = model.route {
                    RouteHeading(
                        color: route.color,
                        textColor: route.textColor,
                        routeType: route.routeType,
                        agencyName: route.agencyName,
                        shortName: route.shortName,
                        longName: route.longName,
                        description: route.gtfsDescription,
                        chateauID: chateauID,
                        isCompact: false
                    )

                    if !route.alerts.isEmpty {
                        ServiceAlertsLink(alerts: route.alerts) {
                            alertsPresented = true
                        }
                    }

                    if let routeURL = route.url.flatMap(URL.init(string:)) {
                        Link(destination: routeURL) {
                            Label("Route website", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }
                } else if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let errorMessage = model.errorMessage {
                    CatenaryUnavailableView {
                        Label("Unable to load route", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await model.load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .task(id: "\(chateauID)|\(routeID)") {
            await model.load()
        }
        .fullScreenCover(isPresented: $alertsPresented) {
            ServiceAlertsScreen(
                alerts: model.route?.alerts ?? [:],
                defaultTimezone: nil,
                chateauID: chateauID
            )
        }
    }
}
