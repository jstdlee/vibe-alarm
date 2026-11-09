import SwiftUI
import VibeAlarmCore

/// The wake time editor for one alarm.
///
/// The chosen time is the large reading at the top. Two drums set the hour and the minute.
/// Repeat, the holiday rule, and snooze are full-width rows. Snooze is stored immediately.
/// The other fields are written when the person taps Save.
public struct TimeEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private let alarmID: UUID

    @State private var hour: Int
    @State private var minute: Int
    @State private var repeatMode: AlarmRepeatMode
    @State private var holidaySmart: Bool
    @State private var customDaysSelection: Set<Weekday>
    @State private var onceDate: Date

    @State private var activeSheet: WakeOptionSheet?
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 72

    public init(viewModel: AppViewModel, alarmID: UUID) {
        self.init(viewModel: viewModel, alarmID: alarmID, initialSheet: nil)
    }

    init(viewModel: AppViewModel, alarmID: UUID, initialSheet: WakeOptionSheet?) {
        _activeSheet = State(initialValue: initialSheet)
        self.viewModel = viewModel
        self.alarmID = alarmID
        let rule = viewModel.snapshot.alarmRules.first(where: { $0.id == alarmID })
            ?? viewModel.snapshot.alarmRule
        _hour = State(initialValue: rule.hour)
        _minute = State(initialValue: rule.minute)
        _repeatMode = State(initialValue: rule.repeatMode)
        _holidaySmart = State(initialValue: rule.skipPublicHolidays)

        if case .customDays(let days) = rule.repeatMode, !days.isEmpty {
            _customDaysSelection = State(initialValue: days)
        } else {
            _customDaysSelection = State(initialValue: Weekday.standardWeekdays)
        }

        if case .specificDates(let dates) = rule.repeatMode,
           let first = dates.sorted().first,
           let parsed = AlarmScheduleEngine().date(from: first) {
            _onceDate = State(initialValue: parsed)
        } else {
            _onceDate = State(initialValue: Date())
        }
    }

    private var alarmLabel: String {
        viewModel.snapshot.alarmRules.first(where: { $0.id == alarmID })?.label ?? "Alarm"
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(alarmLabel)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(VibePalette.ink)
                        .lineLimit(2)
                        .padding(.top, 8)

                    Text(String(format: "%02d:%02d", hour, minute))
                        .font(.system(size: timeSize, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(VibePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityLabel("Wake time")
                        .accessibilityValue(String(format: "%02d:%02d", hour, minute))

                    HStack(alignment: .top, spacing: 12) {
                        BedsideDrum(title: "Hour", value: $hour, upperBound: 24)
                        BedsideDrum(title: "Minute", value: $minute, upperBound: 60)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 0) {
                        optionRow(
                            title: "Repeat",
                            value: AlarmFormatting.repeatTitle(repeatMode),
                            accessibilityValue: repeatAccessibilityValue,
                            hint: "Opens repeat options. Swipe up or down to change."
                        ) {
                            activeSheet = .repeatDays
                        }
                        .accessibilityAdjustableAction { direction in
                            selectRepeatIndex((repeatIndex + (direction == .increment ? 1 : -1) + 5) % 5)
                        }

                        Hairline()

                        optionRow(
                            title: "Holiday rule",
                            value: holidaySmart ? "Smart skip" : "Always ring",
                            accessibilityValue: holidaySmart ? "Smart skip on public holidays" : "Always ring",
                            hint: "Opens holiday options. Swipe up or down to change."
                        ) {
                            activeSheet = .holiday
                        }
                        .accessibilityAdjustableAction { _ in
                            holidaySmart.toggle()
                        }

                        Hairline()

                        optionRow(
                            title: "Snooze",
                            value: "\(viewModel.snoozeMinutes) min",
                            accessibilityValue: "\(viewModel.snoozeMinutes) minutes",
                            hint: "Opens snooze options. Swipe up or down to change."
                        ) {
                            activeSheet = .snooze
                        }
                        .accessibilityAdjustableAction { direction in
                            let options = AlarmRule.snoozeIntervalOptions
                            let index = options.firstIndex(of: viewModel.snoozeMinutes) ?? 0
                            let next = min(max(index + (direction == .increment ? 1 : -1), 0), options.count - 1)
                            viewModel.setSnoozeMinutes(options[next])
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .background(VibePalette.paper.ignoresSafeArea())
        .tint(VibePalette.amber)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .repeatDays:
                RepeatOptionSheet(repeatMode: $repeatMode, customDays: $customDaysSelection, onceDate: $onceDate)
            case .holiday:
                HolidayOptionSheet(smart: $holidaySmart)
            case .snooze:
                SnoozeOptionSheet(minutes: viewModel.snoozeMinutes) { viewModel.setSnoozeMinutes($0) }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.body)
                .foregroundStyle(VibePalette.inkSoft)
                .frame(minHeight: 44)
            Spacer()
            Button("Save") { save() }
                .font(.body.weight(.semibold))
                .foregroundStyle(VibePalette.amber)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
    }

    private func optionRow(
        title: String,
        value: String,
        accessibilityValue: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(VibePalette.ink)
                Spacer(minLength: 8)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VibePalette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VibePalette.inkFaint)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(hint)
    }

    private var repeatIndex: Int {
        switch repeatMode {
        case .weekdays: return 0
        case .everyday: return 1
        case .weekends: return 2
        case .customDays: return 3
        case .specificDates: return 4
        }
    }

    private var repeatAccessibilityValue: String {
        if case .specificDates = repeatMode {
            return "Once, \(onceDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if case .customDays(let days) = repeatMode {
            return days.sorted().map(\.shortWeekdayName).joined(separator: ", ")
        }
        return AlarmFormatting.repeatTitle(repeatMode)
    }

    private func selectRepeatIndex(_ idx: Int) {
        switch idx {
        case 0: repeatMode = .weekdays
        case 1: repeatMode = .everyday
        case 2: repeatMode = .weekends
        case 3: repeatMode = .customDays(customDaysSelection)
        case 4: repeatMode = .specificDates([AlarmScheduleEngine().dateString(from: onceDate)])
        default: break
        }
    }

    private func save() {
        viewModel.updateAlarm(id: alarmID) { rule in
            rule.hour = hour
            rule.minute = minute
            rule.repeatMode = repeatMode
            rule.skipPublicHolidays = holidaySmart
        }
        dismiss()
    }
}
