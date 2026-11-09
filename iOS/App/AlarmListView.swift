import SwiftUI
import UIKit
import VibeAlarmCore

/// The home screen: tomorrow's override actions, then every alarm.
public struct AlarmListView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var editing: EditingTarget?
    @ScaledMetric(relativeTo: .title) private var timeSize: CGFloat = 34

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    tomorrowSummary
                    quickActions
                } header: {
                    Text("Tomorrow")
                } footer: {
                    Text("Overrides apply to tomorrow only, and clear themselves the day after. Everything is computed on this iPhone.")
                }

                Section("Alarms") {
                    ForEach(viewModel.alarmRows) { row in
                        alarmRow(row)
                    }
                }
            }
            .navigationTitle("Alarms")
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
            .sheet(item: $editing) { target in
                TimeEditorView(viewModel: viewModel, alarmID: target.id)
                    .presentationDragIndicator(.visible)
            }
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
