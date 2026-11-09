import SwiftUI
import UIKit
import VibeAlarmCore

/// The Calendar tab: a machined month plate with engraved day cells, then the entries for the
/// selected day.
///
/// Day markers carry kind through shape rather than colour, because the app has exactly one
/// accent: a filled amber dot is a public holiday, a hollow ring is a makeup workday, and a short
/// bar is personal leave. The grid sits on the paper with no card around it, so the month reads as
/// an instrument face rather than a widget.
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    monthPlate
                        .padding(.top, 22)
                    legend
                        .padding(.top, 18)
                    entriesBlock
                        .padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        .tint(VibePalette.amber)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(VibePalette.ink)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    showBYOKSheet = true
                } label: {
                    Text("Import")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VibePalette.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 8)
                        .machinedPlate(corner: 13)
                }
                .buttonStyle(KeyPressStyle())
                .accessibilityLabel("Add Entry With AI")

                Button {
                    editingEntry = nil
                    showEditorSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VibePalette.ink)
                        .frame(width: 44, height: 44)
                        .machinedPlate(corner: 13)
                }
                .buttonStyle(KeyPressStyle())
                .accessibilityLabel("Add Entry")
            }
        }
        .padding(.top, 14)
    }

    // MARK: - Month Plate

    private var monthPlate: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayHeaderRow
            monthGrid
        }
    }

    private var monthHeader: some View {
        HStack {
            monthStepKey(systemName: "chevron.left", label: "Previous Month") {
                shiftMonth(by: -1)
            }

            Spacer()

            VStack(spacing: 3) {
                Text(Self.monthFullNames[displayedMonth - 1])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VibePalette.inkSoft)
                Text(String(displayedYear))
                    .font(.title2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(VibePalette.ink)
            }

            Spacer()

            monthStepKey(systemName: "chevron.right", label: "Next Month") {
                shiftMonth(by: 1)
            }
        }
    }

    private func monthStepKey(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(VibePalette.inkSoft)
                .frame(width: 44, height: 44)
                .machinedPlate(corner: 19)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(label)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdayHeaders.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VibePalette.inkFaint.opacity(0.85))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
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
                                .frame(height: 44)
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
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(VibePalette.ink)
                    .frame(minWidth: 32, minHeight: 32)
                    .background {
                        if isSelected {
                            Circle().fill(VibePalette.paperDeep.opacity(0.9))
                            Circle()
                                .strokeBorder(VibePalette.hairline.opacity(0.9), lineWidth: 0.7)
                        } else if isToday {
                            Circle().strokeBorder(VibePalette.amber.opacity(0.85), lineWidth: 1)
                        }
                    }

                markerRow(kinds)
                    .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(day: day, kinds: kinds))
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
                        .fill(VibePalette.amber)
                        .frame(width: 6, height: 6)
                case .makeupWorkday:
                    Circle()
                        .strokeBorder(VibePalette.inkSoft, lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                case .personalLeave:
                    Capsule()
                        .fill(VibePalette.inkSoft)
                        .frame(width: 8, height: 2.5)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(shape: AnyView(Circle().fill(VibePalette.amber).frame(width: 6, height: 6)), text: "Holiday")
            legendItem(
                shape: AnyView(Circle().strokeBorder(VibePalette.inkSoft, lineWidth: 1.5).frame(width: 6, height: 6)),
                text: "Makeup workday"
            )
            legendItem(shape: AnyView(Capsule().fill(VibePalette.inkSoft).frame(width: 8, height: 2.5)), text: "Leave")
        }
    }

    private func legendItem(shape: AnyView, text: String) -> some View {
        HStack(spacing: 6) {
            shape
            Text(text)
                .font(.caption)
                .foregroundStyle(VibePalette.inkFaint)
        }
    }

    // MARK: - Entries

    private var entriesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(listHeaderTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VibePalette.inkSoft)
                Spacer()
                Text("\(listedEntries.count)")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(VibePalette.inkFaint)
            }
            .padding(.bottom, 10)

            Hairline()

            if listedEntries.isEmpty {
                Text("No entries. Holiday feeds fill this in when they sync; you can also add a day by hand.")
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(VibePalette.inkFaint)
                    .padding(.top, 16)
            } else {
                ForEach(Array(listedEntries.enumerated()), id: \.offset) { _, entry in
                    entryRow(entry)
                }
            }
        }
    }

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
        VStack(spacing: 0) {
            Button {
                editingEntry = entry
                showEditorSheet = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.body)
                            .foregroundStyle(VibePalette.ink)
                            .lineLimit(1)
                        Text("\(Self.monthDayCaption(entry.date)) · \(entry.kind.displayTitle)")
                            .font(.footnote)
                            .foregroundStyle(VibePalette.inkFaint)
                    }
                    Spacer(minLength: 8)
                    Text(entry.source.displayName)
                        .font(.caption)
                        .foregroundStyle(VibePalette.inkFaint.opacity(0.9))
                        .lineLimit(1)
                }
                .padding(.vertical, 14)
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
            Hairline()
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
        var m = displayedMonth + delta
        var y = displayedYear
        if m < 1 {
            m = 12
            y -= 1
        } else if m > 12 {
            m = 1
            y += 1
        }
        withAnimation(VibeMotion.settle(reduceMotion)) {
            displayedMonth = m
            displayedYear = y
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

    private static func accessibilityLabel(day: Int, kinds: [HolidayEntryKind]) -> String {
        guard !kinds.isEmpty else { return "\(day)" }
        let names = kinds.map(\.displayTitle).joined(separator: ", ")
        return "\(day), \(names)"
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    field("Title") {
                        TextField("Holiday name", text: $title)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .recessedWell(corner: 12)
                    }

                    field("Date") {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(VibePalette.amber)
                    }

                    field("Kind") {
                        Picker("Kind", selection: $kind) {
                            Text("Holiday").tag(HolidayEntryKind.publicHoliday)
                            Text("Workday").tag(HolidayEntryKind.makeupWorkday)
                            Text("Leave").tag(HolidayEntryKind.personalLeave)
                        }
                        .pickerStyle(.segmented)
                    }

                    field("Note") {
                        TextField("Optional", text: $note, axis: .vertical)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .recessedWell(corner: 12)
                    }

                    if existingEntry != nil {
                        Button {
                            if let existingEntry { viewModel.deleteHolidayEntry(existingEntry) }
                            dismiss()
                        } label: {
                            Text("Delete Entry")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VibePalette.inkSoft)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .machinedPlate(corner: 15)
                        }
                        .buttonStyle(KeyPressStyle())
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(VibePalette.paper.ignoresSafeArea())
            .navigationTitle(existingEntry == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(VibePalette.inkSoft)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(VibePalette.amber)
    }

    private func field<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(caption)
                .vibeCaption()
            content()
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
