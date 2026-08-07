import SwiftUI

/// Broad transit categories shared by the nearby and station departure screens.
enum TransitDisplayMode: String, CaseIterable, Hashable, Identifiable {
    case rail
    case metro
    case bus
    case other

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .rail: return "Rail"
        case .metro: return "Metro/Tram"
        case .bus: return "Bus"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .rail: return "train.side.front.car"
        case .metro: return "tram.fill"
        case .bus: return "bus.fill"
        case .other: return "ferry.fill"
        }
    }

    static func from(routeType: Int?) -> TransitDisplayMode {
        switch routeType {
        case 3, 11, 700:
            return .bus
        case 0, 1, 5, 7, 12, 900:
            return .metro
        case 2, 100, 101, 102, 103, 106, 107:
            return .rail
        default:
            return .other
        }
    }
}

struct TransitModePicker: View {
    let availableModes: [TransitDisplayMode]
    @Binding var selectedModes: Set<TransitDisplayMode>
    var compact = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: compact ? 6 : 8) {
                ForEach(availableModes) { mode in
                    let selected = selectedModes.contains(mode)
                    Button {
                        if selected && selectedModes.count > 1 {
                            selectedModes.remove(mode)
                        } else {
                            selectedModes.insert(mode)
                        }
                    } label: {
                        Label(mode.label, systemImage: mode.symbol)
                            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                            .padding(.horizontal, compact ? 9 : 11)
                            .padding(.vertical, compact ? 5 : 7)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }
}

struct TransitRouteBadge: View {
    let shortName: String?
    let longName: String?
    let colorHex: String?
    let textColorHex: String?
    let chateauID: String?

    init(
        shortName: String?,
        longName: String?,
        colorHex: String?,
        textColorHex: String?,
        chateauID: String? = nil
    ) {
        self.shortName = shortName
        self.longName = longName
        self.colorHex = colorHex
        self.textColorHex = textColorHex
        self.chateauID = chateauID
    }

    @ViewBuilder
    var body: some View {
        if let mtaRouteID {
            MTASubwayIcon(routeID: mtaRouteID, size: 24)
        } else {
            Text(displayName)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .foregroundStyle(Color.transitHex(textColorHex, fallback: .white))
                .background(Color.transitHex(colorHex, fallback: .secondary), in: .rect(cornerRadius: 6))
                .accessibilityLabel(Text(verbatim: L10n.format(
                    "route.accessibility",
                    defaultValue: "Route %@",
                    displayName
                )))
        }
    }

    private var mtaRouteID: String? {
        guard chateauID == MTASubwayUtils.chateauID,
              let candidate = nonBlank(shortName),
              MTASubwayUtils.isSubwayRouteID(candidate) else {
            return nil
        }
        return candidate
    }

    private var displayName: String {
        nonBlank(shortName)
            ?? nonBlank(longName)
            ?? L10n.string("Route")
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

enum TransitFormatting {
    static func date(
        _ epochSeconds: Int64?,
        timezoneID: String?,
        dateStyle: DateFormatter.Style = .none,
        showSeconds: Bool = false
    ) -> String {
        guard let epochSeconds else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_GB_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
        let time = timeFormatter.string(from: date)

        guard dateStyle != .none else { return time }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = timeZone
        dateFormatter.dateStyle = dateStyle
        dateFormatter.timeStyle = .none
        return "\(dateFormatter.string(from: date)) \(time)"
    }

    static func day(_ epochSeconds: Int64, timezoneID: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    static func relative(_ epochSeconds: Int64?, now: Date = Date()) -> String? {
        guard let epochSeconds else { return nil }
        let seconds = Int(Date(timeIntervalSince1970: TimeInterval(epochSeconds)).timeIntervalSince(now))
        if seconds <= -60 { return L10n.string("Departed") }
        if abs(seconds) < 60 { return L10n.string("Now") }
        let minutes = Int((Double(seconds) / 60.0).rounded())
        if minutes < 60 {
            return L10n.format("time.in_minutes", defaultValue: "in %d min", minutes)
        }
        return nil
    }

    static func distance(_ meters: Double, useImperial: Bool = false) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        formatter.numberFormatter.minimumFractionDigits = 0

        if useImperial {
            let feet = Measurement(value: meters, unit: UnitLength.meters)
                .converted(to: .feet)
            return formatter.string(from: feet.value < 5_280
                ? feet
                : Measurement(value: meters, unit: UnitLength.meters).converted(to: .miles))
        }

        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return formatter.string(from: meters < 1_000
            ? measurement
            : measurement.converted(to: .kilometers))
    }

    static func delay(scheduled: Int64?, realtime: Int64?) -> String? {
        guard let scheduled, let realtime else { return nil }
        let delta = realtime - scheduled
        guard abs(delta) >= 60 else { return nil }
        let minutes = Int(abs(delta) / 60)
        return delta > 0 ? "+\(minutes) min" : "−\(minutes) min"
    }
}

extension Color {
    static func transitHex(_ value: String?, fallback: Color) -> Color {
        guard var value else { return fallback }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return fallback }
        return Color(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
