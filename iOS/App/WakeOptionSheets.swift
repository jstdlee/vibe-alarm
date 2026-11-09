import SwiftUI
import VibeAlarmCore

/// Which option sheet the wake time editor is showing.
enum WakeOptionSheet: String, Identifiable {
    case repeatDays
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
