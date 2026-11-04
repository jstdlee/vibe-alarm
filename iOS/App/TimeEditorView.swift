import SwiftUI
import VibeAlarmCore

/// The wake time editor for one alarm.
///
/// One column, top to bottom: the alarm's name, the instrument row (repeat, holiday, snooze), then the two big discs
/// that fill the lower half of the display where a thumb already rests. Nothing carries a title
/// above it: a disc prints its unit inside its reading well, and each instrument cell prints its own caption. The page is mostly empty paper on purpose, so the two
/// volumes at the bottom are the only things asking to be touched.
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
        GeometryReader { geo in
            let isCompact = geo.size.height < 720
            // The discs are deliberately wider than half the display. `DiscPair` seats each
            // centre outside the bezel, so a taller phone buys air, not a bigger circle.
            let discDiameter = min(geo.size.width * (isCompact ? 0.86 : 0.98), isCompact ? 322 : 400)

            VStack(spacing: 0) {
                titleBlock(isCompact: isCompact)

                WakeOptionsInstrumentRow(
                    repeatMode: repeatMode,
                    onceDate: onceDate,
                    holidaySmart: holidaySmart,
                    snoozeMinutes: viewModel.snoozeMinutes,
                    onOpen: { activeSheet = $0 },
                    onCycleRepeat: { step in
                        selectRepeatIndex((repeatIndex + step + 5) % 5)
                    },
                    onHolidayChange: { holidaySmart = $0 },
                    onSnoozeChange: { viewModel.setSnoozeMinutes($0) }
                )
                .padding(.horizontal, 24)
                .padding(.top, isCompact ? 14 : 26)

                Spacer(minLength: 0)

                DiscPair(
                    diameter: discDiameter,
                    leadingValue: hour,
                    leadingCount: 24,
                    leadingStep: 1,
                    leadingLabel: "Hour",
                    trailingValue: minute,
                    trailingCount: 60,
                    trailingStep: 5,
                    trailingLabel: "Min",
                    onLeadingChange: { hour = $0 },
                    onTrailingChange: { minute = $0 }
                )
                .padding(.bottom, -(discDiameter * (isCompact ? 0.14 : 0.20)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(VibePalette.paper.ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .statusBarHidden(false)
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

    // MARK: - Top Bar

    /// A toolbar drawn by hand so the bar sits on the paper instead of a material block.
    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VibePalette.inkSoft)
            Spacer()
            Button("Save") { save() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VibePalette.amber)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    // MARK: - Title

    /// The alarm's own name is the page title. The time itself is on the discs, so there is no
    /// second, larger copy of it here to compete with them.
    private func titleBlock(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WAKE TIME")
                .vibeCaption()
            Text(alarmLabel)
                .font(.system(size: isCompact ? 26 : 30, weight: .light))
                .foregroundStyle(VibePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, isCompact ? 40 : 52)
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

    // MARK: - Save

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
