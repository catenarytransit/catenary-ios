import Foundation

struct CondensedAlertSchedule: Equatable, Sendable {
    let isCondensed: Bool
    let baseRule: String
    let weekdayRules: String
    let exceptions: String
    let fallbackPeriods: [SingleTripAlertActivePeriod]
}

func condenseActivePeriods(
    periods: [SingleTripAlertActivePeriod],
    locale: Locale = Locale(identifier: "en_CA"),
    defaultTimezone: String? = nil
) -> CondensedAlertSchedule {
    guard !periods.isEmpty else { return fallbackAlertSchedule([]) }

    let completePeriods = periods.compactMap { period -> CompleteAlertPeriod? in
        guard let start = period.start, let end = period.end else { return nil }
        return CompleteAlertPeriod(start: start, end: end)
    }

    guard completePeriods.count == periods.count, completePeriods.count > 3 else {
        return fallbackAlertSchedule(periods)
    }

    let timeZone = resolveAlertTimeZone(defaultTimezone)
    let language = alertScheduleLanguage(locale)
    let calendar = alertCalendar(timeZone: timeZone)
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_GB")
    timeFormatter.calendar = calendar
    timeFormatter.timeZone = timeZone
    timeFormatter.dateFormat = "HH:mm"

    let nights = completePeriods.map { period -> AlertNight in
        let start = Date(timeIntervalSince1970: TimeInterval(period.start))
        let end = Date(timeIntervalSince1970: TimeInterval(period.end))
        let startWeekday = formatAlertWeekday(start, locale: locale, timeZone: timeZone)
        let endWeekday = formatAlertWeekday(end, locale: locale, timeZone: timeZone)
        let weekdayPair = calendar.isDate(start, inSameDayAs: end)
            ? startWeekday
            : "\(startWeekday)/\(endWeekday)"

        return AlertNight(
            originalStart: start,
            startEpochSecond: period.start,
            startTime: timeFormatter.string(from: start),
            endTime: timeFormatter.string(from: end),
            weekdayPair: weekdayPair,
            label: formatAlertNightLabel(
                start: start,
                end: end,
                locale: locale,
                language: language,
                timeZone: timeZone
            )
        )
    }
    .sorted { $0.startEpochSecond < $1.startEpochSecond }

    var patternOrder: [String] = []
    var patternCounts: [String: Int] = [:]
    for night in nights {
        let key = "\(night.startTime)|\(night.endTime)"
        if patternCounts[key] == nil { patternOrder.append(key) }
        patternCounts[key, default: 0] += 1
    }

    let mostFrequentPattern = patternOrder.reduce(nil as String?) { currentBest, candidate in
        guard let currentBest else { return candidate }
        return patternCounts[candidate, default: 0] > patternCounts[currentBest, default: 0]
            ? candidate
            : currentBest
    }
    guard let bestPattern = mostFrequentPattern else {
        return fallbackAlertSchedule(periods)
    }

    let baseStart = String(bestPattern.prefix { $0 != "|" })
    let baseEnd = String(bestPattern.drop { $0 != "|" }.dropFirst())
    let deviations = nights.filter { $0.startTime != baseStart || $0.endTime != baseEnd }

    var deviationOrder: [String] = []
    var groupedDeviations: [String: [AlertNight]] = [:]
    for night in deviations {
        let key = "\(night.weekdayPair)|\(night.startTime)|\(night.endTime)"
        if groupedDeviations[key] == nil { deviationOrder.append(key) }
        groupedDeviations[key, default: []].append(night)
    }

    var weekdayRules: [String] = []
    var exceptions: [AlertNight] = []

    for key in deviationOrder {
        guard let group = groupedDeviations[key], let sample = group.first else { continue }
        if group.count >= 2 {
            let start = replaceAlertTimeSeparator(sample.startTime, language: language)
            let end = replaceAlertTimeSeparator(sample.endTime, language: language)

            if sample.startTime == baseStart {
                switch language {
                case "de": weekdayRules.append("\(sample.weekdayPair) bis \(end) Uhr")
                case "fr": weekdayRules.append("\(sample.weekdayPair) jusqu’à \(end)")
                case "it": weekdayRules.append("\(sample.weekdayPair) fino alle \(end)")
                default: weekdayRules.append("\(sample.weekdayPair) until \(end)")
                }
            } else {
                switch language {
                case "de": weekdayRules.append("\(sample.weekdayPair) \(start)–\(end) Uhr")
                case "fr": weekdayRules.append("\(sample.weekdayPair) de \(start) à \(end)")
                default: weekdayRules.append("\(sample.weekdayPair) \(start)–\(end)")
                }
            }
        } else {
            exceptions.append(sample)
        }
    }

    let exceptionText = exceptions.map { exception -> String in
        let start = replaceAlertTimeSeparator(exception.startTime, language: language)
        let end = replaceAlertTimeSeparator(exception.endTime, language: language)
        switch language {
        case "fr": return "\(exception.label), de \(start) à \(end)"
        case "de": return "\(exception.label), \(start)–\(end) Uhr"
        default: return "\(exception.label), \(start)–\(end)"
        }
    }

    let ruleSeparator = ["de", "fr", "it"].contains(language) ? ", " : "; "
    let rules = weekdayRules.joined(separator: ruleSeparator)
    let firstLabel = nights.first?.label ?? ""
    let lastLabel = nights.last?.label ?? ""
    let start = replaceAlertTimeSeparator(baseStart, language: language)
    let end = replaceAlertTimeSeparator(baseEnd, language: language)
    let firstYear = calendar.component(.year, from: nights.first?.originalStart ?? Date())
    let lastYear = calendar.component(.year, from: nights.last?.originalStart ?? Date())
    let currentYear = calendar.component(.year, from: Date())
    let showYear = firstYear != lastYear || lastYear != currentYear
    let yearSuffix = showYear ? " \(lastYear)" : ""
    let commaYearSuffix = showYear ? ", \(lastYear)" : ""

    let baseRule: String
    let exceptionsRule: String
    switch language {
    case "de":
        baseRule = "Nächte \(firstLabel)–\(lastLabel)\(yearSuffix), jeweils \(start)–\(end) Uhr"
        exceptionsRule = exceptionText.isEmpty ? "" : "Ausnahmen: \(exceptionText.joined(separator: "; "))"
    case "fr":
        baseRule = "Nuits du \(firstLabel) au \(lastLabel)\(yearSuffix), de \(start) à \(end)"
        exceptionsRule = exceptionText.isEmpty ? "" : "Exceptions : \(exceptionText.joined(separator: "; "))"
    case "it":
        baseRule = "Notti dal \(firstLabel) all’\(lastLabel)\(yearSuffix), \(start)–\(end)"
        exceptionsRule = exceptionText.isEmpty ? "" : "Eccezioni: \(exceptionText.joined(separator: "; "))"
    default:
        baseRule = "Nights \(firstLabel)–\(lastLabel)\(commaYearSuffix), \(start)–\(end)"
        exceptionsRule = exceptionText.isEmpty ? "" : "Exceptions: \(exceptionText.joined(separator: "; "))"
    }

    return CondensedAlertSchedule(
        isCondensed: true,
        baseRule: baseRule,
        weekdayRules: rules,
        exceptions: exceptionsRule,
        fallbackPeriods: []
    )
}

