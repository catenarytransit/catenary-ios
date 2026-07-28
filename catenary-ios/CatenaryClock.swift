//
//  CatenaryClock.swift
//  catenary-ios
//
//  SwiftUI port of catenary-compose/CatenaryClock.kt.
//

import Foundation
import SwiftUI

enum CatenaryTextDecoration {
    case none
    case underline
    case strikethrough
}

/// Formats a Unix timestamp in a supplied IANA time zone using a 24-hour clock.
/// Seconds can use a different font from the hour-and-minute portion.
struct FormattedTimeText: View {
    let timezone: String
    let timeSeconds: Int64
    var showSeconds: Bool = false
    var color: Color? = nil
    var textDecoration: CatenaryTextDecoration = .none
    var font: Font? = nil
    var secondsFont: Font? = nil

    private var timeParts: (main: String, seconds: String) {
        guard let timeZone = TimeZone(identifier: timezone) else {
            return ("Invalid Timezone", "")
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timeSeconds))
        let mainFormatter = Self.makeFormatter(format: "HH:mm", timeZone: timeZone)
        let main = mainFormatter.string(from: date)

        guard showSeconds else {
            return (main, "")
        }

        let secondsFormatter = Self.makeFormatter(format: ":ss", timeZone: timeZone)
        return (main, secondsFormatter.string(from: date))
    }

    var body: some View {
        decoratedText
            .foregroundStyle(color ?? Color.primary)
            .accessibilityLabel(Text(verbatim: timeParts.main + timeParts.seconds))
    }

    private var decoratedText: Text {
        let parts = timeParts
        var text = Text(verbatim: parts.main).font(font)

        if showSeconds {
            text = Text("\(text) \(Text(verbatim: parts.seconds).font(secondsFont ?? font))")
        }

        switch textDecoration {
        case .none:
            return text
        case .underline:
            return text.underline()
        case .strikethrough:
            return text.strikethrough()
        }
    }

    private static func makeFormatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}

/// Alternate semantic name for call sites that prefer a clock-oriented type.
typealias CatenaryClock = FormattedTimeText
