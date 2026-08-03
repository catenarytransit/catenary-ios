import Combine
import Foundation

@MainActor
final class VehicleHistoryViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var history: VehicleHistoryLookupResponse?
    @Published private(set) var errorMessage: String?

    let selection: VehicleHistorySelection

    private let session: URLSession
    private var hasLoaded = false

    init(
        selection: VehicleHistorySelection,
        session: URLSession = .shared
    ) {
        self.selection = selection
        self.session = session
    }

    func load(force: Bool = false) async {
        if hasLoaded, !force { return }
        hasLoaded = true
        isLoading = true
        errorMessage = nil
        if force { history = nil }

        var components = URLComponents(
            string: "https://birch.catenarymaps.org/vehicle_history_lookup"
        )!
        components.queryItems = [
            URLQueryItem(name: "vehicle", value: selection.vehicleID),
            URLQueryItem(name: "chateau", value: selection.chateauID)
        ]
        if let routeID = nonEmpty(selection.routeID) {
            components.queryItems?.append(URLQueryItem(name: "route_id", value: routeID))
        }

        guard let url = components.url else {
            isLoading = false
            errorMessage = URLError(.badURL).localizedDescription
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 404 {
                history = .empty
            } else if (200..<300).contains(httpResponse.statusCode) {
                history = try JSONDecoder().decode(VehicleHistoryLookupResponse.self, from: data)
            } else {
                let serverMessage = try? JSONDecoder()
                    .decode(VehicleHistoryLookupErrorResponse.self, from: data)
                    .error
                    .message
                throw VehicleHistoryRequestError.http(
                    statusCode: httpResponse.statusCode,
                    message: serverMessage
                )
            }
        } catch is CancellationError {
            hasLoaded = false
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private enum VehicleHistoryRequestError: LocalizedError {
    case http(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case let .http(statusCode, message):
            if let message, !message.isEmpty { return message }
            return L10n.format(
                "vehicle_history.request_failed",
                defaultValue: "Vehicle history request failed (%d).",
                statusCode
            )
        }
    }
}
