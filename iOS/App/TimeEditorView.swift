import SwiftUI
import VibeAlarmCore

/// The wake time editor: a large centered time readout, the two semicircular rotary
/// dials in the thumb zone, and the horizontal thumbwheel rollers for repeat and
/// holiday rule. Edits are local until "Save" is tapped; "Cancel" discards them.
public struct TimeEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var hour: Int
    @State private var minute: Int
    @State private var repeatMode: AlarmRepeatMode
    @State private var holidaySmart: Bool
    @State private var customDaysSelection: Set<Weekday>
    @State private var onceDate: Date

    private let repeatOptions = ["Workdays", "Every Day", "Weekends", "Custom", "Once"]
    private let holidayOptions = ["Smart", "Always Ring"]
    private let weekOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let rule = viewModel.snapshot.alarmRule
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

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Wake Time")
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
        }
        .tint(.vibeAccent)
    }

    private var content: some View {
        VStack(spacing: 0) {
            timeReadoutHeader
                .padding(.top, 8)
                .padding(.bottom, 4)

            dialsZone
                .frame(height: 300)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    rollersSection

                    if case .customDays = repeatMode {
                        customWeekdaysRow
                    }
                    if case .specificDates = repeatMode {
                        oncePickerRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Top Readout

    private var timeReadoutHeader: some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d:%02d", hour, minute))
                .font(.system(size: 60, weight: .light, design: .default))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(repeatSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var repeatSummaryText: String {
        "\(repeatOptions[repeatIndex]) · \(holidaySmart ? "Smart" : "Always Ring")"
    }

    // MARK: - Dials

    private var dialsZone: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SemicircleDial(
                    edge: .left,
                    value: hour,
                    valueCount: 24,
                    majorStep: 1,
                    unitLabel: "HOUR"
                ) { newHour in
                    hour = newHour
                }
                .frame(width: geo.size.width / 2)

                SemicircleDial(
                    edge: .right,
                    value: minute,
                    valueCount: 60,
                    majorStep: 5,
                    unitLabel: "MIN"
                ) { newMinute in
                    minute = newMinute
                }
                .frame(width: geo.size.width / 2)
            }
        }
    }

    // MARK: - Rollers

    private var rollersSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("REPEAT")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ThumbwheelRoller(
                    options: repeatOptions,
                    selectedIndex: repeatIndex,
                    accessibilityLabelText: "Repeat"
                ) { idx in
                    selectRepeatIndex(idx)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("HOLIDAY RULE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ThumbwheelRoller(
                    options: holidayOptions,
                    selectedIndex: holidaySmart ? 0 : 1,
                    accessibilityLabelText: "Holiday Rule"
                ) { idx in
                    holidaySmart = (idx == 0)
                }
            }
        }
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

    // MARK: - Custom Weekdays Row

    private var customWeekdaysRow: some View {
        HStack(spacing: 10) {
            ForEach(weekOrder, id: \.self) { day in
                weekdayToggle(day)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func weekdayToggle(_ day: Weekday) -> some View {
        let isOn = customDaysSelection.contains(day)
        return Button {
            toggleCustomDay(day)
        } label: {
            Text(String(day.shortWeekdayName.prefix(1)))
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(isOn ? Color.vibeAccent : Color(.tertiarySystemFill)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.shortWeekdayName)
    }

    private func toggleCustomDay(_ day: Weekday) {
        var next = customDaysSelection
        if next.contains(day) {
            next.remove(day)
        } else {
            next.insert(day)
        }
        customDaysSelection = next
        repeatMode = .customDays(next)
    }

    // MARK: - Once Date Picker

    private var oncePickerRow: some View {
        DatePicker(
            "Date",
            selection: Binding(
                get: { onceDate },
                set: { newDate in
                    onceDate = newDate
                    repeatMode = .specificDates([AlarmScheduleEngine().dateString(from: newDate)])
                }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Save

    private func save() {
        viewModel.updateAlarmRule { rule in
            rule.hour = hour
            rule.minute = minute
            rule.repeatMode = repeatMode
            rule.skipPublicHolidays = holidaySmart
        }
        dismiss()
    }
}
