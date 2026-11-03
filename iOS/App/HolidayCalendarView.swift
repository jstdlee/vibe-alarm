import SwiftUI
import VibeAlarmCore

/// The Calendar tab: a month grid with small colored markers (red = holiday,
/// blue = makeup workday, green = leave), and a native list of entries for the
/// selected day (or the whole month when nothing is selected).
public struct HolidayCalendarView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var displayedYear: Int
    @State private var displayedMonth: Int
    @State private var selectedDateString: String?

    @State private var showEditorSheet = false
    @State private var editingEntry: HolidayCalendarEntry?
    @State private var showBYOKSheet = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let todayDate = viewModel.todayAlarm.date
        let parts = todayDate.split(separator: "-")
        let year = parts.count > 0 ? (Int(parts[0]) ?? 2026) : 2026
        let month = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        _displayedYear = State(initialValue: year)
        _displayedMonth = State(initialValue: month)
        _selectedDateString = State(initialValue: todayDate)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    monthGridCard
                }
                .listRowInsets(EdgeInsets())

                Section {
                    ForEach(listedEntries) { entry in
                        entryRow(entry)
                    }
                } header: {
                    Text(listHeaderTitle)
                }
            }
            .listStyle(.insetGrouped)
            // Keep the last rows clear of the floating tab bar.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingEntry = nil
                        showEditorSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Entry")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Import with AI") {
                        showBYOKSheet = true
                    }
                }
            }
            .sheet(isPresented: $showEditorSheet) {
                HolidayEntryEditorSheet(
                    viewModel: viewModel,
                    initialDateString: editingEntry?.date ?? (selectedDateString ?? viewModel.todayAlarm.date),
                    existingEntry: editingEntry
                )
            }
            .sheet(isPresented: $showBYOKSheet) {
                BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
            }
        }
        .tint(.vibeAccent)
    }

    // MARK: - Month Grid

    private var monthGridCard: some View {
        VStack(spacing: 10) {
            monthHeader
            weekdayHeaderRow
            monthGrid
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(Self.monthFullNames[displayedMonth - 1]) \(String(displayedYear))")
                .font(.headline)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdayHeaders.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let cells = Self.buildMonthCells(year: displayedYear, month: displayedMonth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let day = cell.day, let dateStr = cell.dateString {
                    dayCell(day: day, dateStr: dateStr)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(day: Int, dateStr: String) -> some View {
        let kinds = distinctKinds(for: dateStr)
        let isSelected = dateStr == selectedDateString
        let isToday = dateStr == viewModel.todayAlarm.date

        return Button {
            selectedDateString = isSelected ? nil : dateStr
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.system(size: 15, weight: isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSelected ? Color.vibeAccent : Color.clear))
                    .overlay(
                        Circle().strokeBorder(
                            (isToday && !isSelected) ? Color.vibeAccent : Color.clear,
                            lineWidth: 1.5
                        )
                    )

                HStack(spacing: 3) {
                    ForEach(kinds, id: \.self) { kind in
                        Circle().fill(dotColor(kind)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day)")
    }

    // MARK: - Entries List

    private var listedEntries: [HolidayCalendarEntry] {
        if let selectedDateString {
            return viewModel.snapshot.holidayEntries
                .filter { $0.date == selectedDateString }
                .sorted { $0.title < $1.title }
        }
        let prefix = String(format: "%04d-%02d", displayedYear, displayedMonth)
        return viewModel.snapshot.holidayEntries
            .filter { $0.date.hasPrefix(prefix) }
            .sorted { $0.date < $1.date }
    }

    private var listHeaderTitle: String {
        if let selectedDateString {
            return Self.monthDayCaption(selectedDateString)
        }
        return "\(Self.monthFullNames[displayedMonth - 1]) \(String(displayedYear))"
    }

    private func entryRow(_ entry: HolidayCalendarEntry) -> some View {
        Button {
            editingEntry = entry
            showEditorSheet = true
        } label: {
            HStack(spacing: 10) {
                Circle().fill(dotColor(entry.kind)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .foregroundStyle(.primary)
                    Text("\(Self.monthDayCaption(entry.date)) · \(entry.kind.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.source.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                viewModel.deleteHolidayEntry(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func distinctKinds(for dateStr: String) -> [HolidayEntryKind] {
        var seen = Set<HolidayEntryKind>()
        var result: [HolidayEntryKind] = []
        for entry in viewModel.snapshot.holidayEntries where entry.date == dateStr {
            if seen.insert(entry.kind).inserted {
                result.append(entry.kind)
            }
        }
        return result
    }

    private func dotColor(_ kind: HolidayEntryKind) -> Color {
        switch kind {
        case .publicHoliday: return .red
        case .makeupWorkday: return .blue
        case .personalLeave: return .green
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

    private struct MonthDayCell {
        let day: Int?
        let dateString: String?
    }

    private static func buildMonthCells(year: Int, month: Int) -> [MonthDayCell] {
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

// MARK: - Add / Edit Entry Sheet

public struct HolidayEntryEditorSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let existingEntry: HolidayCalendarEntry?

    @State private var title: String
    @State private var date: Date
    @State private var kind: HolidayEntryKind
    @State private var note: String

    public init(viewModel: AppViewModel, initialDateString: String, existingEntry: HolidayCalendarEntry?) {
        self.viewModel = viewModel
        self.existingEntry = existingEntry
        _title = State(initialValue: existingEntry?.title ?? "")
        _kind = State(initialValue: existingEntry?.kind ?? .personalLeave)
        _note = State(initialValue: existingEntry?.note ?? "")
        let engine = AlarmScheduleEngine()
        let seedDateString = existingEntry?.date ?? initialDateString
        _date = State(initialValue: engine.date(from: seedDateString) ?? Date())
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Kind", selection: $kind) {
                        Text("Holiday").tag(HolidayEntryKind.publicHoliday)
                        Text("Workday").tag(HolidayEntryKind.makeupWorkday)
                        Text("Leave").tag(HolidayEntryKind.personalLeave)
                    }
                    .pickerStyle(.segmented)
                    TextField("Note", text: $note, axis: .vertical)
                }

                if existingEntry != nil {
                    Section {
                        Button("Delete Entry", role: .destructive) {
                            if let existingEntry {
                                viewModel.deleteHolidayEntry(existingEntry)
                            }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(existingEntry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(.vibeAccent)
    }

    private func save() {
        let engine = AlarmScheduleEngine()
        let dateString = engine.dateString(from: date)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? kind.displayTitle : cleanTitle

        if let existingEntry {
            viewModel.updateHolidayEntry(
                oldEntry: existingEntry,
                newDate: dateString,
                newTitle: finalTitle,
                newKind: kind,
                newNote: note
            )
        } else {
            viewModel.addManualHolidayEntry(date: dateString, title: finalTitle, kind: kind, note: note)
        }
        dismiss()
    }
}
