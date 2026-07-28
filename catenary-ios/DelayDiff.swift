//
//  DelayDiff.swift
//  catenary-ios
//
//  SwiftUI port of catenary-compose/DelayDiff.kt.
//

import Foundation
import SwiftUI

/// Displays an early/on-time/late difference with the same thresholds and
/// compact unit layout as the Android Compose implementation.
struct DelayDiff: View {
    let diff: Int64
    var showSeconds: Bool = false
    var fontSizeOfPolarity: CGFloat = 12
    var useSymbolSign: Bool = false
    var hideMinUnits: Bool = false
    var locale: Locale = .current

    @Environment(\.colorScheme) private var colorScheme

    private var delayColor: Color {
        if colorScheme == .dark {
            switch diff {
            case ...(-300): return Color(rgb: 0xE53935)
            case ...(-60): return Color(rgb: 0xFDD835)
            case 3_600...: return Color(rgb: 0xFF6467)
            case 300...: return Color(rgb: 0xE53935)
            case 180...: return Color(rgb: 0xFDD835)
            default: return Color(rgb: 0x58A738)
            }
        }

        switch diff {
        case ...(-300): return Color(rgb: 0xE53935)
        case ...(-60): return Color(rgb: 0xE17100)
        case 3_600...: return Color(rgb: 0xD81B60)
        case 300...: return Color(rgb: 0xE53935)
        case 180...: return Color(rgb: 0xE17100)
        default: return Color(rgb: 0x58A738)
        }
    }

    private var components: (hours: UInt64, minutes: UInt64, seconds: UInt64) {
        let remainder = diff.magnitude
        let hours = remainder / 3_600
        let minutes = (remainder - hours * 3_600) / 60
        let seconds = remainder - hours * 3_600 - minutes * 60
        return (hours, minutes, seconds)
    }

    var body: some View {
        let values = components

        HStack(alignment: .firstTextBaseline, spacing: 0) {
            polarity

            if diff != 0 {
                if values.hours > 0 {
                    value(values.hours)
                    unit(DelayDiffLocale.hourMarking(for: locale))
                }

                if values.hours > 0 || values.minutes > 0 || !showSeconds {
                    value(values.minutes)
                    if !hideMinUnits {
                        unit(DelayDiffLocale.minuteMarking(
                            for: locale,
                            showSeconds: showSeconds
                        ))
                    }
                }

                if showSeconds {
                    value(values.seconds)
                    unit(DelayDiffLocale.secondMarking(for: locale))
                }
            } else {
                value(0)
            }
        }
        .foregroundStyle(delayColor)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var polarity: some View {
        if useSymbolSign {
            Text(verbatim: diff < 0 ? "-" : "+")
                .font(.system(size: fontSizeOfPolarity))
        } else {
            Group {
                if diff < 0 {
                    Text(verbatim: NSLocalizedString(
                        "early",
                        value: "Early",
                        comment: "A vehicle is running earlier than scheduled"
                    ))
                } else if diff > 0 {
                    Text(verbatim: NSLocalizedString(
                        "late",
                        value: "Late",
                        comment: "A vehicle is running later than scheduled"
                    ))
                } else {
                    Text(verbatim: NSLocalizedString(
                        "ontime",
                        value: "On time",
                        comment: "A vehicle is running on schedule"
                    ))
                    .fontWeight(.semibold)
                }
            }
            .font(.system(size: fontSizeOfPolarity))

            Text(verbatim: " ")
                .font(.system(size: fontSizeOfPolarity))
        }
    }

    private func value<T: BinaryInteger>(_ value: T) -> some View {
        Text(verbatim: String(value))
            .font(.system(size: 14))
    }

    private func unit(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.system(size: 10))
    }
}

private enum DelayDiffLocale {
    private static func languageCode(for locale: Locale) -> String {
        let identifier = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return identifier.split(separator: "-").first.map(String.init) ?? identifier
    }

    static func hourMarking(for locale: Locale) -> String {
        switch languageCode(for: locale) {
        case "zh": return "小时"
        case "ko": return "시간"
        case "ja": return "時間"
        default: return "h"
        }
    }

    static func minuteMarking(for locale: Locale, showSeconds: Bool) -> String {
        switch languageCode(for: locale) {
        case "zh", "ja": return "分"
        case "ko": return "분"
        default: return showSeconds ? "m" : "min"
        }
    }

    static func secondMarking(for locale: Locale) -> String {
        switch languageCode(for: locale) {
        case "ko": return "초"
        case "zh","ja": return "秒"
        default: return "s"
        }
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}
