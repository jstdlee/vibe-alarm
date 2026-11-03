import SwiftUI
import VibeAlarmCore

/// The Alarm tab: Today and Tomorrow at a glance, one-tap overrides for tomorrow,
/// and quick access to the wake time editor and the bedtime reminder.
public struct TwoDayDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showTimeEditor = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    dayRow(viewModel.todayAlarm, label: "Today")
                    dayRow(viewModel.tomorrowAlarm, label: "Tomorrow")
                }

                Section {
                    tomorrowActionRow
                } footer: {
                    Text("Skip and delay apply to tomorrow only, and restore automatically the day after.")
                }

                Section {
                    Button {
                        showTimeEditor = true
                    } label: {
                        HStack {
                            Text("Wake time")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(viewModel.snapshot.alarmRule.formattedBaseTime)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: bedtimeEnabledBinding) {
                        Text("Bedtime reminder")
                    }
                    .tint(.vibeAccent)

                    if viewModel.snapshot.alarmRule.bedtimeReminderEnabled {
                        DatePicker(
                            "Reminder time",
                            selection: bedtimeDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Alarm")
            .sheet(isPresented: $showTimeEditor) {
                TimeEditorView(viewModel: viewModel)
            }
        }
        .tint(.vibeAccent)
    }

    // MARK: - Today / Tomorrow Row

    private func dayRow(_ day: ResolvedDayAlarm, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Text(dateCaption(day))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(timeOrStatusText(day))
                .font(.system(size: 48, weight: .light, design: .default))
                .monospacedDigit()
                .foregroundStyle(day.status.isRinging ? Color.primary : Color.secondary)

            if let reason = reasonLine(day) {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeOrStatusText(_ day: ResolvedDayAlarm) -> String {
        if day.status.isRinging {
            return day.effectiveTime ?? day.baseTime
        }
        if day.status == .skippedManually {
            return "Skipped"
        }
        return "Off"
    }

    private func reasonLine(_ day: ResolvedDayAlarm) -> String? {
        switch day.status {
        case .scheduled:
            if let makeup = day.matchedEntries.first(where: { $0.kind == .makeupWorkday }) {
                return makeup.title
            }
            return nil
        case .delayed(let minutes):
            return "Delayed \(minutes) min"
        case .skippedByHoliday(let reason):
            return reason
        case .skippedByPersonalLeave(let reason):
            return reason
        case .skippedManually:
            return "Manually skipped"
        case .noAlarm:
            return nil
        }
    }

    private func dateCaption(_ day: ResolvedDayAlarm) -> String {
        "\(day.weekdayText) \(Self.monthDayCaption(day.date))"
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func monthDayCaption(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month) else {
            return dateString
        }
        return "\(monthAbbreviations[month - 1]) \(day)"
    }

    // MARK: - Tomorrow Actions

    private var tomorrowActionRow: some View {
        HStack(spacing: 10) {
            Button("Skip") {
                viewModel.performTomorrowOverride(.skipTomorrow)
            }
            .buttonStyle(.bordered)
            .tint(isTomorrowSkipped ? Color.vibeAccent : Color.secondary)
            .frame(maxWidth: .infinity)

            Button("+30 min") {
                viewModel.incrementTomorrowDelay(by: 30)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button("Restore") {
                viewModel.performTomorrowOverride(.none)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.tomorrowAlarm.hasManualOverride)
        }
        .controlSize(.large)
        .tint(.vibeAccent)
        .listRowInsets(EdgeInsets())
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var isTomorrowSkipped: Bool {
        viewModel.tomorrowAlarm.status == .skippedManually
    }

    // MARK: - Bedtime Bindings

    private var bedtimeEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.snapshot.alarmRule.bedtimeReminderEnabled },
            set: { val in viewModel.updateAlarmRule { $0.bedtimeReminderEnabled = val } }
        )
    }

    private var bedtimeDateBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = viewModel.snapshot.alarmRule.preBedtimeReminderMinutes
                var comps = DateComponents()
                comps.hour = minutes / 60
                comps.minute = minutes % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let minutes = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                viewModel.updateAlarmRule { $0.preBedtimeReminderMinutes = minutes }
            }
        )
    }
}
