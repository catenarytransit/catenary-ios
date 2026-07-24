import SwiftUI

/// Compact date/time control used by nearby departures and stop screens.
/// Drag horizontally to scrub in five-minute increments, or tap for a wheel picker.
struct TransitTimePicker: View {
    @Binding var selectedDate: Date
    @Binding var isNow: Bool
    let timezoneID: String?
    let onCommit: (Date?, Bool) -> Void

    @State private var showingPicker = false
    @State private var dragStartDate: Date?

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isNow ? "clock.badge.checkmark" : "calendar.badge.clock")
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .background(.thinMaterial, in: .capsule)
            .overlay {
                Capsule().stroke(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(scrubGesture)
        .accessibilityHint("Tap to choose a date and time, or drag horizontally to change the time")
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                VStack(spacing: 18) {
                    DatePicker(
                        "Departure time",
                        selection: $selectedDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.timeZone, timezone)

                    Button {
                        isNow = true
                        selectedDate = Date()
                        onCommit(nil, true)
                        showingPicker = false
                    } label: {
                        Label("Use current time", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .navigationTitle("Departure time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isNow = false
                            onCommit(selectedDate, false)
                            showingPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.height(360)])
        }
    }

    private var timezone: TimeZone {
        timezoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    private var label: String {
        if isNow { return "Now" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezone
        formatter.dateStyle = Calendar.current.isDateInToday(selectedDate) ? .none : .medium
        formatter.timeStyle = .short
        return formatter.string(from: selectedDate)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStartDate == nil {
                    dragStartDate = isNow ? Date() : selectedDate
                }
                guard let dragStartDate else { return }
                // Roughly one five-minute step per 12 points. Drag left for later times.
                let steps = Int((-value.translation.width / 12).rounded())
                selectedDate = dragStartDate.addingTimeInterval(TimeInterval(steps * 5 * 60))
                isNow = false
            }
            .onEnded { _ in
                dragStartDate = nil
                onCommit(selectedDate, false)
            }
    }
}
