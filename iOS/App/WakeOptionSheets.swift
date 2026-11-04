import SwiftUI
import VibeAlarmCore

/// Shared chrome for the three option sheets: a caption, a title and paper background.
private struct OptionSheetFrame<Content: View>: View {
    let caption: String
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(caption).vibeCaption()
                    Text(title)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(VibePalette.ink)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VibePalette.amber)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VibePalette.paper.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(VibePalette.paper)
    }
}

/// Repeat: four shortcut keys on top, then the seven days as a checkmark list.
struct RepeatOptionSheet: View {
    @Binding var repeatMode: AlarmRepeatMode
    @Binding var customDays: Set<Weekday>
    @Binding var onceDate: Date

    private var isOnce: Bool {
        if case .specificDates = repeatMode { return true }
        return false
    }

    private var activeDays: Set<Weekday> {
        switch repeatMode {
        case .weekdays: return Weekday.standardWeekdays
        case .everyday: return Set(Weekday.allCases)
        case .weekends: return [.saturday, .sunday]
        case .customDays(let d): return d
        case .specificDates: return []
        }
    }

    var body: some View {
        OptionSheetFrame(caption: "REPEAT", title: WakeOptionsInstrumentRow.repeatTitle(repeatMode)) {
            HStack(spacing: 8) {
                shortcut("Weekdays", mode: .weekdays)
                shortcut("Every Day", mode: .everyday)
                shortcut("Weekends", mode: .weekends)
                shortcut("Once", mode: .specificDates([AlarmScheduleEngine().dateString(from: onceDate)]))
            }

            if isOnce {
                HStack {
                    Text("Ring once on")
                        .font(.system(size: 15))
                        .foregroundStyle(VibePalette.inkSoft)
                    Spacer()
                    DatePicker("Date", selection: Binding(
                        get: { onceDate },
                        set: { d in
                            onceDate = d
                            repeatMode = .specificDates([AlarmScheduleEngine().dateString(from: d)])
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .tint(VibePalette.amber)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .recessedWell(corner: 16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(WakeOptionsInstrumentRow.weekOrder.enumerated()), id: \.element) { idx, day in
                            dayRow(day)
                            if idx < 6 { Hairline(inset: 16) }
                        }
                    }
                    .recessedWell(corner: 16)
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
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? VibePalette.amber : VibePalette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .machinedPlate(corner: 12, raised: !on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func dayRow(_ day: Weekday) -> some View {
        let on = activeDays.contains(day)
        return Button {
            var next = activeDays
            if on { next.remove(day) } else { next.insert(day) }
            customDays = next
            if next == Weekday.standardWeekdays { repeatMode = .weekdays }
            else if next == Set(Weekday.allCases) { repeatMode = .everyday }
            else if next == [.saturday, .sunday] { repeatMode = .weekends }
            else { repeatMode = .customDays(next) }
        } label: {
            HStack {
                Text(day.longName)
                    .font(.system(size: 15))
                    .foregroundStyle(VibePalette.ink)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VibePalette.amber)
                    .opacity(on ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longName)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

private extension Weekday {
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

/// Holiday: two engraved positions on one plate, each with a line on what it does.
struct HolidayOptionSheet: View {
    @Binding var smart: Bool

    var body: some View {
        OptionSheetFrame(caption: "HOLIDAY", title: smart ? "Smart skip" : "Always ring") {
            VStack(spacing: 0) {
                option(true, "Smart skip", "Stays quiet on public holidays and leave days, rings on makeup workdays.")
                Hairline(inset: 16)
                option(false, "Always ring", "Rings on every scheduled day, holidays included.")
            }
            .recessedWell(corner: 16)
        }
    }

    private func option(_ value: Bool, _ title: String, _ detail: String) -> some View {
        Button { smart = value } label: {
            HStack(alignment: .center, spacing: 14) {
                HolidayNotch(smart: value, width: 30, height: 10).opacity(smart == value ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(VibePalette.ink)
                    Text(detail).font(.system(size: 13)).foregroundStyle(VibePalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
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

/// Snooze: a large arc you can drag, and five ticks you can tap.
struct SnoozeOptionSheet: View {
    let minutes: Int
    let onChange: (Int) -> Void

    private var index: Int { AlarmRule.snoozeIntervalOptions.firstIndex(of: minutes) ?? 0 }

    var body: some View {
        OptionSheetFrame(caption: "SNOOZE", title: "\(minutes) min") {
            HStack(alignment: .bottom, spacing: 20) {
                SnoozeArcGauge(index: index, count: AlarmRule.snoozeIntervalOptions.count, lineScale: 2.2) { i in
                    onChange(AlarmRule.snoozeIntervalOptions[i])
                }
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .recessedWell(corner: 16)

            HStack(spacing: 8) {
                ForEach(AlarmRule.snoozeIntervalOptions, id: \.self) { m in
                    let on = m == minutes
                    Button { onChange(m) } label: {
                        Text("\(m)")
                            .font(.system(size: 15, weight: on ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(on ? VibePalette.amber : VibePalette.inkSoft)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .machinedPlate(corner: 12, raised: !on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(m) minutes")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
    }
}
