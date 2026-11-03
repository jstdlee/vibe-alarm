import Foundation

// MARK: - Weekday

public enum Weekday: Int, Codable, CaseIterable, Hashable, Sendable, Comparable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var shortWeekdayName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    public var compactLabel: String {
        switch self {
        case .sunday: return "Su"
        case .monday: return "Mo"
        case .tuesday: return "Tu"
        case .wednesday: return "We"
        case .thursday: return "Th"
        case .friday: return "Fr"
        case .saturday: return "Sa"
        }
    }

    public var isWeekend: Bool {
        self == .saturday || self == .sunday
    }

    public static let standardWeekdays: Set<Weekday> = [
        .monday, .tuesday, .wednesday, .thursday, .friday
    ]
}

// MARK: - Alarm Repeat Mode

public enum AlarmRepeatMode: Codable, Equatable, Hashable, Sendable {
    /// Monday through Friday, automatically respecting public holidays and statutory makeup workdays.
    case weekdays
    /// Every day of the week.
    case everyday
    /// Saturday and Sunday only.
    case weekends
    /// Custom selected days of the week.
    case customDays(Set<Weekday>)
    /// Specific calendar dates in `YYYY-MM-DD` format.
    case specificDates(Set<String>)

    public var summaryText: String {
        switch self {
        case .weekdays:
            return "Workdays (Smart Holiday & Makeup)"
        case .everyday:
            return "Every Day"
        case .weekends:
            return "Weekends"
        case .customDays(let days):
            if days == Weekday.standardWeekdays {
                return "Mon–Fri"
            }
            if days.isEmpty {
                return "One-Time"
            }
            return days.sorted().map(\.shortWeekdayName).joined(separator: " ")
        case .specificDates(let dates):
            if dates.isEmpty {
                return "No Dates Set"
            }
            let sorted = dates.sorted()
            if sorted.count <= 2 {
                return "Dates: " + sorted.joined(separator: ", ")
            }
            return "\(sorted.count) Dates Selected"
        }
    }
}

// MARK: - Alarm Rule

