import SwiftUI
import UIKit
import VibeAlarmCore

/// The home screen: tomorrow's override keys at the top, then every alarm as a row.
///
/// The screen is one column of matte paper with two engraved hairlines. The only volumes are
/// the three machined keys and the toggles; everything else is ink on paper, which is what
/// keeps it calm even though it carries six pieces of information per alarm.
public struct AlarmListView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var editing: EditingTarget?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    quickActionsBlock
                        .padding(.top, 26)
                    alarmRows
                        .padding(.top, 30)
                    footer
                        .padding(.top, 28)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { target in
                TimeEditorView(viewModel: viewModel, alarmID: target.id)
                    .presentationDragIndicator(.visible)
            }
        }
        .tint(VibePalette.amber)
    }

    // MARK: - Title

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("VIBE ALARM")
                    .vibeCaption()
                Text("Alarms")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(VibePalette.ink)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.addAlarm()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(VibePalette.inkSoft)
                    .frame(width: 42, height: 42)
                    .machinedPlate(corner: 21)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Alarm")
        }
        .padding(.top, 14)
    }

    // MARK: - Tomorrow's Keys

    private var quickActionsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TOMORROW")
                    .vibeCaption(VibePalette.inkSoft)
                Text(tomorrowDateCaption)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(0.6)
                    .foregroundStyle(VibePalette.inkFaint)
                Spacer()
                Text(tomorrowStateSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(tomorrowWillRing ? VibePalette.amber : VibePalette.inkFaint)
                    .lineLimit(1)
            }

            HStack(spacing: 9) {
                quickKey(
                    title: "Skip",
                    enabled: tomorrowWillRing,
                    action: { viewModel.performTomorrowOverride(.skipTomorrow) }
                )
                quickKey(
                    title: "+10 min",
                    enabled: tomorrowWillRing,
                    action: { viewModel.incrementTomorrowDelay(by: 10) }
                )
                quickKey(
                    title: "Restore",
                    enabled: hasOverride,
                    action: { viewModel.performTomorrowOverride(.none) }
                )
            }
        }
    }

    private func quickKey(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(enabled ? VibePalette.ink : VibePalette.inkFaint.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .machinedPlate(corner: 16, raised: enabled)
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.18), value: enabled)
    }

    // MARK: - Rows

    private var alarmRows: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(viewModel.alarmRows) { row in
                alarmRow(row)
                Hairline()
            }
        }
    }

    private func alarmRow(_ row: AlarmRow) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                editing = EditingTarget(id: row.id)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.rule.formattedBaseTime)
                        .font(.system(size: 44, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(row.rule.isEnabled ? VibePalette.ink : VibePalette.inkFaint.opacity(0.65))

                    Text(row.rule.label.uppercased())
                        .vibeCaption(row.rule.isEnabled ? VibePalette.inkSoft : VibePalette.inkFaint)

                    Text(repeatSummary(row.rule))
                        .font(.system(size: 12))
                        .foregroundStyle(VibePalette.inkFaint)
                        .lineLimit(1)

                    stateReadout(row)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { row.rule.isEnabled },
                set: { isOn in
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.setAlarmEnabled(id: row.id, isEnabled: isOn)
                }
            ))
            .labelsHidden()
            .tint(VibePalette.amber)
        }
        .padding(.vertical, 20)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeAlarm(id: row.id)
            } label: {
                Label("Delete Alarm", systemImage: "trash")
            }
        }
    }

    /// The per-row today/tomorrow readout. This is the product's point, so it is always
    /// visible: an instrument label pair rather than a chip.
    private func stateReadout(_ row: AlarmRow) -> some View {
        HStack(spacing: 18) {
            readoutItem(label: "TODAY", day: row.today)
            readoutItem(label: "TOMORROW", day: row.tomorrow)
        }
    }

    private func readoutItem(label: String, day: ResolvedDayAlarm) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(VibePalette.inkFaint.opacity(0.85))
            Text(stateText(day))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(stateTone(day))
        }
    }

    private func stateText(_ day: ResolvedDayAlarm) -> String {
        if day.status.isRinging {
            return day.effectiveTime ?? day.baseTime
        }
        if day.status == .skippedManually {
            return "Skipped"
        }
        return "Off"
    }

    private func stateTone(_ day: ResolvedDayAlarm) -> Color {
        if case .delayed = day.status {
            return VibePalette.amber
        }
        return day.status.isRinging ? VibePalette.ink : VibePalette.inkFaint
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
                .padding(.bottom, 6)
            Text("Overrides apply to tomorrow only, and clear themselves the day after. Everything is computed on this iPhone.")
                .font(.system(size: 11.5))
                .lineSpacing(3)
                .foregroundStyle(VibePalette.inkFaint)
        }
    }

    // MARK: - Derived

    private var tomorrowWillRing: Bool {
        viewModel.alarmRows.contains { $0.tomorrow.status.isRinging }
    }

    private var hasOverride: Bool {
        viewModel.snapshot.nextDayOverride != nil
    }

    /// The earliest alarm decides what the top bar reports.
    private var primaryTomorrow: ResolvedDayAlarm? {
        viewModel.alarmRows
            .filter { $0.rule.isEnabled }
            .map(\.tomorrow)
            .first
    }

    private var tomorrowStateSummary: String {
        guard let day = primaryTomorrow else { return "ALL OFF" }
        if day.status.isRinging {
            return (day.effectiveTime ?? day.baseTime).uppercased()
        }
        return widgetReasonShort(day).uppercased()
    }

    private func widgetReasonShort(_ day: ResolvedDayAlarm) -> String {
        switch day.status {
        case .skippedByHoliday(let reason), .skippedByPersonalLeave(let reason):
            return reason
        case .skippedManually:
            return "Skipped"
        case .noAlarm:
            return "No alarm"
        case .delayed(let minutes):
            return "Delayed \(minutes) min"
        case .scheduled:
            return "Ringing"
        }
    }

    private var tomorrowDateCaption: String {
        guard let dateString = viewModel.alarmRows.first?.tomorrow.date,
              let date = AlarmScheduleEngine().date(from: dateString) else {
            return ""
        }
        return Self.dayFormatter.string(from: date).uppercased()
    }

    private func repeatSummary(_ rule: AlarmRule) -> String {
        switch rule.repeatMode {
        case .weekdays: return "Monday to Friday · holiday aware"
        case .everyday: return "Every day"
        case .weekends: return "Saturday and Sunday"
        case .customDays(let days):
            if days.isEmpty { return "No days selected" }
            let ordered: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            return ordered.filter { days.contains($0) }.map(\.shortWeekdayName).joined(separator: " ")
        case .specificDates(let dates):
            if dates.isEmpty { return "No dates set" }
            return dates.sorted().joined(separator: ", ")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}

// MARK: - Key Press

/// Keys travel a fraction of a millimetre and lose their shadow. Nothing scales much,
/// because a machined key does not squish.
struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Sheet Identity

/// A sheet needs an `Identifiable`; `UUID` is not one on every SDK this builds against.
private struct EditingTarget: Identifiable {
    let id: UUID
}
