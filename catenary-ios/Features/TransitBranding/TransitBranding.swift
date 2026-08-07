import Foundation
import SVGView
import SwiftUI

struct MTASubwayIcon: View {
    let routeID: String
    var size: CGFloat = 24

    var body: some View {
        TransitRemoteSVGImage(
            url: MTASubwayUtils.iconURL(for: routeID),
            accessibilityLabel: routeID
        ) {
            ZStack {
                Circle()
                    .fill(MTASubwayUtils.color(for: routeID))
                Text(MTASubwayUtils.symbolShortName(for: routeID))
                    .font(.system(size: size * 0.58, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

struct NationalRailAgencyLabel: View {
    let agencyID: String?
    let agencyName: String?
    var compact = false

    var body: some View {
        if let resolvedName = NationalRailUtils.resolvedAgencyName(
            agencyID: agencyID,
            agencyName: agencyName
        ) {
            HStack(spacing: 4) {
                if let iconURL = NationalRailUtils.agencyIconURL(
                    agencyID: agencyID,
                    agencyName: agencyName
                ) {
                    TransitRemoteSVGImage(
                        url: iconURL,
                        accessibilityLabel: resolvedName,
                        contentSize: compact ? 14 : 16,
                        showsPlaceholder: false
                    ) {
                        EmptyView()
                    }
                }

                Text(resolvedName)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TransitRemoteSVGImage<Placeholder: View>: View {
    let url: URL?
    let accessibilityLabel: String
    let contentSize: CGFloat?
    let showsPlaceholder: Bool
    private let placeholder: Placeholder

    @State private var svgData: Data?

    init(
        url: URL?,
        accessibilityLabel: String,
        contentSize: CGFloat? = nil,
        showsPlaceholder: Bool = true,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.accessibilityLabel = accessibilityLabel
        self.contentSize = contentSize
        self.showsPlaceholder = showsPlaceholder
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let svgData {
                SVGView(data: svgData)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: contentSize, height: contentSize)
            } else if showsPlaceholder {
                placeholder
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: url?.absoluteString) {
            svgData = nil
            guard let url else { return }

            do {
                var request = URLRequest(
                    url: url,
                    cachePolicy: .returnCacheDataElseLoad,
                    timeoutInterval: 20
                )
                request.setValue("image/svg+xml", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let response = response as? HTTPURLResponse,
                   !(200 ... 299).contains(response.statusCode) {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                svgData = data
            } catch {
                // Retain the SwiftUI fallback if the remote icon cannot be loaded.
            }
        }
    }
}
