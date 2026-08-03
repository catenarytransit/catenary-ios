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
    let calendar = alertCalendar(timeZone: timeZone)
    let timeFormatter = DateFormatter()
    timeFormatter.locale = locale
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
            if sample.startTime == baseStart {
                weekdayRules.append(L10n.format(
                    "alert.schedule.weekday_until",
                    defaultValue: "%1$@ until %2$@",
                    locale: locale,
                    sample.weekdayPair,
                    sample.endTime
                ))
            } else {
                weekdayRules.append(L10n.format(
                    "alert.schedule.weekday_range",
                    defaultValue: "%1$@ %2$@–%3$@",
                    locale: locale,
                    sample.weekdayPair,
                    sample.startTime,
                    sample.endTime
                ))
            }
        } else {
            exceptions.append(sample)
        }
    }

    let exceptionText = exceptions.map { exception -> String in
        L10n.format(
            "alert.schedule.exception_range",
            defaultValue: "%1$@, %2$@–%3$@",
            locale: locale,
            exception.label,
            exception.startTime,
            exception.endTime
        )
    }

    let rules = weekdayRules.joined(separator: "; ")
    let firstLabel = nights.first?.label ?? ""
    let lastLabel = nights.last?.label ?? ""
    let start = baseStart
    let end = baseEnd
    let firstYear = calendar.component(.year, from: nights.first?.originalStart ?? Date())
    let lastYear = calendar.component(.year, from: nights.last?.originalStart ?? Date())
    let currentYear = calendar.component(.year, from: Date())
    let showYear = firstYear != lastYear || lastYear != currentYear
    let yearSuffix = showYear ? " \(lastYear)" : ""
    let commaYearSuffix = showYear ? ", \(lastYear)" : ""

    let baseRule = L10n.format(
        "alert.schedule.base_rule",
        defaultValue: "Nights %1$@–%2$@%3$@, %4$@–%5$@",
        locale: locale,
        firstLabel,
        lastLabel,
        showYear ? yearSuffix : commaYearSuffix,
        start,
        end
    )
    let exceptionsRule = exceptionText.isEmpty
        ? ""
        : L10n.format(
            "alert.schedule.exceptions",
            defaultValue: "Exceptions: %1$@",
            locale: locale,
            exceptionText.joined(separator: "; ")
        )

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

private func formatAlertNightLabel(
    start: Date,
    end: Date,
    locale: Locale,
    timeZone: TimeZone
) -> String {
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: start, to: end)
}
