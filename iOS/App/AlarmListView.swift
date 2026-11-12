import SwiftUI
import UIKit
import VibeAlarmCore

/// The home screen: tomorrow's override actions, then every alarm.
public struct AlarmListView: View {
    @ObservedObject var viewModel: AppViewModel

    @Environment(\.appearanceStyle) private var appearanceStyle
    @Environment(\.vibeTokens) private var tokens
    @State private var editing: EditingTarget?
    @ScaledMetric(relativeTo: .title) private var timeSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var bedsideTimeSize: CGFloat = 40

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if appearanceStyle == .bedside {
                bedsideBody
            } else {
                standardBody
            }
        }
        .sheet(item: $editing) { target in
            TimeEditorView(viewModel: viewModel, alarmID: target.id)
                .presentationDragIndicator(.visible)
        }
    }

    private var standardBody: some View {
        NavigationStack {
            List {
                Section {
                    tomorrowSummary
                    quickActions
                } header: {
                    Text("Tomorrow")
                } footer: {
                    Text(tomorrowFooter)
                }

                Section("Alarms") {
                    ForEach(viewModel.alarmRows) { row in
                        alarmRow(row)
                    }
                }
            }
            .navigationTitle("Alarms")
            .vibeChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.addAlarm()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Alarm")
                }
            }
        }
    }

    private var bedsideBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Alarms")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(tokens.ink)
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.addAlarm()
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(tokens.ink)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add Alarm")
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(tomorrowDateCaption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tokens.inkSoft)
                        Text(bedsideHeroTitle)
                            .font(.system(size: heroSize, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(tokens.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .padding(.top, 6)
                        Text(bedsideHeroDetail)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(tokens.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 6)
                    }
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)

                    bedsideQuickActions
                        .padding(.top, 18)

                    Text(bedsideNote)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(viewModel.alarmRows) { row in
                            bedsideAlarmRow(row)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(tokens.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(tokens.accent)
    }

    /// "Quiet tomorrow" when nothing rings, otherwise the time that will.
    private var bedsideHeroTitle: String {
        guard let day = primaryTomorrow else { return "All off" }
        if day.status.isRinging {
            return day.effectiveTime ?? day.baseTime
        }
        return "Quiet tomorrow"
    }

    private var bedsideHeroDetail: String {
        guard let day = primaryTomorrow else { return "All alarms are off" }
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
            return viewModel.alarmRows.first(where: { $0.rule.isEnabled })?.rule.label ?? "Ringing"
        }
    }

    private var bedsideNote: String {
        if !tomorrowWillRing {
            return "Nothing rings tomorrow, so Skip and +10 min stay off. Restore appears after a skip or delay."
        }
        if hasOverride {
            return "Restore clears the skip or delay on tomorrow."
        }
        return "Skip and +10 min change tomorrow only. Restore appears after a skip or delay."
    }

    private var bedsideQuickActions: some View {
        HStack(spacing: 8) {
            bedsideKey(title: "Skip", enabled: tomorrowWillRing) {
                viewModel.performTomorrowOverride(.skipTomorrow)
            }
            bedsideKey(title: "+10 min", enabled: tomorrowWillRing) {
                viewModel.incrementTomorrowDelay(by: 10)
            }
            bedsideKey(title: "Restore", enabled: hasOverride) {
                viewModel.performTomorrowOverride(.none)
            }
        }
    }

    private func bedsideKey(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(enabled ? tokens.ink : tokens.inkFaint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tokens.well.opacity(enabled ? 1 : 0.85))
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(actionHint(title: title, enabled: enabled))
    }

    private func bedsideAlarmRow(_ row: AlarmRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                editing = EditingTarget(id: row.id)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.rule.formattedBaseTime)
                        .font(.system(size: bedsideTimeSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(row.rule.isEnabled ? tokens.ink : tokens.inkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(row.rule.label)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tokens.ink)
                        .lineLimit(2)
                        .padding(.top, 8)
                    Text(AlarmFormatting.repeatSummary(row.rule))
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.inkSoft)
                        .lineLimit(2)
                        .padding(.top, 3)
                    Text("Today \(AlarmFormatting.dayStateText(row.today)) · tomorrow \(bedsideTomorrowPhrase(row.tomorrow))")
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.rule.label), \(row.rule.formattedBaseTime)")
            .accessibilityValue("Today \(AlarmFormatting.dayStateText(row.today)). Tomorrow \(AlarmFormatting.dayStateText(row.tomorrow)).")
            .accessibilityHint("Edits this alarm")

            Toggle(isOn: Binding(
                get: { row.rule.isEnabled },
                set: { isOn in
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.setAlarmEnabled(id: row.id, isEnabled: isOn)
                }
            )) {
                Text("Enabled")
            }
            .labelsHidden()
            .tint(tokens.accent)
            .accessibilityLabel("\(row.rule.label) enabled")
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(tokens.hairline).frame(height: 0.5)
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeAlarm(id: row.id)
            } label: {
                Label("Delete Alarm", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                viewModel.removeAlarm(id: row.id)
            } label: {
                Label("Delete Alarm", systemImage: "trash")
            }
        }
    }

    private func bedsideTomorrowPhrase(_ day: ResolvedDayAlarm) -> String {
        switch day.status {
        case .scheduled:
            return day.effectiveTime ?? day.baseTime
        case .delayed(let minutes):
            return "delayed \(minutes) min"
        case .skippedManually, .skippedByHoliday, .skippedByPersonalLeave:
            return "skipped"
        case .noAlarm:
            return "off"
        }
    }

    // MARK: - Tomorrow

    private var tomorrowSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tomorrowDateCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(tomorrowStateSummary)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickKey(title: "Skip", enabled: tomorrowWillRing) {
                viewModel.performTomorrowOverride(.skipTomorrow)
            }
            quickKey(title: "+10 min", enabled: tomorrowWillRing) {
                viewModel.incrementTomorrowDelay(by: 10)
            }
            quickKey(title: "Restore", enabled: hasOverride) {
                viewModel.performTomorrowOverride(.none)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
    }

    private func quickKey(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!enabled)
        .accessibilityHint(actionHint(title: title, enabled: enabled))
    }

    /// Skip and +10 min act only on a tomorrow that will ring. Restore clears a
    /// manual skip or delay, so it stays off when the holiday engine already did.
    private func actionHint(title: String, enabled: Bool) -> String {
        if enabled { return "Applies to tomorrow only" }
        if title == "Restore" { return "Available after a skip or delay" }
        return "Unavailable because tomorrow will not ring"
    }

    private var tomorrowFooter: String {
        let kept = "The change clears itself the day after. Everything is computed on this iPhone."
        if !tomorrowWillRing {
            return "Tomorrow will not ring, so Skip and +10 min are off. Restore is available after a skip or delay. \(kept)"
        }
        if !hasOverride {
            return "Skip and +10 min change tomorrow only. Restore is available after a skip or delay. \(kept)"
        }
        return "Restore clears the skip or delay on tomorrow. \(kept)"
    }

    // MARK: - Rows

    private func alarmRow(_ row: AlarmRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                editing = EditingTarget(id: row.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.rule.formattedBaseTime)
                        .font(.system(size: timeSize, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(row.rule.isEnabled ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(row.rule.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(AlarmFormatting.repeatSummary(row.rule))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("Today \(AlarmFormatting.dayStateText(row.today)) · Tomorrow \(AlarmFormatting.dayStateText(row.tomorrow))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.rule.label), \(row.rule.formattedBaseTime)")
            .accessibilityValue("Today \(AlarmFormatting.dayStateText(row.today)). Tomorrow \(AlarmFormatting.dayStateText(row.tomorrow)).")
            .accessibilityHint("Edits this alarm")

            Toggle(isOn: Binding(
                get: { row.rule.isEnabled },
                set: { isOn in
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.setAlarmEnabled(id: row.id, isEnabled: isOn)
                }
            )) {
                Text("Enabled")
            }
            .labelsHidden()
            .accessibilityLabel("\(row.rule.label) enabled")
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeAlarm(id: row.id)
            } label: {
                Label("Delete Alarm", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                viewModel.removeAlarm(id: row.id)
            } label: {
                Label("Delete Alarm", systemImage: "trash")
            }
        }
    }

    // MARK: - Derived

    private var tomorrowWillRing: Bool {
        viewModel.alarmRows.contains { $0.tomorrow.status.isRinging }
    }

    private var hasOverride: Bool {
        viewModel.snapshot.nextDayOverride != nil
    }

    /// The earliest enabled alarm decides what the tomorrow summary reports.
    private var primaryTomorrow: ResolvedDayAlarm? {
        viewModel.alarmRows
            .filter { $0.rule.isEnabled }
            .map(\.tomorrow)
            .first
    }

    private var tomorrowStateSummary: String {
        guard let day = primaryTomorrow else { return "All off" }
        if day.status.isRinging {
            return day.effectiveTime ?? day.baseTime
        }
        return AlarmFormatting.shortReason(day)
    }

    private var tomorrowDateCaption: String {
        guard let dateString = viewModel.alarmRows.first?.tomorrow.date,
              let date = AlarmScheduleEngine().date(from: dateString) else {
            return "Tomorrow"
        }
        return Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()
}

// MARK: - Sheet Identity

/// A sheet needs an `Identifiable`; `UUID` is not one on every SDK this builds against.
private struct EditingTarget: Identifiable {
    let id: UUID
}
