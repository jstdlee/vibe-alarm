import SwiftUI
import VibeAlarmCore

/// The wake time editor for one alarm.
///
/// Hour and minute are edited with the system wheel. Repeat, the holiday rule, and snooze stay
/// available. Snooze is stored immediately, matching the previous editor. The other fields are
/// written when the person taps Save.
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

                    Picker("Holiday Rule", selection: $holidaySmart) {
                        Text("Smart skip").tag(true)
                        Text("Always ring").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Swipe up or down to change.")
                } footer: {
                    Text(holidaySmart
                         ? "Stays quiet on public holidays and leave days, and rings on makeup workdays."
                         : "Rings on every scheduled day, holidays included.")
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
                switch sheet {
                case .repeatDays:
                    RepeatOptionSheet(
                        repeatMode: $repeatMode,
                        customDays: $customDaysSelection,
                        onceDate: $onceDate
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            }
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
            rule.skipPublicHolidays = holidaySmart
        }
        dismiss()
    }
}
