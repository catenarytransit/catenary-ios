import Foundation
import SwiftUI

struct VehicleHistoryScreen: View {
    let selection: VehicleHistorySelection

    @EnvironmentObject private var viewObject: viewObject
    @Environment(\.locale) private var locale
    @StateObject private var model: VehicleHistoryViewModel
    @AppStorage("showSeconds") private var showSeconds = false
    @State private var newestFirst = true

    init(selection: VehicleHistorySelection) {
        self.selection = selection
        _model = StateObject(
            wrappedValue: VehicleHistoryViewModel(selection: selection)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 12)

                if model.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                } else if let errorMessage = model.errorMessage {
                    CatenaryUnavailableView {
                        Label {
                            Text(
                                verbatim: L10n.string(
                                    "vehicle_history.unable_to_load",
                                    defaultValue: "Unable to load vehicle history"
                                )
                            )
                        } icon: {
                            Image(systemName: "wifi.exclamationmark")
                        }
                    } description: {
                        Text(verbatim: errorMessage)
                            .textSelection(.enabled)
                    } actions: {
                        Button {
                            Task { await model.load(force: true) }
                        } label: {
                            Text(verbatim: L10n.string("Retry"))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                } else if sections.isEmpty {
                    CatenaryUnavailableView {
                        Label {
                            Text(
                                verbatim: L10n.string(
                                    "vehicle_history.no_history",
                                    defaultValue: "No history available"
                                )
                            )
                        } icon: {
                            Image(systemName: "clock.badge.questionmark")
                        }
                    } description: {
                        Text(
                            verbatim: L10n.string(
                                "vehicle_history.no_history_description",
                                defaultValue: "No previous trips were found for this vehicle."
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(sections) { section in
                        historySection(section)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .task(id: selection) {
            await model.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(
                    verbatim: L10n.string(
                        "vehicle_history.title",
                        defaultValue: "Vehicle History"
                    )
                )
                .font(.title2.bold())

                Spacer()

                Button {
                    newestFirst.toggle()
                } label: {
                    Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .catenaryCircularButtonBorderShape()
                .accessibilityLabel(
                    newestFirst
                        ? L10n.string(
                            "vehicle_history.sort_oldest_first",
                            defaultValue: "Show oldest first"
                        )
                        : L10n.string(
                            "vehicle_history.sort_newest_first",
                            defaultValue: "Show newest first"
                        )
                )
            }

            if let agencyName = nonEmpty(model.history?.agencyName) {
                Text(verbatim: agencyName)
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 4) {
                Text(verbatim: L10n.string("Vehicle"))
                    .foregroundStyle(.secondary)
                Text(verbatim: selection.vehicleID)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func historySection(_ section: VehicleHistorySection) -> some View {
        Text(verbatim: serviceDateLabel(section.operationDate))
            .font(.subheadline.weight(.semibold))
            .padding(.top, 12)
            .padding(.bottom, 4)

        columnHeadings
        Divider()

        ForEach(section.rows) { row in
            historyRow(row)
            Divider()
        }
    }

    private var columnHeadings: some View {
        HStack(spacing: 0) {
            columnHeading(
                L10n.string("vehicle_history.time", defaultValue: "Time"),
                width: timeColumnWidth,
                alignment: .leading
            )
            columnHeading(L10n.string("Route"), width: 58, alignment: .leading)
            Text(verbatim: L10n.string("Headsign"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnHeading(L10n.string("Block"), width: 72, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func columnHeading(
        _ title: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(verbatim: title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func historyRow(_ row: VehicleHistoryRow) -> some View {
        let route = model.history?.routes[row.routeID]
        let timezone = model.history?.agencyTimezone ?? "UTC"

        return HStack(spacing: 0) {
            Group {
                if let unixStartTime = row.unixStartTime {
                    FormattedTimeText(
                        timezone: timezone,
                        timeSeconds: unixStartTime,
                        showSeconds: showSeconds,
                        font: .caption.monospacedDigit().weight(.semibold),
                        secondsFont: .caption2.monospacedDigit()
                    )
                } else {
                    Text("—")
                        .font(.caption.monospacedDigit())
                }
            }
            .frame(width: timeColumnWidth, alignment: .leading)

            routeBadge(route, routeID: row.routeID)
                .frame(width: 58, alignment: .leading)

            Button {
                viewObject.push(
                    .singleTrip(
                        chateauID: selection.chateauID,
                        tripID: row.tripID,
                        routeID: row.routeID,
                        startTime: gtfsStartTime(for: row, timezone: timezone),
                        startDate: row.operationDate.replacingOccurrences(of: "-", with: ""),
                        vehicleID: selection.vehicleID,
                        routeType: route?.routeType
                    )
                )
            } label: {
                Text(verbatim: row.displayHeadsign)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .underline()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let blockID = nonEmpty(row.blockID) {
                Button {
                    viewObject.push(
                        .block(
                            chateauID: selection.chateauID,
                            blockID: blockID,
                            serviceDate: row.operationDate
                        )
                    )
                } label: {
                    Text(verbatim: blockID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                        .underline()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 72, alignment: .trailing)
                }
                .buttonStyle(.plain)
            } else {
                Text("—")
                    .font(.caption2.monospaced())
                    .frame(width: 72, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func routeBadge(
        _ route: VehicleHistoryRoute?,
        routeID: String
    ) -> some View {
        Text(verbatim: route?.displayName ?? routeID)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                vehicleHistoryColor(route?.textColor, fallback: .primary)
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                vehicleHistoryColor(
                    route?.color,
                    fallback: Color(uiColor: .secondarySystemBackground)
                ),
                in: .rect(cornerRadius: 4)
            )
            .frame(maxWidth: 54, alignment: .leading)
    }

    private var timeColumnWidth: CGFloat {
        showSeconds ? 78 : 62
    }

    private var sections: [VehicleHistorySection] {
        guard let rows = model.history?.tripHistory, !rows.isEmpty else { return [] }
        let grouped = Dictionary(grouping: rows, by: \.operationDate)
        let dates = grouped.keys.sorted { newestFirst ? $0 > $1 : $0 < $1 }

        return dates.map { operationDate in
            let rows = (grouped[operationDate] ?? []).sorted { left, right in
                switch (left.unixStartTime, right.unixStartTime) {
                case let (leftTime?, rightTime?) where leftTime != rightTime:
                    return newestFirst ? leftTime > rightTime : leftTime < rightTime
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return left.tripID < right.tripID
                }
            }
            return VehicleHistorySection(operationDate: operationDate, rows: rows)
        }
    }

    private func serviceDateLabel(_ value: String) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return value }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        ) else {
            return value
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // Ramonda uses GTFS start_time to distinguish repeated/frequency trips.
    // This converts Birch's absolute timestamp back to seconds after the
    // service-date midnight; displayed clock text still uses FormattedTimeText.
    private func gtfsStartTime(
        for row: VehicleHistoryRow,
        timezone: String
    ) -> String? {
        guard let unixStartTime = row.unixStartTime,
              let timeZone = TimeZone(identifier: timezone) else {
            return nil
        }

        let parts = row.operationDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let serviceMidnight = calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        ) else {
            return nil
        }

        let gtfsSeconds = unixStartTime - Int64(serviceMidnight.timeIntervalSince1970)
        guard gtfsSeconds >= 0 else { return nil }

        let hours = gtfsSeconds / 3_600
        let minutes = (gtfsSeconds % 3_600) / 60
        let seconds = gtfsSeconds % 60
        return String(format: "%02lld:%02lld:%02lld", hours, minutes, seconds)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func vehicleHistoryColor(
        _ value: String?,
        fallback: Color
    ) -> Color {
        guard let value else { return fallback }
        let normalized = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6,
              let rgb = UInt64(normalized, radix: 16) else {
            return fallback
        }

        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private struct VehicleHistorySection: Identifiable {
    let operationDate: String
    let rows: [VehicleHistoryRow]

    var id: String { operationDate }
}
