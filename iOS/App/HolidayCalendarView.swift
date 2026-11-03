import SwiftUI
import VibeAlarmCore

/// Screen 3 ("Calendar"): Braun/Apple Light Theme built-in calendar & events manager.
/// Interactive monthly grid with `OFF` / `WRK` / `PTO` micro-pills, a horizontal roller filter,
/// and full CRUD for holidays, makeup workdays, and personal leave.
public struct HolidayCalendarView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var displayedYear: Int = 2026
    @State private var displayedMonth: Int = 11
    @State private var selectedDateString: String = "2026-11-09"

    @State private var eventTitleInput: String = ""
    @State private var eventKindSelection: HolidayEntryKind = .personalLeave
    @State private var editingEntry: HolidayCalendarEntry?
    @State private var showEditorCard: Bool = false

    @State private var filterRollerIndex: Int = 0
    @State private var showBYOKSheet: Bool = false

    private let filterOptions: [String] = ["All", "Holidays", "Workdays", "Leave"]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    monthBar
                    monthlyCalendarCard
                    filterRollerCard

                    if showEditorCard {
                        eventEditorCard
                    }

                    eventsListCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color.vibeCanvas)
            .navigationBarHidden(true)
            .sheet(isPresented: $showBYOKSheet) {
                BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
            }
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }

    // MARK: - Month Bar

    private var monthBar: some View {
        HStack(spacing: 10) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.vibeAccent)
            }
            .buttonStyle(.plain)

            Text("\(Self.monthFullNames[displayedMonth - 1]) \(displayedYear)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.vibeAccent)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                editingEntry = nil
                eventTitleInput = ""
                showEditorCard = true
            } label: {
                Text("+ Add")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.vibeAccent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                showBYOKSheet = true
            } label: {
                Text("AI Parse")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Monthly Calendar Grid

    private var monthlyCalendarCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                legendDot(label: "Holiday", color: .vibeAccent)
                legendDot(label: "Workday", color: .vibeWork)
                legendDot(label: "Leave", color: .vibePTO)
                Spacer()
            }

            HStack(spacing: 0) {
                ForEach(Array(Self.weekdayHeaders.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(idx >= 5 ? Color.vibeAccent : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let cells = buildMonthCells(year: displayedYear, month: displayedMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let dayNum = cell.day, let dateStr = cell.dateString {
                        dayCell(dayNum: dayNum, dateStr: dateStr)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding(14)
        .vibeCard()
    }

    private func dayCell(dayNum: Int, dateStr: String) -> some View {
        let matched = entriesForDate(dateStr)
        let isSelected = dateStr == selectedDateString
        let isToday = dateStr == viewModel.todayAlarm.date

        return Button {
            selectedDateString = dateStr
            if let first = matched.first {
                editingEntry = first
                eventTitleInput = first.title
                eventKindSelection = first.kind
            } else {
                editingEntry = nil
                eventTitleInput = ""
                eventKindSelection = .personalLeave
            }
            showEditorCard = true
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNum)")
                    .font(.system(size: 14, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : (isToday ? Color.vibeAccent : Color.primary)
                    )

                if let primaryEntry = matched.first {
                    Text(primaryEntry.kind.shortBadge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : badgeColor(for: primaryEntry.kind).opacity(0.15))
                        )
                        .foregroundStyle(isSelected ? Color.white : badgeColor(for: primaryEntry.kind))
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.vibeAccent : (isToday ? Color.vibeAccent.opacity(0.10) : Color(uiColor: .systemGray6).opacity(0.5)))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Roller

    private var filterRollerCard: some View {
        SkeuomorphicHorizontalRoller(
            title: "FILTER",
            options: filterOptions,
            selectedIndex: filterRollerIndex
        ) { newIdx in
            filterRollerIndex = newIdx
        }
        .padding(10)
        .vibeCard()
    }

    // MARK: - Add / Edit Event Card

    private var eventEditorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(editingEntry == nil ? "New Entry · \(selectedDateString)" : "Edit Entry · \(selectedDateString)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showEditorCard = false
                    editingEntry = nil
                    eventTitleInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Event name (e.g. Annual Leave)", text: $eventTitleInput)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(uiColor: .systemGray6))
                )

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
                    } else {
                        viewModel.addManualHolidayEntry(
                            date: selectedDateString,
                            title: finalTitle,
                            kind: eventKindSelection
                        )
                    }
                    showEditorCard = false
                    editingEntry = nil
                    eventTitleInput = ""
                } label: {
                    Text(editingEntry == nil ? "Save" : "Update")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.vibeAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if let existing = editingEntry {
                    Button {
                        viewModel.deleteHolidayEntry(existing)
                        showEditorCard = false
                        editingEntry = nil
                        eventTitleInput = ""
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .vibeCard()
    }

    // MARK: - Entries List

    private var eventsListCard: some View {
        let items = filteredEntries
        return VStack(alignment: .leading, spacing: 4) {
            Text("THIS MONTH · \(items.count)")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                    }
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
                                .lineLimit(1)
                            Text(entry.date)
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
                            showEditorCard = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.vibeAccent)
                                .padding(6)
                                .background(Color.vibeAccent.opacity(0.10))
                                .clipShape(Circle())
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
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(14)
        .vibeCard()
    }

    // MARK: - Helpers

    private var filteredEntries: [HolidayCalendarEntry] {
        let prefix = String(format: "%04d-%02d", displayedYear, displayedMonth)
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

    private func badgeColor(for kind: HolidayEntryKind) -> Color {
        switch kind {
        case .publicHoliday: return .vibeAccent
        case .makeupWorkday: return .vibeWork
        case .personalLeave: return .vibePTO
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

    private static let weekdayHeaders = ["M", "T", "W", "T", "F", "S", "S"]

    private static let monthFullNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    private struct MonthDayCell {
        let day: Int?
        let dateString: String?
    }

    private func buildMonthCells(year: Int, month: Int) -> [MonthDayCell] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday, to match the "M T W T F S S" header
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) // 1 (Sun) ... 7 (Sat)
        let leadingEmpty = (weekdayOfFirst - cal.firstWeekday + 7) % 7

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
