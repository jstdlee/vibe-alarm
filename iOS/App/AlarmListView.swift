import SwiftUI
import UIKit
import VibeAlarmCore

/// The home screen: tomorrow's time, three keys, then every alarm.
public struct AlarmListView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var editing: EditingTarget?
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title) private var rowTimeSize: CGFloat = 40

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    heroBlock
                        .padding(.top, 20)
                    quickActionsBlock
                        .padding(.top, 20)
                    alarmRows
                        .padding(.top, 28)
                    footer
                        .padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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

    private var titleBlock: some View {
        HStack(alignment: .center) {
            Text("Alarms")
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(VibePalette.ink)
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.addAlarm()
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VibePalette.ink)
                    .frame(width: 44, height: 44)
                    .machinedPlate(corner: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Alarm")
        }
        .padding(.top, 8)
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tomorrowDateCaption)
                .font(.subheadline)
                .foregroundStyle(VibePalette.inkSoft)
            Text(tomorrowStateSummary)
                .font(.system(size: heroSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tomorrowWillRing ? VibePalette.ink : VibePalette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(heroDetail)
                .font(.body)
                .foregroundStyle(VibePalette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var quickActionsBlock: some View {
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
    }

    private func quickKey(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? VibePalette.ink : VibePalette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .machinedPlate(corner: 14, raised: enabled)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(enabled ? VibePalette.amber : Color.clear)
                        .frame(width: 16, height: 3)
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
    }

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
        HStack(alignment: .center, spacing: 12) {
            Button {
                editing = EditingTarget(id: row.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.rule.formattedBaseTime)
                        .font(.system(size: rowTimeSize, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(row.rule.isEnabled ? VibePalette.ink : VibePalette.inkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(row.rule.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(row.rule.isEnabled ? VibePalette.inkSoft : VibePalette.inkFaint)
                        .lineLimit(2)

                    Text(AlarmFormatting.repeatSummary(row.rule))
                        .font(.subheadline)
                        .foregroundStyle(VibePalette.inkFaint)
                        .lineLimit(2)

                    Text("Today \(AlarmFormatting.dayStateText(row.today)) · Tomorrow \(AlarmFormatting.dayStateText(row.tomorrow))")
                        .font(.footnote)
                        .foregroundStyle(VibePalette.inkSoft)
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
            .tint(VibePalette.amber)
            .accessibilityLabel("\(row.rule.label) enabled")
        }
        .padding(.vertical, 16)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.removeAlarm(id: row.id)
            } label: {
                Label("Delete Alarm", systemImage: "trash")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            Text(tomorrowFooter)
                .font(.footnote)
                .foregroundStyle(VibePalette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tomorrowWillRing: Bool {
        viewModel.alarmRows.contains { $0.tomorrow.status.isRinging }
    }

    private var hasOverride: Bool {
        viewModel.snapshot.nextDayOverride != nil
    }

    private var primaryTomorrow: ResolvedDayAlarm? {
        viewModel.alarmRows
            .filter { $0.rule.isEnabled }
            .map(\.tomorrow)
            .first
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

    private var tomorrowStateSummary: String {
        guard let day = primaryTomorrow else { return "Off" }
        if day.status.isRinging {
            return day.effectiveTime ?? day.baseTime
        }
        return "Off"
    }

    private var heroDetail: String {
        guard let row = viewModel.alarmRows.first(where: { $0.rule.isEnabled }) else {
            return "All alarms are off"
        }
        if row.tomorrow.status.isRinging {
            return row.rule.label
        }
        return AlarmFormatting.shortReason(row.tomorrow)
    }

    private var tomorrowDateCaption: String {
        guard let dateString = viewModel.alarmRows.first?.tomorrow.date,
              let date = AlarmScheduleEngine().date(from: dateString) else {
            return "Tomorrow"
        }
        return "Tomorrow · \(Self.dayFormatter.string(from: date))"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()
}

struct KeyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EditingTarget: Identifiable {
    let id: UUID
}
