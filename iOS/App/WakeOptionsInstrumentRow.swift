import SwiftUI
import VibeAlarmCore

/// Which option sheet the wake time editor is showing.
enum WakeOptionSheet: String, Identifiable {
    case repeatDays, holiday, snooze
    var id: String { rawValue }
}

/// One recessed plate split into three cells by engraved grooves: Repeat, Holiday, Snooze.
///
/// Each cell reads like a small instrument: a caption, the current value, and a glyph that
/// shows the setting without words (seven day dots, a two-position notch, a quarter-arc gauge).
/// Tapping a cell opens its sheet. The snooze arc can also be dragged directly.
struct WakeOptionsInstrumentRow: View {
    let repeatMode: AlarmRepeatMode
    let onceDate: Date
    let holidaySmart: Bool
    let snoozeMinutes: Int
    let onOpen: (WakeOptionSheet) -> Void
    let onCycleRepeat: (Int) -> Void
    let onHolidayChange: (Bool) -> Void
    let onSnoozeChange: (Int) -> Void

    static let weekOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        HStack(spacing: 0) {
            repeatCell
            groove
            holidayCell
            groove
            snoozeCell
        }
        .frame(height: 64)
        .recessedWell(corner: 18)
    }

    private var groove: some View {
        HStack(spacing: 0) {
            Rectangle().fill(VibePalette.shadow.opacity(0.16)).frame(width: 0.6)
            Rectangle().fill(Color.white.opacity(0.7)).frame(width: 0.6)
        }
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }

    // MARK: Repeat

    private var activeDays: Set<Weekday> {
        switch repeatMode {
        case .weekdays: return Weekday.standardWeekdays
        case .everyday: return Set(Weekday.allCases)
        case .weekends: return [.saturday, .sunday]
        case .customDays(let days): return days
        case .specificDates: return []
        }
    }

    static func repeatTitle(_ mode: AlarmRepeatMode) -> String {
        switch mode {
        case .weekdays: return "Weekdays"
        case .everyday: return "Every Day"
        case .weekends: return "Weekends"
        case .customDays(let days):
            return days.isEmpty ? "Never" : "Custom"
        case .specificDates: return "Once"
        }
    }

    private var onceHint: String {
        onceDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var repeatCell: some View {
        cell(caption: "REPEAT", value: Self.repeatTitle(repeatMode)) {
            if case .specificDates = repeatMode {
                HStack(spacing: 5) {
                    Circle().fill(VibePalette.amber).frame(width: 5, height: 5)
                    Text(onceHint)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(VibePalette.inkSoft)
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(Self.weekOrder, id: \.self) { day in
                        Circle()
                            .fill(activeDays.contains(day) ? VibePalette.amber : VibePalette.well)
                            .overlay(Circle().strokeBorder(VibePalette.shadow.opacity(activeDays.contains(day) ? 0 : 0.12), lineWidth: 0.5))
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
        .accessibilityAdjustableAction { dir in onCycleRepeat(dir == .increment ? 1 : -1) }
    }

    private var repeatAccessibilityValue: String {
        if case .specificDates = repeatMode { return "Once, \(onceHint)" }
        if case .customDays(let days) = repeatMode {
            return days.sorted().map(\.shortWeekdayName).joined(separator: ", ")
        }
        return Self.repeatTitle(repeatMode)
    }

    // MARK: Holiday

    private var holidayCell: some View {
        cell(caption: "HOLIDAY", value: holidaySmart ? "Smart skip" : "Always ring") {
            HolidayNotch(smart: holidaySmart)
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

    // MARK: Snooze

    private var snoozeIndex: Int {
        AlarmRule.snoozeIntervalOptions.firstIndex(of: snoozeMinutes) ?? 0
    }

    private var snoozeCell: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SNOOZE").vibeCaption()
                Text("\(snoozeMinutes) min")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(VibePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            SnoozeArcGauge(index: snoozeIndex, count: AlarmRule.snoozeIntervalOptions.count) { idx in
                onSnoozeChange(AlarmRule.snoozeIntervalOptions[idx])
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
        .accessibilityAdjustableAction { dir in
            let opts = AlarmRule.snoozeIntervalOptions
            let next = min(max(snoozeIndex + (dir == .increment ? 1 : -1), 0), opts.count - 1)
            onSnoozeChange(opts[next])
        }
    }

    // MARK: Cell

    private func cell<G: View>(caption: String, value: String, @ViewBuilder glyph: () -> G) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).vibeCaption()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VibePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            glyph().frame(height: 8)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// An engraved two-position slot with a small matte stop seated at the active end.
struct HolidayNotch: View {
    let smart: Bool
    var width: CGFloat = 26
    var height: CGFloat = 8

    var body: some View {
        ZStack(alignment: smart ? .leading : .trailing) {
            Capsule()
                .fill(VibePalette.well.shadow(.inner(color: VibePalette.shadow.opacity(0.3), radius: 1.5, x: 0, y: 1)))
            Rectangle()
                .fill(VibePalette.shadow.opacity(0.18))
                .frame(width: 0.6, height: height * 0.6)
                .frame(maxWidth: .infinity)
            Capsule()
                .fill(smart ? VibePalette.amber : VibePalette.paperRaised)
                .shadow(color: VibePalette.shadow.opacity(0.25), radius: 1, x: 0, y: 1)
                .frame(width: width / 2 - 1, height: height - 2)
                .padding(.horizontal, 1)
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 0.18), value: smart)
    }
}

/// A 90-degree arc with one tick per snooze interval and an amber pointer.
/// The pivot sits in the lower-left corner; the arc sweeps from straight up to straight right.
struct SnoozeArcGauge: View {
    let index: Int
    let count: Int
    var lineScale: CGFloat = 1
    let onChange: (Int) -> Void

    private func angle(for i: Int) -> Angle {
        .degrees(-90 + Double(i) * 90 / Double(max(count - 1, 1)))
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let pivot = CGPoint(x: 2 * lineScale, y: size - 2 * lineScale)
            let r = size - 5 * lineScale
            ZStack {
                Path { p in
                    p.addArc(center: pivot, radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                }
                .stroke(VibePalette.hairline, lineWidth: 0.8 * lineScale)
                ForEach(0..<count, id: \.self) { i in
                    let a = angle(for: i).radians
                    Path { p in
                        p.move(to: CGPoint(x: pivot.x + cos(a) * (r - 4 * lineScale), y: pivot.y + sin(a) * (r - 4 * lineScale)))
                        p.addLine(to: CGPoint(x: pivot.x + cos(a) * (r + 2 * lineScale), y: pivot.y + sin(a) * (r + 2 * lineScale)))
                    }
                    .stroke(i == index ? VibePalette.amber : VibePalette.inkFaint, lineWidth: (i == index ? 1.6 : 0.9) * lineScale)
                }
                let a = angle(for: index).radians
                Path { p in
                    p.move(to: pivot)
                    p.addLine(to: CGPoint(x: pivot.x + cos(a) * (r - 6 * lineScale), y: pivot.y + sin(a) * (r - 6 * lineScale)))
                }
                .stroke(VibePalette.amber, style: StrokeStyle(lineWidth: 1.6 * lineScale, lineCap: .round))
                Circle().fill(VibePalette.ink).frame(width: 4 * lineScale, height: 4 * lineScale).position(pivot)
            }
            .animation(.easeOut(duration: 0.15), value: index)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        let dx = max(g.location.x - pivot.x, 0.001)
                        let dy = min(g.location.y - pivot.y, 0)
                        let deg = atan2(dy, dx) * 180 / .pi // -90 ... 0
                        let t = (deg + 90) / 90
                        let i = Int((t * Double(count - 1)).rounded())
                        let clamped = min(max(i, 0), count - 1)
                        if clamped != index { onChange(clamped) }
                    }
            )
        }
        .sensoryFeedback(.selection, trigger: index)
    }
}
