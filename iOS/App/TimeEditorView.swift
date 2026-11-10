import SwiftUI
import VibeAlarmCore

/// The wake time editor for one alarm.
///
/// Standard edits the hour and minute with the system wheel. Bedside Clock uses two rotary
/// discs along the bottom edge: hour on the left, minute on the right. Repeat, the holiday
/// rule, and snooze stay available. Snooze is stored immediately. The other fields are
/// written when the person taps Save.
public struct TimeEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private let alarmID: UUID

    @State private var hour: Int
    @State private var minute: Int
    @State private var repeatMode: AlarmRepeatMode
    @State private var skipPublicHolidays: Bool
    @State private var skipPersonalLeave: Bool
    @State private var customDaysSelection: Set<Weekday>
    @State private var onceDate: Date

    @Environment(\.appearanceStyle) private var appearanceStyle
    @Environment(\.vibeTokens) private var tokens
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var activeSheet: WakeOptionSheet?
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 56

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
        _skipPublicHolidays = State(initialValue: rule.skipPublicHolidays)
        _skipPersonalLeave = State(initialValue: rule.skipPersonalLeave)

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
        if appearanceStyle == .bedside {
            bedsideBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        // The tall simulator proposes a zero window on the first pass. A geometry
        // reader subscribes to the real size so the editor replaces the launch screen.
        GeometryReader { proxy in
            NavigationStack {
                Form {
                Section {
                    Text(String(format: "%02d:%02d", hour, minute))
                        .font(.system(size: timeSize, weight: .regular))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityHidden(true)

                    DatePicker(
                        "Wake time",
                        selection: wakeDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 216)
                    .clipped()
                }

                Section {
                    Button {
                        activeSheet = .repeatDays
                    } label: {
                        HStack {
                            Text("Repeat")
                            Spacer()
                            Text(AlarmFormatting.repeatTitle(repeatMode))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat")
                    .accessibilityValue(repeatAccessibilityValue)
                    .accessibilityHint("Opens repeat options. Swipe up or down to change.")
                    .accessibilityAdjustableAction { direction in
                        selectRepeatIndex((repeatIndex + (direction == .increment ? 1 : -1) + 5) % 5)
                    }
                }

                Section {
                    Toggle("Public holidays", isOn: $skipPublicHolidays)
                    Toggle("Personal leave", isOn: $skipPersonalLeave)
                } footer: {
                    Text(standardSkipFooter)
                }

                Section {
                    Picker("Snooze", selection: snoozeSelection) {
                        ForEach(snoozeChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Used by the notification snooze action and every alarm on this iPhone.")
                }
            }
            .navigationTitle(alarmLabel)
            .vibeChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                optionSheet(sheet)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    /// Cancel and Save sit on the paper. The name and the wake options stay
    /// with them. The hour and minute discs fill whatever height is left, with
    /// their lower halves off the bottom edge.
    private var bedsideBody: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 720
            VStack(spacing: 0) {
                bedsideTitle(isCompact: isCompact)

                BedsideWakeOptions(
                    weekdays: repeatMode.weekdays,
                    skipPublicHolidays: skipPublicHolidays,
                    skipPersonalLeave: skipPersonalLeave,
                    snoozeMinutes: viewModel.snoozeMinutes,
                    accent: BedsideDialColor.accent(scheme: colorScheme, contrast: contrast),
                    onWeekdaysChange: { repeatMode = AlarmRepeatMode.matching(weekdays: $0) },
                    onSkipPublicHolidays: { skipPublicHolidays = $0 },
                    onSkipPersonalLeave: { skipPersonalLeave = $0 },
                    onSnoozeChange: { viewModel.setSnoozeMinutes($0) }
                )
                .padding(.horizontal, 16)
                .padding(.top, isCompact ? 4 : 8)

                GeometryReader { discSpace in
                    // Keep the lower portion off the bottom edge and use the
                    // rest of the height for the upper arc, so the rims sit
                    // just under the options.
                    let clip: CGFloat = 0.32
                    let diameter = discSpace.size.height / (1 - clip)
                    BedsideDiscPair(
                        diameter: diameter,
                        hour: hour,
                        minute: minute,
                        onHourChange: { hour = $0 },
                        onMinuteChange: { minute = $0 }
                    )
                    .padding(.bottom, -(diameter * clip))
                    .frame(width: discSpace.size.width, height: discSpace.size.height, alignment: .top)
                }
                .padding(.top, isCompact ? 8 : 12)
                .frame(minHeight: isCompact ? 220 : 300)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(tokens.paper.ignoresSafeArea())
        .overlay(alignment: .top) { bedsideTopBar }
        .sheet(item: $activeSheet) { sheet in
            optionSheet(sheet)
        }
    }

    private var bedsideTopBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(tokens.inkSoft)
                .frame(minHeight: 44)
            Spacer()
            Button("Save") { save() }
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .foregroundStyle(BedsideDialColor.accent(scheme: colorScheme, contrast: contrast))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    private func bedsideTitle(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WAKE TIME")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(tokens.inkFaint)
            Text(alarmLabel)
                .font(.system(size: isCompact ? 26 : 30, weight: .regular))
                .foregroundStyle(tokens.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, isCompact ? 48 : 52)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func optionSheet(_ sheet: WakeOptionSheet) -> some View {
        switch sheet {
        case .repeatDays:
            RepeatOptionSheet(repeatMode: $repeatMode, customDays: $customDaysSelection, onceDate: $onceDate)
        case .holiday:
            HolidayOptionSheet(smart: $skipPublicHolidays)
        case .snooze:
            SnoozeOptionSheet(minutes: viewModel.snoozeMinutes) { viewModel.setSnoozeMinutes($0) }
        }
    }

    private var wakeDate: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                if let newHour = components.hour { hour = newHour }
                if let newMinute = components.minute { minute = newMinute }
            }
        )
    }

    private var snoozeChoices: [Int] {
        var options = AlarmRule.snoozeIntervalOptions
        if !options.contains(viewModel.snoozeMinutes) {
            options.append(viewModel.snoozeMinutes)
            options.sort()
        }
        return options
    }

    private var standardSkipFooter: String {
        switch (skipPublicHolidays, skipPersonalLeave) {
        case (false, false):
            return "Rings on every scheduled day."
        case (true, false):
            return "Stays quiet on public holidays and rings on makeup workdays."
        case (false, true):
            return "Stays quiet on personal leave."
        case (true, true):
            return "Stays quiet on public holidays and personal leave, and rings on makeup workdays."
        }
    }

    private var snoozeSelection: Binding<Int> {
        Binding(
            get: { viewModel.snoozeMinutes },
            set: { viewModel.setSnoozeMinutes($0) }
        )
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
            rule.skipPublicHolidays = skipPublicHolidays
            rule.skipPersonalLeave = skipPersonalLeave
        }
        dismiss()
    }
}