private struct CompleteAlertPeriod {
    let start: Int64
    let end: Int64
}

private struct AlertNight {
    let originalStart: Date
    let startEpochSecond: Int64
    let startTime: String
    let endTime: String
    let weekdayPair: String
    let label: String
}

private func fallbackAlertSchedule(
    _ periods: [SingleTripAlertActivePeriod]
) -> CondensedAlertSchedule {
    CondensedAlertSchedule(
        isCondensed: false,
        baseRule: "",
        weekdayRules: "",
        exceptions: "",
        fallbackPeriods: periods
    )
}

private func resolveAlertTimeZone(_ identifier: String?) -> TimeZone {
    guard let identifier, !identifier.isEmpty, let timeZone = TimeZone(identifier: identifier) else {
        return .autoupdatingCurrent
    }
    return timeZone
}

private func alertCalendar(timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

private func alertScheduleLanguage(_ locale: Locale) -> String {
    locale.language.languageCode?.identifier.lowercased()
        ?? locale.identifier.split(separator: "_").first.map(String.init)?.lowercased()
        ?? "en"
}

private func formatAlertWeekday(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateFormat = "EEE"
    let value = formatter.string(from: date).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard let first = value.first else { return value }
    return String(first).uppercased(with: locale) + value.dropFirst()
}

private func replaceAlertTimeSeparator(_ value: String, language: String) -> String {
    switch language {
    case "de", "it": return value.replacingOccurrences(of: ":", with: ".", options: [], range: value.range(of: ":"))
    case "fr": return value.replacingOccurrences(of: ":", with: "h", options: [], range: value.range(of: ":"))
    default: return value
    }
}

private func formatAlertNightLabel(
    start: Date,
    end: Date,
    locale: Locale,
    language: String,
    timeZone: TimeZone
) -> String {
    let calendar = alertCalendar(timeZone: timeZone)
    let sameDay = calendar.isDate(start, inSameDayAs: end)
    let startDay = calendar.component(.day, from: start)
    let endDay = calendar.component(.day, from: end)
    let endMonth = calendar.component(.month, from: end)

    switch language {
    case "de":
        let endDate = String(format: "%02d.%02d.", endDay, endMonth)
        return sameDay ? endDate : String(format: "%02d./%@", startDay, endDate)

    case "fr", "it":
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: start).lowercased(with: locale)
        return sameDay ? "\(startDay) \(month)" : "\(startDay)/\(endDay) \(month)"

    default:
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM"
        let month = formatter.string(from: start)
        return sameDay ? "\(month) \(startDay)" : "\(month) \(startDay)/\(endDay)"
    }
}
