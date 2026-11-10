import SwiftUI
import UIKit
import VibeAlarmCore

/// Repeat, holiday, and snooze for the bedside wake editor.
///
/// Each control is a full-width plate. Repeat opens the repeat sheet. Holiday
/// is a switch. Snooze is a row of minute choices. Nothing is squeezed into
/// a shared three-cell strip.
struct BedsideWakeOptions: View {
    let repeatMode: AlarmRepeatMode
    let onceDate: Date
    let holidaySmart: Bool
    let snoozeMinutes: Int
    let accent: Color
    let onOpenRepeat: () -> Void
    let onCycleRepeat: (Int) -> Void
    let onHolidayChange: (Bool) -> Void
    let onSnoozeChange: (Int) -> Void

    @Environment(\.vibeTokens) private var tokens
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            repeatRow
            holidayRow
            snoozeRow
        }
    }

    private var activeDays: Set<Weekday> {
        switch repeatMode {
        case .weekdays: return Weekday.standardWeekdays
        case .everyday: return Set(Weekday.allCases)
        case .weekends: return [.saturday, .sunday]
        case .customDays(let days): return days
        case .specificDates: return []
        }
    }

    private var repeatValue: String {
        if case .specificDates = repeatMode {
            let day = onceDate.formatted(.dateTime.month(.abbreviated).day())
            return "Once, \(day)"
        }
        return AlarmFormatting.repeatTitle(repeatMode)
    }

    private var repeatRow: some View {
        Button(action: onOpenRepeat) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    caption("REPEAT")
                    Text(repeatValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tokens.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if case .specificDates = repeatMode {
                        EmptyView()
                    } else {
                        HStack(spacing: 5) {
                            ForEach(AlarmFormatting.weekOrder, id: \.self) { day in
                                Circle()
                                    .fill(activeDays.contains(day) ? accent : tokens.paper)
                                    .overlay(Circle().strokeBorder(tokens.hairline, lineWidth: 0.6))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tokens.inkFaint)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { plate }
        .accessibilityLabel("Repeat")
        .accessibilityValue(repeatAccessibilityValue)
        .accessibilityHint("Opens repeat options. Swipe up or down to change.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            onCycleRepeat(direction == .increment ? 1 : -1)
        }
    }

    private var repeatAccessibilityValue: String {
        if case .specificDates = repeatMode {
            return "Once, \(onceDate.formatted(.dateTime.month(.wide).day()))"
        }
        if case .customDays(let days) = repeatMode {
            let names = days.sorted().map(\.shortWeekdayName).joined(separator: ", ")
            return names.isEmpty ? "No days" : names
        }
        return AlarmFormatting.repeatTitle(repeatMode)
    }

    private var holidayRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                caption("HOLIDAY")
                Text(holidaySmart ? "Smart skip" : "Always ring")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tokens.ink)
                    .lineLimit(1)
                Text(holidaySmart
                     ? "Quiet on holidays and leave days. Rings on makeup workdays."
                     : "Rings on every scheduled day, holidays included.")
                    .font(.subheadline)
                    .foregroundStyle(tokens.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { holidaySmart },
                set: { newValue in
                    UISelectionFeedbackGenerator().selectionChanged()
                    onHolidayChange(newValue)
                }
            )) {
                Text("Smart skip")
            }
            .labelsHidden()
            .tint(accent)
            .accessibilityLabel("Smart skip")
            .accessibilityValue(holidaySmart ? "On" : "Off")
            .accessibilityHint(holidaySmart
                               ? "Quiet on holidays and leave days. Rings on makeup workdays."
                               : "Rings on every scheduled day, holidays included.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background { plate }
        .accessibilityElement(children: .contain)
    }

    private var snoozeChoices: [Int] {
        var options = AlarmRule.snoozeIntervalOptions
        if !options.contains(snoozeMinutes) {
            options.append(snoozeMinutes)
            options.sort()
        }
        return options
    }

    private var snoozeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                caption("SNOOZE")
                Spacer(minLength: 8)
                Text("\(snoozeMinutes) min")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tokens.ink)
            }
            HStack(spacing: 6) {
                ForEach(snoozeChoices, id: \.self) { minutes in
                    snoozeKey(minutes)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { plate }
        .accessibilityElement(children: .contain)
    }

    private func snoozeKey(_ minutes: Int) -> some View {
        let selected = minutes == snoozeMinutes
        return Button {
            guard minutes != snoozeMinutes else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onSnoozeChange(minutes)
        } label: {
            Text("\(minutes)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(selected ? selectedInk : tokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? accent : tokens.paper)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }

    private var selectedInk: Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.12, blue: 0.07)
            : Color.white
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(tokens.inkFaint)
            .lineLimit(1)
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tokens.raised)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tokens.hairline, lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.28 : 0.05), radius: 8, y: 3)
    }
}
