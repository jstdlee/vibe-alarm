import SwiftUI
import UIKit
import VibeAlarmCore

/// Repeat, holiday, and snooze on one plate above the bedside discs.
///
/// Tapping a cell opens its sheet. Swiping with VoiceOver changes the value
/// without opening the sheet. The snooze arc can also be dragged.
struct BedsideInstrumentRow: View {
    let repeatMode: AlarmRepeatMode
    let onceDate: Date
    let holidaySmart: Bool
    let snoozeMinutes: Int
    let accent: Color
    let onOpen: (WakeOptionSheet) -> Void
    let onCycleRepeat: (Int) -> Void
    let onHolidayChange: (Bool) -> Void
    let onSnoozeChange: (Int) -> Void

    @Environment(\.vibeTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var measuredHeight: CGFloat = 64

    private var rowHeight: CGFloat { min(max(measuredHeight, 64), 88) }

    var body: some View {
        HStack(spacing: 0) {
            repeatCell
            groove
            holidayCell
            groove
            snoozeCell
        }
        .frame(height: rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tokens.well.shadow(.inner(color: Color.black.opacity(0.16), radius: 4, y: 2)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(tokens.hairline, lineWidth: 0.6)
                )
        }
    }

    private var groove: some View {
        Rectangle()
            .fill(tokens.hairline)
            .frame(width: 0.6)
            .padding(.vertical, 12)
            .accessibilityHidden(true)
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

    private var onceHint: String {
        onceDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var repeatCell: some View {
        cell(caption: "REPEAT", value: AlarmFormatting.repeatTitle(repeatMode)) {
            if case .specificDates = repeatMode {
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 5, height: 5)
                    Text(onceHint)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(tokens.inkSoft)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(AlarmFormatting.weekOrder, id: \.self) { day in
                        Circle()
                            .fill(activeDays.contains(day) ? accent : tokens.paper)
                            .overlay(Circle().strokeBorder(tokens.hairline, lineWidth: 0.5))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .onTapGesture { onOpen(.repeatDays) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Repeat")
        .accessibilityValue(repeatAccessibilityValue)
        .accessibilityHint("Opens repeat options. Swipe up or down to change.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(.repeatDays) }
        .accessibilityAdjustableAction { direction in
            onCycleRepeat(direction == .increment ? 1 : -1)
        }
    }

    private var repeatAccessibilityValue: String {
        if case .specificDates = repeatMode { return "Once, \(onceHint)" }
        if case .customDays(let days) = repeatMode {
            return days.sorted().map(\.shortWeekdayName).joined(separator: ", ")
        }
        return AlarmFormatting.repeatTitle(repeatMode)
    }

    private var holidayCell: some View {
        cell(caption: "HOLIDAY", value: holidaySmart ? "Smart skip" : "Always ring") {
            BedsideHolidayNotch(smart: holidaySmart, accent: accent, reduceMotion: reduceMotion)
        }
        .onTapGesture { onOpen(.holiday) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Holiday rule")
        .accessibilityValue(holidaySmart ? "Smart skip on public holidays" : "Always ring")
        .accessibilityHint("Opens holiday options. Swipe up or down to change.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(.holiday) }
        .accessibilityAdjustableAction { _ in onHolidayChange(!holidaySmart) }
    }

    private var snoozeIndex: Int {
        AlarmRule.snoozeIntervalOptions.firstIndex(of: snoozeMinutes) ?? 0
    }

    private var snoozeCell: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SNOOZE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(tokens.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(snoozeMinutes) min")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(tokens.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            BedsideSnoozeGauge(
                index: snoozeIndex,
                count: AlarmRule.snoozeIntervalOptions.count,
                accent: accent,
                reduceMotion: reduceMotion
            ) { index in
                onSnoozeChange(AlarmRule.snoozeIntervalOptions[index])
            }
            .frame(width: 34, height: 34)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(.snooze) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snooze interval")
        .accessibilityValue("\(snoozeMinutes) minutes")
        .accessibilityHint("Opens snooze options. Swipe up or down to change.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(.snooze) }
        .accessibilityAdjustableAction { direction in
            let options = AlarmRule.snoozeIntervalOptions
            let next = min(max(snoozeIndex + (direction == .increment ? 1 : -1), 0), options.count - 1)
            onSnoozeChange(options[next])
        }
    }

    private func cell<G: View>(caption: String, value: String, @ViewBuilder glyph: () -> G) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(tokens.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            glyph().frame(height: 8)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct BedsideHolidayNotch: View {
    let smart: Bool
    let accent: Color
    let reduceMotion: Bool

    @Environment(\.vibeTokens) private var tokens

    var body: some View {
        ZStack(alignment: smart ? .leading : .trailing) {
            Capsule()
                .fill(tokens.paper.shadow(.inner(color: Color.black.opacity(0.22), radius: 1.2, y: 1)))
            Capsule()
                .fill(smart ? accent : tokens.raised)
                .frame(width: 12, height: 6)
                .padding(.horizontal, 1)
        }
        .frame(width: 26, height: 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: smart)
    }
}

private struct BedsideSnoozeGauge: View {
    let index: Int
    let count: Int
    let accent: Color
    let reduceMotion: Bool
    let onChange: (Int) -> Void

    @Environment(\.vibeTokens) private var tokens

    private func angle(for step: Int) -> Angle {
        .degrees(-90 + Double(step) * 90 / Double(max(count - 1, 1)))
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let pivot = CGPoint(x: 2, y: size - 2)
            let radius = size - 5
            ZStack {
                Path { path in
                    path.addArc(
                        center: pivot,
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(0),
                        clockwise: false
                    )
                }
                .stroke(tokens.hairline, lineWidth: 0.8)
                ForEach(0..<count, id: \.self) { step in
                    let radians = angle(for: step).radians
                    Path { path in
                        path.move(to: CGPoint(
                            x: pivot.x + cos(radians) * (radius - 4),
                            y: pivot.y + sin(radians) * (radius - 4)
                        ))
                        path.addLine(to: CGPoint(
                            x: pivot.x + cos(radians) * (radius + 2),
                            y: pivot.y + sin(radians) * (radius + 2)
                        ))
                    }
                    .stroke(step == index ? accent : tokens.inkFaint, lineWidth: step == index ? 1.6 : 0.9)
                }
                let radians = angle(for: index).radians
                Path { path in
                    path.move(to: pivot)
                    path.addLine(to: CGPoint(
                        x: pivot.x + cos(radians) * (radius - 6),
                        y: pivot.y + sin(radians) * (radius - 6)
                    ))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                Circle()
                    .fill(tokens.ink)
                    .frame(width: 4, height: 4)
                    .position(pivot)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: index)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        let dx = max(gesture.location.x - pivot.x, 0.001)
                        let dy = min(gesture.location.y - pivot.y, 0)
                        let degrees = atan2(dy, dx) * 180 / .pi
                        let unit = (degrees + 90) / 90
                        let next = min(max(Int((unit * Double(count - 1)).rounded()), 0), count - 1)
                        if next != index {
                            UISelectionFeedbackGenerator().selectionChanged()
                            onChange(next)
                        }
                    }
            )
        }
    }
}
