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

    public var shortChineseName: String {
        switch self {
        case .sunday: return "周日"
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        }
    }

    public var compactLabel: String {
        switch self {
        case .sunday: return "日"
        case .monday: return "一"
        case .tuesday: return "二"
        case .wednesday: return "三"
        case .thursday: return "四"
        case .friday: return "五"
        case .saturday: return "六"
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
    /// Custom selected days of the week.
    case customDays(Set<Weekday>)
    /// Specific calendar dates in `YYYY-MM-DD` format.
    case specificDates(Set<String>)

    public var summaryText: String {
        switch self {
        case .weekdays:
            return "工作日 (智能节假日/调休)"
        case .everyday:
            return "每天"
        case .customDays(let days):
            if days == Weekday.standardWeekdays {
                return "周一至周五"
            }
            if days.isEmpty {
                return "单次"
            }
            return days.sorted().map(\.shortChineseName).joined(separator: " ")
        case .specificDates(let dates):
            if dates.isEmpty {
                return "未指定日期"
            }
            let sorted = dates.sorted()
            if sorted.count <= 2 {
                return "指定: " + sorted.joined(separator: ", ")
            }
            return "指定 \(sorted.count) 个日期"
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
    /// When enabled, public holidays skip the alarm and statutory makeup workdays (调休补班) activate it on weekends.
    public var skipPublicHolidays: Bool
    /// When enabled, personal leave events (from local EventKit calendar or BYOK AI calendar) skip the alarm.
    public var skipPersonalLeave: Bool
    /// When enabled, one-click next-day skip/delay overrides automatically expire after tomorrow so the following day restores the normal schedule.
    public var autoRestoreNextDay: Bool
    /// Minutes since midnight (0...1439) for the pre-bedtime reminder notification (e.g. 22 * 60 + 30 = 22:30).
    public var preBedtimeReminderMinutes: Int
    public var bedtimeReminderEnabled: Bool

    public init(
        id: UUID = UUID(),
        label: String = "早起闹钟",
        hour: Int = 7,
        minute: Int = 30,
        isEnabled: Bool = true,
        repeatMode: AlarmRepeatMode = .weekdays,
        skipPublicHolidays: Bool = true,
        skipPersonalLeave: Bool = true,
        autoRestoreNextDay: Bool = true,
        preBedtimeReminderMinutes: Int = 22 * 60 + 30,
        bedtimeReminderEnabled: Bool = true
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

// MARK: - Next-Day Override (一键推迟 / 跳过 / 恢复次日闹钟)

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

public enum HolidayEntryKind: String, Codable, CaseIterable, Sendable {
    /// Statutory public holiday (法定节假日 / 公共假期) -> skips alarm.
    case publicHoliday
    /// Statutory makeup workday on a weekend (调休补班) -> triggers workday alarm.
    case makeupWorkday
    /// Personal vacation / PTO / leave (个人休假 / 年假 / 病假) -> skips alarm.
    case personalLeave

    public var displayTitle: String {
        switch self {
        case .publicHoliday: return "公共假期 (休)"
        case .makeupWorkday: return "调休补班 (班)"
        case .personalLeave: return "个人请假 (休)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .publicHoliday: return "公休"
        case .makeupWorkday: return "补班"
        case .personalLeave: return "请假"
        }
    }
}

public enum HolidayEntrySource: String, Codable, CaseIterable, Sendable {
    case builtin
    case externalICS
    case localEventKit
    case byokLLM

    public var displayName: String {
        switch self {
        case .builtin: return "内置日历"
        case .externalICS: return "外部 ICS 订阅"
        case .localEventKit: return "本地系统日历"
        case .byokLLM: return "BYOK AI 录入"
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

    public init(
        date: String,
        title: String,
        kind: HolidayEntryKind,
        source: HolidayEntrySource
    ) {
        self.date = date
        self.title = title
        self.kind = kind
        self.source = source
    }
}

// MARK: - External Calendar Subscription (.ics)

public enum HolidayRegionHint: String, Codable, CaseIterable, Sendable {
    case sg = "SG"
    case cn = "CN"
    case custom = "Custom"

    public var displayName: String {
        switch self {
        case .sg: return "新加坡 (SG MOM)"
        case .cn: return "中国大陆 (国务院放假调休)"
        case .custom: return "自定义 iCal (.ics)"
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

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        regionHint: HolidayRegionHint = .custom,
        lastSyncedAt: Date? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.regionHint = regionHint
        self.lastSyncedAt = lastSyncedAt
        self.isEnabled = isEnabled
    }

    public static let defaultPresets: [ExternalCalendarSubscription] = [
        ExternalCalendarSubscription(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555501")!,
            name: "中国大陆法定节假日与调休订阅",
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

// MARK: - Resolved Day Alarm (最近两天及未来排期计算结果)

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
    /// e.g. "今天", "明天", "后天", or weekday name
    public var displayLabel: String
    /// e.g. "周六", "周日", "周一"
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
        HolidayCalendarEntry(date: "2026-09-25", title: "中秋节", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-01", title: "国庆节", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-02", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-03", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-04", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-05", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-06", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-07", title: "国庆节假期", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-10-10", title: "国庆节调休补班", kind: .makeupWorkday, source: .builtin),
        // Singapore 2026 Deepavali (falls on Sunday Nov 8 -> Monday Nov 9 public holiday)
        HolidayCalendarEntry(date: "2026-11-08", title: "Deepavali (屠妖节)", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-11-09", title: "Deepavali Observed (屠妖节补休)", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2026-12-25", title: "Christmas Day (圣诞节)", kind: .publicHoliday, source: .builtin),
        HolidayCalendarEntry(date: "2027-01-01", title: "New Year's Day (元旦)", kind: .publicHoliday, source: .builtin)
    ]
}
