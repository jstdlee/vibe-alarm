import SwiftUI
import VibeAlarmCore

/// Built-in Calendar & Events Manager (`内置日历与事项管理` — Light Theme):
/// - Interactive Monthly Calendar Grid (`2026年 11月`) showing `休` (Holiday), `班` (Makeup Workday), and `假` (Personal Leave/Event) badges on each day.
/// - Skeuomorphic Horizontal Roller (`SkeuomorphicHorizontalRoller`) for filtering event types.
/// - Full CRUD (Add, Edit, Delete) for built-in calendar events, holidays, makeup workdays, and personal leave, plus quick entry to BYOK AI Notice Parsing.
public struct HolidayCalendarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    public var isEmbeddedInTab: Bool

    @State private var displayedYear: Int = 2026
    @State private var displayedMonth: Int = 11
    @State private var selectedDateString: String = "2026-11-09"

    @State private var eventTitleInput: String = ""
    @State private var eventKindSelection: HolidayEntryKind = .personalLeave
    @State private var editingEntry: HolidayCalendarEntry?

    @State private var filterRollerIndex: Int = 0
    @State private var showBYOKSheet: Bool = false

    private let filterOptions: [String] = [
        "全部日历事项",
        "公共假期 (休)",
        "调休补班 (班)",
        "个人请假 (假)"
    ]

    public init(viewModel: AppViewModel, isEmbeddedInTab: Bool = false) {
        self.viewModel = viewModel
        self.isEmbeddedInTab = isEmbeddedInTab
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // 1. INTERACTIVE MONTHLY CALENDAR GRID CARD
                    monthlyCalendarCard

                    // 2. SKEUOMORPHIC HORIZONTAL ROLLER FILTER
                    VStack(spacing: 6) {
                        SkeuomorphicHorizontalRoller(
                            title: "事项筛选",
                            options: filterOptions,
                            selectedIndex: filterRollerIndex
                        ) { newIdx in
                            filterRollerIndex = newIdx
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
                    )

                    // 3. ADD / EDIT BUILT-IN CALENDAR EVENT & HOLIDAY CARD
                    eventEditorCard

                    // 4. BUILT-IN CALENDAR & EVENTS LIST (WITH EDIT & DELETE)
                    eventsListCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("内置日历与事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showBYOKSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("AI 解析通知")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                }
                if !isEmbeddedInTab {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(isPresented: $showBYOKSheet) {
                BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
            }
        }
        .tint(.orange)
        .preferredColorScheme(.light)
    }

    // MARK: - 1. Interactive Monthly Calendar Grid

    private var monthlyCalendarCard: some View {
        VStack(spacing: 10) {
            // Month Header + Legend
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                Text(String(format: "%04d年 %02d月", displayedYear, displayedMonth))
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                Spacer()

                // Mini Legend for 休 / 班 / 假
                HStack(spacing: 8) {
                    legendDot(label: "公休", color: .red)
                    legendDot(label: "补班", color: .blue)
                    legendDot(label: "请假", color: .green)
                }
            }

            // Weekday Header Row
            let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { wd in
                    Text(wd)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(wd == "日" || wd == "六" ? Color.orange : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar Days Grid
            let cells = buildMonthCells(year: displayedYear, month: displayedMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let dayNum = cell.day, let dateStr = cell.dateString {
                        let matched = entriesForDate(dateStr)
                        let isSelected = dateStr == selectedDateString
                        let isToday = dateStr == viewModel.todayAlarm.date

                        Button {
                            selectedDateString = dateStr
                            if let first = matched.first {
                                editingEntry = first
                                eventTitleInput = first.title
                                eventKindSelection = first.kind
                            } else {
                                editingEntry = nil
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(dayNum)")
                                    .font(.system(size: 14, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(
                                        isSelected
                                            ? Color.white
                                            : (isToday ? Color.orange : Color.primary)
                                    )

                                if let primaryEntry = matched.first {
                                    Text(badgeText(for: primaryEntry.kind))
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule()
                                                .fill( isSelected ? Color.white.opacity(0.25) : badgeColor(for: primaryEntry.kind).opacity(0.15) )
                                        )
                                        .foregroundStyle(isSelected ? Color.white : badgeColor(for: primaryEntry.kind))
                                } else {
                                    Text("·")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.clear)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(isSelected ? Color.orange : (isToday ? Color.orange.opacity(0.10) : Color(uiColor: .systemGray6).opacity(0.55)))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - 3. Add / Edit Event Card (管理内置日历与事项 CRUD)

    private var eventEditorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    editingEntry == nil ? "新增内置日历事项 / 假期 / 调休" : "编辑事项 (\(selectedDateString))",
                    systemImage: editingEntry == nil ? "calendar.badge.plus" : "pencil.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text("选中日期: \(selectedDateString)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                TextField("输入事项名称（如：个人年假、春节调休补班）", text: $eventTitleInput)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(uiColor: .systemGray6))
                    )

                if editingEntry != nil {
                    Button("取消编辑") {
                        editingEntry = nil
                        eventTitleInput = ""
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(HolidayEntryKind.allCases, id: \.self) { kind in
                    let active = eventKindSelection == kind
                    Button {
                        eventKindSelection = kind
                    } label: {
                        Text(kind.displayTitle)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(active ? badgeColor(for: kind) : Color(uiColor: .systemGray6))
                            )
                            .foregroundStyle(active ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    let cleanTitle = eventTitleInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalTitle = cleanTitle.isEmpty ? eventKindSelection.displayTitle : cleanTitle
                    if let existing = editingEntry {
                        viewModel.updateHolidayEntry(
                            oldEntry: existing,
                            newDate: selectedDateString,
                            newTitle: finalTitle,
                            newKind: eventKindSelection
                        )
                        editingEntry = nil
                    } else {
                        viewModel.addManualHolidayEntry(
                            date: selectedDateString,
                            title: finalTitle,
                            kind: eventKindSelection
                        )
                    }
                    eventTitleInput = ""
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: editingEntry == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                        Text(editingEntry == nil ? "保存至内置日历" : "更新事项")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    showBYOKSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("粘贴放假通知解析")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.orange.opacity(0.14))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - 4. Filtered Built-in Calendar & Events List

    private var eventsListCard: some View {
        let items = filteredEntries
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已管理的日历事项与调休记录 (\(items.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("点击可编辑或删除")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(items) { entry in
                HStack(spacing: 10) {
                    Text(entry.kind.shortBadge)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(badgeColor(for: entry.kind).opacity(0.14))
                        )
                        .foregroundStyle(badgeColor(for: entry.kind))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(entry.date) · \(entry.source.displayName)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        selectedDateString = entry.date
                        editingEntry = entry
                        eventTitleInput = entry.title
                        eventKindSelection = entry.kind
                    } label: {
                        Text("编辑")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.deleteHolidayEntry(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(6)
                            .background(Color.red.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Helpers

    private var filteredEntries: [HolidayCalendarEntry] {
        let prefix = String(format: "%04d-%02d", displayYear, displayMonth)
        let all = viewModel.snapshot.holidayEntries.sorted { a, b in
            let aInMonth = a.date.hasPrefix(prefix)
            let bInMonth = b.date.hasPrefix(prefix)
            if aInMonth != bInMonth { return aInMonth }
            return a.date < b.date
        }
        switch filterRollerIndex {
        case 1:
            return all.filter { $0.kind == .publicHoliday }
        case 2:
            return all.filter { $0.kind == .makeupWorkday }
        case 3:
            return all.filter { $0.kind == .personalLeave }
        default:
            return all
        }
    }

    private func entriesForDate(_ dateStr: String) -> [HolidayCalendarEntry] {
        viewModel.snapshot.holidayEntries.filter { $0.date == dateStr }
    }

    private func badgeText(for kind: HolidayEntryKind) -> String {
        switch kind {
        case .publicHoliday: return "休"
        case .makeupWorkday: return "班"
        case .personalLeave: return "假"
        }
    }

    private func badgeColor(for kind: HolidayEntryKind) -> Color {
        switch kind {
        case .publicHoliday: return .red
        case .makeupWorkday: return .blue
        case .personalLeave: return .green
        }
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shiftMonth(by delta: Int) {
        var m = displayedMonth + delta
        var y = displayedYear
        if m < 1 {
            m = 12
            y -= 1
        } else if m > 12 {
            m = 1
            y += 1
        }
        displayedMonth = m
        displayedYear = y
    }

    private struct MonthDayCell {
        let day: Int?
        let dateString: String?
    }

    private func buildMonthCells(year: Int, month: Int) -> [MonthDayCell] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) // 1..7
        let leadingEmpty = weekdayOfFirst - 1

        var cells: [MonthDayCell] = []
        for _ in 0..<leadingEmpty {
            cells.append(MonthDayCell(day: nil, dateString: nil))
        }
        for d in range {
            let dStr = String(format: "%04d-%02d-%02d", year, month, d)
            cells.append(MonthDayCell(day: d, dateString: dStr))
        }
        return cells
    }
}
