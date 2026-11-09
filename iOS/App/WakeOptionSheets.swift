import SwiftUI
import VibeAlarmCore

/// Which option sheet the wake time editor is showing.
enum WakeOptionSheet: String, Identifiable {
    case repeatDays, holiday, snooze
    var id: String { rawValue }
}

private struct OptionSheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(VibePalette.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VibePalette.amber)
                    .frame(minHeight: 44)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VibePalette.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(VibePalette.paper)
    }
}

struct RepeatOptionSheet: View {
    @Binding var repeatMode: AlarmRepeatMode
    @Binding var customDays: Set<Weekday>
    @Binding var onceDate: Date

    private var isOnce: Bool {
        if case .specificDates = repeatMode { return true }
        return false
    }

    var body: some View {
        OptionSheetFrame(title: AlarmFormatting.repeatTitle(repeatMode)) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                shortcut("Weekdays", mode: .weekdays)
                shortcut("Every Day", mode: .everyday)
                shortcut("Weekends", mode: .weekends)
                shortcut("Once", mode: .specificDates([AlarmScheduleEngine().dateString(from: onceDate)]))
            }

            if isOnce {
                HStack {
                    Text("Ring once on")
                        .font(.body)
                        .foregroundStyle(VibePalette.inkSoft)
                    Spacer()
                    DatePicker("Date", selection: Binding(
                        get: { onceDate },
                        set: { newDate in
                            onceDate = newDate
                            repeatMode = .specificDates([AlarmScheduleEngine().dateString(from: newDate)])
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .tint(VibePalette.amber)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .recessedWell(corner: 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(AlarmFormatting.weekOrder.enumerated()), id: \.element) { index, day in
                            dayRow(day)
                            if index < 6 { Hairline(inset: 16) }
                        }
                    }
                    .recessedWell(corner: 14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func isSelected(_ mode: AlarmRepeatMode) -> Bool {
        switch (mode, repeatMode) {
        case (.weekdays, .weekdays), (.everyday, .everyday), (.weekends, .weekends),
             (.specificDates, .specificDates): return true
        default: return false
        }
    }

    private func shortcut(_ title: String, mode: AlarmRepeatMode) -> some View {
        let on = isSelected(mode)
        return Button {
            repeatMode = mode
        } label: {
            Text(title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? VibePalette.amber : VibePalette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .machinedPlate(corner: 12, raised: !on)
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
                    .font(.body)
                    .foregroundStyle(VibePalette.ink)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VibePalette.amber)
                    .opacity(on ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
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

struct HolidayOptionSheet: View {
    @Binding var smart: Bool

    var body: some View {
        OptionSheetFrame(title: smart ? "Smart skip" : "Always ring") {
            VStack(spacing: 0) {
                option(true, "Smart skip", "Stays quiet on public holidays and leave days, and rings on makeup workdays.")
                Hairline(inset: 16)
                option(false, "Always ring", "Rings on every scheduled day, holidays included.")
            }
            .recessedWell(corner: 14)
        }
    }

    private func option(_ value: Bool, _ title: String, _ detail: String) -> some View {
        Button { smart = value } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VibePalette.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(VibePalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VibePalette.amber)
                    .opacity(smart == value ? 1 : 0)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(smart == value ? [.isSelected] : [])
    }
}

struct SnoozeOptionSheet: View {
    let minutes: Int
    let onChange: (Int) -> Void

    var body: some View {
        OptionSheetFrame(title: "\(minutes) min") {
            Text("Snooze length for the notification action and every alarm on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(VibePalette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(AlarmRule.snoozeIntervalOptions, id: \.self) { option in
                    let on = option == minutes
                    Button { onChange(option) } label: {
                        Text("\(option)")
                            .font(.body.weight(on ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(on ? VibePalette.amber : VibePalette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .machinedPlate(corner: 12, raised: !on)
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(on ? VibePalette.amber : Color.clear)
                                    .frame(width: 12, height: 3)
                                    .padding(.top, 8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option) minutes")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
    }
}
