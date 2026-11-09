import SwiftUI
import VibeAlarmCore

/// Which option sheet the wake time editor is showing.
enum WakeOptionSheet: String, Identifiable {
    case repeatDays, holiday, snooze
    var id: String { rawValue }
}

/// Repeat: four presets, then each weekday, or a single date when the alarm rings once.
struct RepeatOptionSheet: View {
    @Binding var repeatMode: AlarmRepeatMode
    @Binding var customDays: Set<Weekday>
    @Binding var onceDate: Date
    @Environment(\.dismiss) private var dismiss

    private var isOnce: Bool {
        if case .specificDates = repeatMode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    presetRow("Weekdays", mode: .weekdays)
                    presetRow("Every Day", mode: .everyday)
                    presetRow("Weekends", mode: .weekends)
                    presetRow("Once", mode: .specificDates([AlarmScheduleEngine().dateString(from: onceDate)]))
                }

                if isOnce {
                    Section {
                        DatePicker("Ring once on", selection: Binding(
                            get: { onceDate },
                            set: { newDate in
                                onceDate = newDate
                                repeatMode = .specificDates([AlarmScheduleEngine().dateString(from: newDate)])
                            }
                        ), displayedComponents: .date)
                    }
                } else {
                    Section {
                        ForEach(AlarmFormatting.weekOrder, id: \.self) { day in
                            dayRow(day)
                        }
                    }
                }
            }
            .navigationTitle(AlarmFormatting.repeatTitle(repeatMode))
            .vibeChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func isSelected(_ mode: AlarmRepeatMode) -> Bool {
        switch (mode, repeatMode) {
        case (.weekdays, .weekdays), (.everyday, .everyday), (.weekends, .weekends),
             (.specificDates, .specificDates): return true
        default: return false
        }
    }

    private func presetRow(_ title: String, mode: AlarmRepeatMode) -> some View {
        let on = isSelected(mode)
        return Button {
            repeatMode = mode
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if on {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func dayRow(_ day: Weekday) -> some View {
        let on = AlarmFormatting.activeDays(repeatMode).contains(day)
        return Button {
            var next = AlarmFormatting.activeDays(repeatMode)
            if on { next.remove(day) } else { next.insert(day) }
            customDays = next
            if next == Weekday.standardWeekdays { repeatMode = .weekdays }
            else if next == Set(Weekday.allCases) { repeatMode = .everyday }
            else if next == [.saturday, .sunday] { repeatMode = .weekends }
            else { repeatMode = .customDays(next) }
        } label: {
            HStack {
                Text(day.longName)
                    .foregroundStyle(.primary)
                Spacer()
                if on {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longName)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

struct HolidayOptionSheet: View {
    @Binding var smart: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                option(true, "Smart skip", "Stays quiet on public holidays and leave days, and rings on makeup workdays.")
                option(false, "Always ring", "Rings on every scheduled day, holidays included.")
            }
            .navigationTitle(smart ? "Smart skip" : "Always ring")
            .navigationBarTitleDisplayMode(.inline)
            .vibeChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func option(_ value: Bool, _ title: String, _ detail: String) -> some View {
        Button {
            smart = value
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if smart == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(smart == value ? [.isSelected] : [])
    }
}

struct SnoozeOptionSheet: View {
    let minutes: Int
    let onChange: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(AlarmRule.snoozeIntervalOptions, id: \.self) { option in
                Button {
                    onChange(option)
                } label: {
                    HStack {
                        Text("\(option) min")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Spacer()
                        if option == minutes {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option) minutes")
                .accessibilityAddTraits(option == minutes ? [.isSelected] : [])
            }
            .navigationTitle("\(minutes) min")
            .navigationBarTitleDisplayMode(.inline)
            .vibeChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

extension Weekday {
    var longName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }
}