public struct AlarmRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var hour: Int
    public var minute: Int
    public var isEnabled: Bool
    public var repeatMode: AlarmRepeatMode
    /// When enabled, public holidays skip the alarm and statutory makeup workdays activate it on weekends.
    public var skipPublicHolidays: Bool
    /// When enabled, personal leave events (from local EventKit calendar or BYOK AI calendar) skip the alarm.
    public var skipPersonalLeave: Bool
    /// When enabled, one-click next-day skip/delay overrides automatically expire after tomorrow so the following day restores the normal schedule.
    public var autoRestoreNextDay: Bool
    /// Minutes since midnight (0...1439) for the pre-bedtime reminder notification (e.g. 22 * 60 + 30 = 22:30).
    public var preBedtimeReminderMinutes: Int
    public var bedtimeReminderEnabled: Bool
    /// Snooze interval in minutes applied when the user taps the wake notification's "Snooze" action. Default 8.
    public var snoozeMinutes: Int

    public init(
        id: UUID = UUID(),
        label: String = "Wake Alarm",
        hour: Int = 7,
        minute: Int = 30,
        isEnabled: Bool = true,
        repeatMode: AlarmRepeatMode = .weekdays,
        skipPublicHolidays: Bool = true,
        skipPersonalLeave: Bool = true,
        autoRestoreNextDay: Bool = true,
        preBedtimeReminderMinutes: Int = 22 * 60 + 30,
        bedtimeReminderEnabled: Bool = true,
        snoozeMinutes: Int = 8
    ) {
        self.id = id
        self.label = label
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
        self.isEnabled = isEnabled
        self.repeatMode = repeatMode
        self.skipPublicHolidays = skipPublicHolidays
        self.skipPersonalLeave = skipPersonalLeave
        self.autoRestoreNextDay = autoRestoreNextDay
        self.preBedtimeReminderMinutes = max(0, min(1439, preBedtimeReminderMinutes))
        self.bedtimeReminderEnabled = bedtimeReminderEnabled
        self.snoozeMinutes = AlarmRule.normalizedSnoozeMinutes(snoozeMinutes)
    }

    // MARK: - Snooze Interval

    /// Selectable snooze interval options presented in the UI (minutes).
    public static let snoozeIntervalOptions: [Int] = [5, 8, 10, 15, 20]

    /// Normalizes an arbitrary snooze value: non-positive values fall back to 8,
    /// values already in `snoozeIntervalOptions` pass through, and any other value
    /// snaps to the nearest option (e.g. 7 -> 8, 100 -> 20, 0 -> 8).
    public static func normalizedSnoozeMinutes(_ value: Int) -> Int {
        guard value > 0 else { return 8 }
        if snoozeIntervalOptions.contains(value) { return value }
        var best = snoozeIntervalOptions[0]
        var bestDistance = abs(value - best)
        for option in snoozeIntervalOptions.dropFirst() {
            let distance = abs(value - option)
            if distance < bestDistance {
                best = option
                bestDistance = distance
            }
        }
        return best
    }

    // MARK: - Codable (backward-compatible decoding of new keys)

    private enum CodingKeys: String, CodingKey {
        case id, label, hour, minute, isEnabled, repeatMode
        case skipPublicHolidays, skipPersonalLeave, autoRestoreNextDay
        case preBedtimeReminderMinutes, bedtimeReminderEnabled, snoozeMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        repeatMode = try container.decode(AlarmRepeatMode.self, forKey: .repeatMode)
        skipPublicHolidays = try container.decode(Bool.self, forKey: .skipPublicHolidays)
        skipPersonalLeave = try container.decode(Bool.self, forKey: .skipPersonalLeave)
        autoRestoreNextDay = try container.decode(Bool.self, forKey: .autoRestoreNextDay)
        preBedtimeReminderMinutes = try container.decode(Int.self, forKey: .preBedtimeReminderMinutes)
        bedtimeReminderEnabled = try container.decode(Bool.self, forKey: .bedtimeReminderEnabled)
        let rawSnooze = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 8
        snoozeMinutes = AlarmRule.normalizedSnoozeMinutes(rawSnooze)
    }

    public var formattedBaseTime: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public var formattedBedtimeReminder: String {
        let h = preBedtimeReminderMinutes / 60
        let m = preBedtimeReminderMinutes % 60
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - Next-Day Override (One-Tap Skip / Delay / Restore)

public enum NextDayOverrideAction: Codable, Equatable, Sendable {
    case none
    case skipTomorrow
    case delayTomorrow(minutes: Int)
    case forceKeepTomorrow
}

public struct NextDayOverride: Codable, Equatable, Sendable {
    public var action: NextDayOverrideAction
    /// Target date in `YYYY-MM-DD` format. Once the current date passes `targetDate`, the override automatically expires.
    public var targetDate: String
    public var createdAt: Date

    public init(
        action: NextDayOverrideAction,
        targetDate: String,
        createdAt: Date = Date()
    ) {
        self.action = action
        self.targetDate = targetDate
        self.createdAt = createdAt
    }

    public func isActive(for dateString: String) -> Bool {
        action != .none && targetDate == dateString
    }
}

// MARK: - Holiday & Leave Calendar Entry

public enum HolidayEntryKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    /// Statutory public holiday -> skips alarm.
    case publicHoliday
    /// Statutory makeup workday on a weekend -> triggers workday alarm.
    case makeupWorkday
    /// Personal vacation / PTO / leave -> skips alarm.
    case personalLeave

    public var displayTitle: String {
        switch self {
        case .publicHoliday: return "Public Holiday"
        case .makeupWorkday: return "Makeup Workday"
        case .personalLeave: return "Personal Leave"
        }
    }

    public var shortBadge: String {
        switch self {
        case .publicHoliday: return "OFF"
        case .makeupWorkday: return "WRK"
        case .personalLeave: return "PTO"
        }
    }
}

public enum HolidayEntrySource: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case builtin
    case externalICS
    case localEventKit
    case byokLLM

    public var displayName: String {
        switch self {
        case .builtin: return "Built-in"
        case .externalICS: return "Subscription"
        case .localEventKit: return "iOS Calendar"
        case .byokLLM: return "AI"
        }
    }
}

public struct HolidayCalendarEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(date)-\(kind.rawValue)-\(source.rawValue)-\(title)" }
    /// Date in `YYYY-MM-DD` format.
    public var date: String
    public var title: String
    public var kind: HolidayEntryKind
    public var source: HolidayEntrySource
    public var note: String

    public init(
        date: String,
        title: String,
        kind: HolidayEntryKind,
        source: HolidayEntrySource,
        note: String = ""
    ) {
        self.date = date
        self.title = title
        self.kind = kind
        self.source = source
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(HolidayEntryKind.self, forKey: .kind)
        source = try container.decode(HolidayEntrySource.self, forKey: .source)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - External Calendar Subscription (.ics)

public enum HolidayRegionHint: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case sg = "SG"
    case cn = "CN"
    case custom = "Custom"

    public var displayName: String {
        switch self {
        case .sg: return "Singapore (MOM)"
        case .cn: return "Mainland China (State Council)"
        case .custom: return "Custom iCal (.ics)"
        }
    }
}

