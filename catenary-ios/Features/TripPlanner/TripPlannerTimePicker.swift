import SwiftUI

/// HH:mm in a fixed Gregorian/POSIX locale: numeric 24-hour time shouldn't depend on the device's
/// (sometimes exotic) locale, which can otherwise make `Date.FormatStyle`'s `.shortened` convenience
/// silently return an empty string.
func tripPlannerClockLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_GB_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

/// Weekday + day + month in the device's locale (e.g. "Mon 9 Nov"), or "Today" for the current day.
func tripPlannerDayLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return L10n.string("Today") }
    let locale = Locale.autoupdatingCurrent
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEE d MMM", options: 0, locale: locale) ?? "EEE d MMM"
    return formatter.string(from: date)
}

/// Ported from catenary-compose's DateTimePicker.kt (TimeSelectorDialog), presented as a bottom
/// sheet like the home screen's departure-time picker instead of a floating dialog.
/// Changes are staged locally and only committed to the caller when "Done" is tapped.
struct TripPlannerTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Date
    @State private var selectedHour: Int
    @State private var selectedMinute: Int
    @State private var lockToNow: Bool
    @State private var arriveBy: Bool
    let onConfirm: (Date, Bool, Bool) -> Void

    init(time: Date, isNow: Bool, arriveBy: Bool, onConfirm: @escaping (Date, Bool, Bool) -> Void) {
        let calendar = Calendar.current
        let reference = isNow ? Date() : time
        _selectedDay = State(initialValue: calendar.startOfDay(for: reference))
        _selectedHour = State(initialValue: calendar.component(.hour, from: reference))
        _selectedMinute = State(initialValue: calendar.component(.minute, from: reference))
        _lockToNow = State(initialValue: isNow)
        _arriveBy = State(initialValue: arriveBy)
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose time").font(.title2.weight(.semibold))
                Text(TimeZone.current.identifier).font(.footnote).foregroundStyle(.secondary)
            }
            DepartureArrivalToggle(arriveBy: Binding(
                get: { arriveBy },
                set: { newValue in
                    arriveBy = newValue
                    if newValue { lockToNow = false }
                }
            ))
            HStack(spacing: 12) {
                Picker("", selection: Binding(get: { selectedDay }, set: { selectedDay = $0; lockToNow = false })) {
                    ForEach(dayOptions, id: \.self) { day in Text(dayLabel(day)).tag(day) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                Picker("", selection: Binding(get: { selectedHour }, set: { selectedHour = $0; lockToNow = false })) {
                    ForEach(0..<24, id: \.self) { hour in Text(String(format: "%02d", hour)).tag(hour) }
                }
                .pickerStyle(.wheel)
                .frame(width: 70)
                Picker("", selection: Binding(get: { selectedMinute }, set: { selectedMinute = $0; lockToNow = false })) {
                    ForEach(0..<60, id: \.self) { minute in Text(String(format: "%02d", minute)).tag(minute) }
                }
                .pickerStyle(.wheel)
                .frame(width: 70)
            }
            .frame(height: 170)
            // "Now" is a one-way action: it can only turn the lock on; adjusting any wheel turns it back off.
            Button {
                lockToNow = true
                if arriveBy { arriveBy = false }
                let now = Date()
                selectedDay = Calendar.current.startOfDay(for: now)
                selectedHour = Calendar.current.component(.hour, from: now)
                selectedMinute = Calendar.current.component(.minute, from: now)
            } label: {
                Text("Now").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button {
                    onConfirm(lockToNow ? Date() : combinedDate, lockToNow, arriveBy)
                    dismiss()
                } label: { Text(doneLabel) }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var dayOptions: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = min(calendar.date(byAdding: .day, value: -30, to: today) ?? today, selectedDay)
        let end = max(calendar.date(byAdding: .day, value: 30, to: today) ?? today, selectedDay)
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
    private func dayLabel(_ day: Date) -> String { tripPlannerDayLabel(day) }
    private var combinedDate: Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDay)
        components.hour = selectedHour; components.minute = selectedMinute
        return Calendar.current.date(from: components) ?? selectedDay
    }
    private var doneLabel: String {
        let date = lockToNow ? Date() : combinedDate
        return "\(L10n.string("Done")) • \(tripPlannerClockLabel(date))"
    }
}

/// Rounded two-position toggle with its labels inside the track, matching Compose's DepartureArrivalSlider.
private struct DepartureArrivalToggle: View {
    @Binding var arriveBy: Bool
    var body: some View {
        GeometryReader { proxy in
            let halfWidth = proxy.size.width / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                Capsule().fill(Color.accentColor.opacity(0.85))
                    .frame(width: halfWidth)
                    .offset(x: arriveBy ? halfWidth : 0)
                    .animation(.easeInOut(duration: 0.2), value: arriveBy)
                HStack(spacing: 0) {
                    option("Departure", selected: !arriveBy) { arriveBy = false }
                    option("Arrival", selected: arriveBy) { arriveBy = true }
                }
            }
        }
        .frame(height: 48)
    }
    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}
