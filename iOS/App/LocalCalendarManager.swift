import EventKit
import Foundation
import VibeAlarmCore

public struct LocalCalendarSourceInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String
    public let colorHex: String

    public init(id: String, title: String, sourceTitle: String, colorHex: String = "#FF6B00") {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
    }

    public static let samplePreviewCalendars: [LocalCalendarSourceInfo] = [
        LocalCalendarSourceInfo(id: "cal-icloud-work", title: "Work", sourceTitle: "iCloud", colorHex: "#007AFF"),
        LocalCalendarSourceInfo(id: "cal-icloud-personal", title: "Personal", sourceTitle: "iCloud", colorHex: "#34C759"),
        LocalCalendarSourceInfo(id: "cal-exchange-corp", title: "Team PTO", sourceTitle: "Exchange", colorHex: "#FF9500"),
        LocalCalendarSourceInfo(id: "cal-local-birthdays", title: "Birthdays", sourceTitle: "iOS Built-in", colorHex: "#AF52DE")
    ]
}

/// Reads the user's local iPhone calendars via `EventKit` strictly on-device
/// to identify personal leave (PTO / Vacation / Annual Leave) for the upcoming 30 days.
@MainActor
public final class LocalCalendarManager: ObservableObject {
    private let eventStore = EKEventStore()

    @Published public private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published public private(set) var availableCalendars: [LocalCalendarSourceInfo] = []
    @Published public var isDemoAuthorized: Bool = false

    public init() {
        refreshAuthorizationStatus()
    }

    public func enableDemoPreviewCalendars() {
        isDemoAuthorized = true
        availableCalendars = LocalCalendarSourceInfo.samplePreviewCalendars
    }

    public func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if hasReadAccess {
            loadAvailableCalendars()
        } else if availableCalendars.isEmpty {
            availableCalendars = LocalCalendarSourceInfo.samplePreviewCalendars
        }
    }

    public var hasReadAccess: Bool {
        if isDemoAuthorized { return true }
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess || authorizationStatus == .authorized
        } else {
            return authorizationStatus == .authorized
        }
    }

    /// A short status word for the Sources screen's access row.
    public var accessStatusLabel: String {
        if isDemoAuthorized { return "Full Access" }
        switch authorizationStatus {
        case .notDetermined:
            return "Not Determined"
        case .denied, .restricted:
            return "Denied"
        case .fullAccess, .authorized:
            return "Full Access"
        case .writeOnly:
            return "Write Only"
        @unknown default:
            return "Not Determined"
        }
    }

    public func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            refreshAuthorizationStatus()
            return granted
        } catch {
            refreshAuthorizationStatus()
            return false
        }
    }

    public func loadAvailableCalendars() {
        let calendars = eventStore.calendars(for: .event)
        if calendars.isEmpty {
            availableCalendars = LocalCalendarSourceInfo.samplePreviewCalendars
            return
        }
        availableCalendars = calendars.map {
            LocalCalendarSourceInfo(
                id: $0.calendarIdentifier,
                title: $0.title,
                sourceTitle: $0.source?.title ?? "Local Calendar"
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func scanPersonalLeaveEntries(
        selectedCalendarIDs: [String],
        keywords: [String],
        referenceDate: Date = Date(),
        daysAhead: Int = 30
    ) -> [HolidayCalendarEntry] {
        guard hasReadAccess else { return [] }

        let allCalendars = eventStore.calendars(for: .event)
        let targetCalendars: [EKCalendar]?
        if selectedCalendarIDs.isEmpty {
            targetCalendars = nil
        } else {
            let filtered = allCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
            targetCalendars = filtered.isEmpty ? nil : filtered
        }

        let calendar = AlarmScheduleEngine.defaultCalendar()
        let engine = AlarmScheduleEngine(calendar: calendar)
        let startDate = calendar.startOfDay(for: referenceDate)
        guard let endDate = calendar.date(byAdding: .day, value: daysAhead, to: startDate) else {
            return []
        }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        let events = eventStore.events(matching: predicate)
        let activeKeywords = keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }

        var detected: [HolidayCalendarEntry] = []

        for event in events {
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (event.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = "\(title) \(notes)".lowercased()

            let matchedKeyword = activeKeywords.first { combined.contains($0) }
            guard matchedKeyword != nil else { continue }

            let kind = ICSHolidayParser.classifyEventKind(summary: title, description: notes)
            let finalKind: HolidayEntryKind = (kind == .publicHoliday) ? .personalLeave : kind

            var cursor = calendar.startOfDay(for: max(startDate, event.startDate))
            let eventEndDay = calendar.startOfDay(for: min(endDate, event.endDate))
            var safety = 0
            while cursor <= eventEndDay && safety < 35 {
                let dStr = engine.dateString(from: cursor)
                detected.append(
                    HolidayCalendarEntry(
                        date: dStr,
                        title: title.isEmpty ? "Calendar Leave" : title,
                        kind: finalKind,
                        source: .localEventKit
                    )
                )
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                safety += 1
            }
        }

        var seen = Set<String>()
        return detected.filter { seen.insert("\($0.date)|\($0.title)|\($0.kind.rawValue)").inserted }
            .sorted { $0.date < $1.date }
    }
}
