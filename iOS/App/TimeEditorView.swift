import SwiftUI
import VibeAlarmCore

/// The wake time editor: a large centered time readout over a calm, full-bleed background,
/// a stack of compact rotary option dials, and the two semicircular hour/minute dials
/// pinned in the lower thumb zone. The option dials cover Repeat, Holiday Rule and Snooze. Edits to the alarm rule are local until "Save"
/// is tapped; "Cancel" discards them. Snooze is a standalone preference and applies immediately.
public struct TimeEditorView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var hour: Int
    @State private var minute: Int
    @State private var repeatMode: AlarmRepeatMode
    @State private var holidaySmart: Bool
    @State private var customDaysSelection: Set<Weekday>
    @State private var onceDate: Date

    private let repeatOptions = ["Weekdays", "Every Day", "Weekends", "Custom", "Once"]
    private let holidayOptions = ["Smart", "Always Ring"]
    private let snoozeOptions: [String] = AlarmRule.snoozeIntervalOptions.map { "\($0) min" }
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

    /// Layout, top to bottom: time readout, the option-dial stack (the only part that may
    /// scroll, on short screens), and the hour/minute dials pinned in the lower thumb zone.
    /// Budget on 393 x 852 pt: ~715 pt usable; readout ~100 + options ~320 + dials 240 = ~660,
    /// so nothing scrolls. On 375 x 667 pt only the option stack scrolls.
    private var content: some View {
        VStack(spacing: 0) {
            timeReadoutHeader
                .padding(.top, 6)
                .padding(.bottom, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    optionDialsSection

                    if case .customDays = repeatMode {
                        customWeekdaysRow
                    }
                    if case .specificDates = repeatMode {
                        oncePickerRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            dialsZone
                .frame(height: 240)
                .padding(.bottom, 8)
        }
        .background(calmBackground)
    }

    // MARK: - Calm Background

    /// A soft, full-bleed light background with a very subtle accent wash, in the spirit of
    /// the native Clock and Weather apps. No images, no heavy gradients.
    private var calmBackground: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.vibeAccent.opacity(0.05),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Readout

    private var timeReadoutHeader: some View {
        VStack(spacing: 6) {
            Text(String(format: "%02d:%02d", hour, minute))
                .font(.system(size: 56, weight: .light, design: .rounded))
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

    // MARK: - Option Dials

    private var optionDialsSection: some View {
        VStack(spacing: 12) {
            dialBlock(title: "REPEAT") {
                RotaryOptionDial(
                    options: repeatOptions,
                    selectedIndex: repeatIndex,
                    accessibilityLabelText: "Repeat"
                ) { idx in
                    selectRepeatIndex(idx)
                }
            }

            dialBlock(title: "HOLIDAY RULE") {
                RotaryOptionDial(
                    options: holidayOptions,
                    selectedIndex: holidaySmart ? 0 : 1,
                    accessibilityLabelText: "Holiday Rule"
                ) { idx in
                    holidaySmart = (idx == 0)
                }
            }

            dialBlock(title: "SNOOZE") {
                RotaryOptionDial(
                    options: snoozeOptions,
                    selectedIndex: snoozeIndex,
                    accessibilityLabelText: "Snooze"
                ) { idx in
                    selectSnoozeIndex(idx)
                }
            }
        }
    }

    private func dialBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var snoozeIndex: Int {
        let current = viewModel.snoozeMinutes
        if let idx = AlarmRule.snoozeIntervalOptions.firstIndex(of: current) {
            return idx
        }
        return 0
    }

    private func selectSnoozeIndex(_ idx: Int) {
        guard AlarmRule.snoozeIntervalOptions.indices.contains(idx) else { return }
        viewModel.setSnoozeMinutes(AlarmRule.snoozeIntervalOptions[idx])
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
