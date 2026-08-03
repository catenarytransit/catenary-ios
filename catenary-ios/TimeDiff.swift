//
//  TimeDiff.swift
//  catenary-ios
//
//  SwiftUI port of catenary-compose/DiffTime.kt.
//

import Foundation
import SwiftUI

/// Displays a signed duration using compact, locale-aware unit markings.
///
/// `diff` is expressed in seconds and may be negative. This view is the SwiftUI
/// equivalent of the Compose `DiffTimer` component.
struct TimeDiff: View {
    let diff: TimeInterval
    var showBrackets: Bool = true
    var showSeconds: Bool = false
    var showDays: Bool = false
    var showPlus: Bool = false
    var numSize: CGFloat = 14
    var unitSize: CGFloat = 12
    var bracketSize: CGFloat = 14
    var numberFontWeight: Font.Weight = .regular
    var unitFontWeight: Font.Weight = .regular
    var color: Color? = nil
    var locale: Locale = .current

    private var components: (days: Int, hours: Int, minutes: Int, seconds: Int) {
        var remainder = Int(floor(abs(diff)))
        var days = 0

        if showDays {
            days = remainder / 86_400
            remainder -= days * 86_400
        }

        let hours = remainder / 3_600
        remainder -= hours * 3_600

        let minutes = remainder / 60
        remainder -= minutes * 60

        return (days, hours, minutes, remainder)
    }

    private var signText: String {
        if diff < 0 {
            return "-"
        }
        if diff > 0 && showPlus {
            return "+"
        }
        return ""
    }

    var body: some View {
        let values = components
        let showMinutes = values.hours > 0
            || values.minutes > 0
            || (!showSeconds && diff != 0)

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if showBrackets {
                Text(verbatim: "[")
                    .font(.system(size: bracketSize))
            }

            if !signText.isEmpty {
                Text(verbatim: signText)
                    .font(.system(size: numSize, weight: .bold))
            }

            if values.days > 0 {
                number(values.days)
                unit(TimeDiffLocale.dayMarking(for: locale))
            }

            if values.hours > 0 {
                number(values.hours)
                unit(TimeDiffLocale.hourMarking(for: locale))
            }

            if showMinutes {
                number(values.minutes)
                unit(TimeDiffLocale.minuteMarking(for: locale))
            }

            if showSeconds {
                number(values.seconds)
                unit(TimeDiffLocale.secondMarking(for: locale))
            }

            if showBrackets {
                Text(verbatim: "]")
                    .font(.system(size: bracketSize))
            }
        }
        .foregroundStyle(color ?? Color.primary)
        .accessibilityElement(children: .combine)
    }

    private func number(_ value: Int) -> some View {
        Text(verbatim: String(value))
            .font(.system(size: numSize, weight: numberFontWeight))
    }

    private func unit(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.system(size: unitSize, weight: unitFontWeight))
    }
}

/// Automatically refreshes a `TimeDiff` once per second.
struct SelfUpdatingDiffTimer: View {
    let targetTimeSeconds: Int64
    var showBrackets: Bool = true
    var showSeconds: Bool = false
    var showDays: Bool = false
    var showPlus: Bool = false
    var numSize: CGFloat = 14
    var unitSize: CGFloat = 12
    var bracketSize: CGFloat = 14
    var numberFontWeight: Font.Weight = .regular
    var unitFontWeight: Font.Weight = .regular
    var color: Color? = nil
    var locale: Locale = .current

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            TimeDiff(
                diff: TimeInterval(targetTimeSeconds) - context.date.timeIntervalSince1970,
                showBrackets: showBrackets,
                showSeconds: showSeconds,
                showDays: showDays,
                showPlus: showPlus,
                numSize: numSize,
                unitSize: unitSize,
                bracketSize: bracketSize,
                numberFontWeight: numberFontWeight,
                unitFontWeight: unitFontWeight,
                color: color,
                locale: locale
            )
        }
    }
}

/// Compatibility name matching the Android component.
typealias DiffTimer = TimeDiff

/// A more descriptive alias for new Swift call sites.
typealias SelfUpdatingTimeDiff = SelfUpdatingDiffTimer

private enum TimeDiffLocale {
    private static func normalizedIdentifier(for locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func isTraditionalChinese(_ identifier: String) -> Bool {
        identifier.hasPrefix("zh-tw")
            || identifier.hasPrefix("zh-hk")
            || identifier.contains("hant")
    }

    private static func isChinese(_ identifier: String) -> Bool {
        identifier == "zh" || identifier.hasPrefix("zh-")
    }

    static func hourMarking(for locale: Locale) -> String {
        L10n.string("time.unit.hour.short", defaultValue: "h", locale: locale)
    }

    static func dayMarking(for locale: Locale) -> String {
        L10n.string("time.unit.day.short", defaultValue: "d", locale: locale)
    }

    static func minuteMarking(for locale: Locale) -> String {
        L10n.string("time.unit.minute.short", defaultValue: "min", locale: locale)
    }

    static func secondMarking(for locale: Locale) -> String {
        L10n.string("time.unit.second.short", defaultValue: "s", locale: locale)
    }
}
