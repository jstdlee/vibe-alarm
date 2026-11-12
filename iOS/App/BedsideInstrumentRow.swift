import SwiftUI
import UIKit
import VibeAlarmCore

/// Repeat, skip, and snooze for the bedside wake editor.
///
/// Repeat is seven day keys. A tap toggles one day. A drag paints days on or
/// off: the first key touched chooses the direction, and every key the finger
/// crosses takes that state. Skip is two independent keys. Snooze is the
/// minute choices. There are no helper sentences.
struct BedsideWakeOptions: View {
    let weekdays: Set<Weekday>
    let skipPublicHolidays: Bool
    let skipPersonalLeave: Bool
    let snoozeMinutes: Int
    let accent: Color
    let onWeekdaysChange: (Set<Weekday>) -> Void
    let onSkipPublicHolidays: (Bool) -> Void
    let onSkipPersonalLeave: (Bool) -> Void
    let onSnoozeChange: (Int) -> Void

    @Environment(\.vibeTokens) private var tokens
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var paintTurningOn: Bool?
    @State private var lastPaintIndex: Int?

    private let daySpacing: CGFloat = 3

    var body: some View {
        VStack(spacing: 10) {
            repeatRow
            skipRow
            snoozeRow
            Text(skipRule)
                .font(.system(size: 12))
                .foregroundStyle(tokens.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Repeat

    private var repeatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Repeat")
            GeometryReader { geo in
                HStack(spacing: daySpacing) {
                    ForEach(AlarmFormatting.weekOrder, id: \.self) { day in
                        dayKey(day)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dayPaint(width: geo.size.width))
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { plate }
    }

    private func dayKey(_ day: Weekday) -> some View {
        let on = weekdays.contains(day)
        return Text(day.shortWeekdayName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(on ? selectedInk : tokens.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? accent : tokens.well)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: on)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day.shortWeekdayName)
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityAddTraits(on ? [.isToggle, .isSelected] : .isToggle)
            .accessibilityAction { toggle(day) }
    }

    private func dayPaint(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let index = dayIndex(at: value.location.x, width: width)
                paint(through: index)
            }
            .onEnded { _ in
                paintTurningOn = nil
                lastPaintIndex = nil
            }
    }

    private func dayIndex(at x: CGFloat, width: CGFloat) -> Int {
        let count = AlarmFormatting.weekOrder.count
        let slot = (width + daySpacing) / CGFloat(count)
        guard slot > 0 else { return 0 }
        return min(count - 1, max(0, Int(x / slot)))
    }

    private func paint(through index: Int) {
        let order = AlarmFormatting.weekOrder
        if paintTurningOn == nil {
            paintTurningOn = !weekdays.contains(order[index])
        }
        guard let turningOn = paintTurningOn else { return }
        let start = lastPaintIndex ?? index
        var days = weekdays
        var changed = false
        for cursor in min(start, index)...max(start, index) {
            let day = order[cursor]
            if turningOn, !days.contains(day) {
                days.insert(day)
                changed = true
            } else if !turningOn, days.contains(day) {
                days.remove(day)
                changed = true
            }
        }
        lastPaintIndex = index
        guard changed else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onWeekdaysChange(days)
    }

    private func toggle(_ day: Weekday) {
        var days = weekdays
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        onWeekdaysChange(days)
    }

    // MARK: - Skip

    private var skipRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Skip")
            HStack(spacing: 8) {
                skipKey("Public holidays", on: skipPublicHolidays) { next in
                    onSkipPublicHolidays(next)
                }
                skipKey("Personal leave", on: skipPersonalLeave) { next in
                    onSkipPersonalLeave(next)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { plate }
    }

    private func skipKey(_ title: String, on: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            set(!on)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? selectedInk : tokens.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(on ? accent : tokens.well)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(on ? [.isToggle, .isSelected] : .isToggle)
    }

    // MARK: - Snooze

    private var snoozeChoices: [Int] {
        var options = AlarmRule.snoozeIntervalOptions
        if !options.contains(snoozeMinutes) {
            options.append(snoozeMinutes)
            options.sort()
        }
        return options
    }

    private var snoozeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                label("Snooze")
                Spacer(minLength: 8)
                Text("\(snoozeMinutes) min")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                ForEach(snoozeChoices, id: \.self) { minutes in
                    snoozeKey(minutes)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { plate }
        .accessibilityElement(children: .contain)
    }

    private var skipRule: String {
        switch (skipPublicHolidays, skipPersonalLeave) {
        case (true, true):
            return "Stays quiet on public holidays and personal leave, and rings on makeup workdays."
        case (true, false):
            return "Stays quiet on public holidays, and rings on makeup workdays."
        case (false, true):
            return "Stays quiet on personal leave."
        case (false, false):
            return "Rings on every selected day."
        }
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
                        .fill(selected ? accent : tokens.well)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minutes")
        .accessibilityAddTraits(selected ? [.isToggle, .isSelected] : .isToggle)
    }

    private var selectedInk: Color {
        scheme == .dark
            ? Color(red: 0.102, green: 0.078, blue: 0.047)
            : Color(red: 1.0, green: 0.973, blue: 0.933)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tokens.ink)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
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