public struct ExternalCalendarSubscription: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public var regionHint: HolidayRegionHint
    public var lastSyncedAt: Date?
    public var isEnabled: Bool
    /// Identifier of the `HolidayCatalogItem` this subscription was created from, if any.
    /// Optional so legacy persisted JSON (which lacks the key) still decodes via the
    /// synthesized `decodeIfPresent` path and existing users keep their data.
    public var catalogID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        regionHint: HolidayRegionHint = .custom,
        lastSyncedAt: Date? = nil,
        isEnabled: Bool = true,
        catalogID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.regionHint = regionHint
        self.lastSyncedAt = lastSyncedAt
        self.isEnabled = isEnabled
        self.catalogID = catalogID
    }

    public static let defaultPresets: [ExternalCalendarSubscription] = [
        ExternalCalendarSubscription(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555501")!,
            name: "China Statutory Holidays & Workdays",
            url: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.ics",
            regionHint: .cn,
            isEnabled: true
        ),
        ExternalCalendarSubscription(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555502")!,
            name: "Singapore Public Holidays (MOM)",
            url: "https://www.mom.gov.sg/-/media/mom/documents/employment-practices/public-holidays/public-holidays-sg-2026.ics",
            regionHint: .sg,
            isEnabled: true
        )
    ]
}

// MARK: - Resolved Day Alarm (Today, Tomorrow, and Upcoming Schedule Results)

public enum ResolvedAlarmStatus: Codable, Equatable, Sendable {
    case scheduled
    case delayed(minutes: Int)
    case skippedByHoliday(reason: String)
    case skippedByPersonalLeave(reason: String)
    case skippedManually
    case noAlarm

    public var isRinging: Bool {
        switch self {
        case .scheduled, .delayed:
            return true
        case .skippedByHoliday, .skippedByPersonalLeave, .skippedManually, .noAlarm:
            return false
        }
    }
}

public struct ResolvedDayAlarm: Codable, Identifiable, Equatable, Sendable {
    public var id: String { date }
    /// `YYYY-MM-DD`
    public var date: String
    /// e.g. "Today", "Tomorrow", "In 2 Days", or "Nov 10"
    public var displayLabel: String
    /// e.g. "Sun", "Mon", "Tue"
    public var weekdayText: String
    /// Original configured time (`HH:mm`)
    public var baseTime: String
    /// Actual ringing time (`HH:mm`), or `nil` if skipped / off
    public var effectiveTime: String?
    public var effectiveHour: Int?
    public var effectiveMinute: Int?
    public var status: ResolvedAlarmStatus
    /// Human-readable reason pill for the 2-day dashboard and desktop Widget
    public var reasonBadge: String
    /// Whether this day has an active one-day override applied
    public var hasManualOverride: Bool
    /// Matching holiday/leave entries on this day
    public var matchedEntries: [HolidayCalendarEntry]

    public init(
        date: String,
        displayLabel: String,
        weekdayText: String,
        baseTime: String,
        effectiveTime: String?,
        effectiveHour: Int?,
        effectiveMinute: Int?,
        status: ResolvedAlarmStatus,
        reasonBadge: String,
        hasManualOverride: Bool,
        matchedEntries: [HolidayCalendarEntry] = []
    ) {
        self.date = date
        self.displayLabel = displayLabel
        self.weekdayText = weekdayText
        self.baseTime = baseTime
        self.effectiveTime = effectiveTime
        self.effectiveHour = effectiveHour
        self.effectiveMinute = effectiveMinute
        self.status = status
        self.reasonBadge = reasonBadge
        self.hasManualOverride = hasManualOverride
        self.matchedEntries = matchedEntries
    }
}

// MARK: - Built-in Sample Holidays (2026 SG + CN Statutory Holidays & Makeup Workdays)

public enum BuiltinHolidays {
    public static let entries2026: [HolidayCalendarEntry] = [
        // China 2026 National Day & Mid-Autumn + Makeup Workdays
        HolidayCalendarEntry(date: "2026-09-25", title: "Mid-Autumn Festival", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-01", title: "National Day", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-02", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-03", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-04", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-05", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-06", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-07", title: "National Day Holiday", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-10", title: "National Day Makeup Workday", kind: .makeupWorkday, source: .builtin),
        // Singapore 2026 Deepavali (falls on Sunday Nov 8 -> Monday Nov 9 public holiday)
        HolidayCalendarEntry(date: "2026-11-08", title: "Deepavali", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-11-09", title: "Deepavali Observed", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-12-25", title: "Christmas Day", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2027-01-01", title: "New Year's Day", kind: .publicHoliday, source: .builtin)
    ]
}
