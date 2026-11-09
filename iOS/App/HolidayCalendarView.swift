import SwiftUI
import UIKit
import VibeAlarmCore

/// The Calendar tab: a month grid, then the entries for the selected day.
public struct HolidayCalendarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    monthPlate
                    legend
                } footer: {
                    Text("A dot is a public holiday, a ring is a makeup workday, and a bar is personal leave.")
                }

                Section(listHeaderTitle) {
                    if listedEntries.isEmpty {
                        Text("No entries. Holiday feeds fill this in when they sync; you can also add a day by hand.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(listedEntries, id: \.id) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showBYOKSheet = true
                    } label: {
                        Image(systemName: "text.document")
                    }
                    .accessibilityLabel("Add Entry With AI")

                    Button {
                        editingEntry = nil
                        showEditorSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Entry")
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
    }

    // MARK: - Month

    private var monthPlate: some View {
        VStack(spacing: 8) {
            monthHeader
            weekdayHeaderRow
            monthGrid
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 8))
    }

    private var monthHeader: some View {
        HStack {
            monthStepButton(systemName: "chevron.left", label: "Previous Month") {
                shiftMonth(by: -1)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(Self.monthFullNames[displayedMonth - 1])
                    .font(.headline)
                Text(String(displayedYear))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            monthStepButton(systemName: "chevron.right", label: "Next Month") {
                shiftMonth(by: 1)
            }
        }
    }

    private func monthStepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdayHeaders.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Plain, non-lazy week rows. A LazyVGrid inside a self-sizing container can trigger an
    /// endless layout pass, so the grid is built from fixed rows instead.
    private var monthGrid: some View {
        let weeks = Self.buildMonthWeeks(year: displayedYear, month: displayedMonth)
        return VStack(spacing: 2) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let cell = weeks[weekIndex][column]
                        if let day = cell.day, let dateStr = cell.dateString {
                            dayCell(day: day, dateStr: dateStr)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(day: Int, dateStr: String) -> some View {
        let kinds = distinctKinds(for: dateStr)
        let isSelected = dateStr == selectedDateString
        let isToday = dateStr == viewModel.todayAlarm.date

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedDateString = isSelected ? nil : dateStr
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            Circle().fill(Color(.tertiarySystemFill))
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }

                markerRow(kinds)
                    .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(day: day, kinds: kinds, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Kind read as shape: filled dot for a public holiday, hollow ring for a makeup workday,
    /// short bar for personal leave.
    private func markerRow(_ kinds: [HolidayEntryKind]) -> some View {
        HStack(spacing: 4) {
            ForEach(kinds, id: \.self) { kind in
                switch kind {
                case .publicHoliday:
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                case .makeupWorkday:
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                case .personalLeave:
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 2)
                }
            }
        }
        .frame(minHeight: 8)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(kind: .publicHoliday, text: "Holiday")
            legendItem(kind: .makeupWorkday, text: "Makeup")
            legendItem(kind: .personalLeave, text: "Leave")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(kind: HolidayEntryKind, text: String) -> some View {
        HStack(spacing: 6) {
            markerRow([kind])
            Text(text)
        }
    }

    // MARK: - Entries

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
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(Self.monthDayCaption(entry.date)) · \(entry.kind.displayTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.source.displayName)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteHolidayEntry(entry)
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                viewModel.deleteHolidayEntry(entry)
            } label: {
                Label("Delete Entry", systemImage: "trash")
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

    private func shiftMonth(by delta: Int) {
        var month = displayedMonth + delta
        var year = displayedYear
        if month < 1 {
            month = 12
            year -= 1
        } else if month > 12 {
            month = 1
            year += 1
        }
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.16)
        withAnimation(animation) {
            displayedMonth = month
            displayedYear = year
        }
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

    private static func accessibilityLabel(day: Int, kinds: [HolidayEntryKind], isToday: Bool) -> String {
        var parts = ["\(day)"]
        if isToday { parts.append("today") }
        if !kinds.isEmpty {
            parts.append(kinds.map(\.displayTitle).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
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
        for day in range {
            let dateString = String(format: "%04d-%02d-%02d", year, month, day)
            cells.append(MonthDayCell(day: day, dateString: dateString))
        }
        return cells
    }

    /// Splits the month cells into full weeks of exactly seven cells each.
    private static func buildMonthWeeks(year: Int, month: Int) -> [[MonthDayCell]] {
        var cells = buildMonthCells(year: year, month: month)
        while cells.count % 7 != 0 {
            cells.append(MonthDayCell(day: nil, dateString: nil))
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
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
                    TextField("Holiday name", text: $title)
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
                            if let existingEntry { viewModel.deleteHolidayEntry(existingEntry) }
                            dismiss()
                        }
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
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
