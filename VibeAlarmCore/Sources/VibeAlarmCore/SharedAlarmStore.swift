import Foundation

// MARK: - Complete Persisted Snapshot Shared by App & Widget Extension

public struct VibeAlarmSnapshot: Codable, Equatable, Sendable {
    public var alarmRule: AlarmRule
    public var nextDayOverride: NextDayOverride?
    public var holidayEntries: [HolidayCalendarEntry]
    public var subscriptions: [ExternalCalendarSubscription]
    public var selectedLocalCalendarIDs: [String]
    public var leaveKeywords: [String]
    public var byokConfig: BYOKConfiguration
    public var updatedAt: Date

    public init(
        alarmRule: AlarmRule = AlarmRule(),
        nextDayOverride: NextDayOverride? = nil,
        holidayEntries: [HolidayCalendarEntry] = BuiltinHolidays.entries2026,
        subscriptions: [ExternalCalendarSubscription] = ExternalCalendarSubscription.defaultPresets,
        selectedLocalCalendarIDs: [String] = [],
        leaveKeywords: [String] = Self.defaultLeaveKeywords,
        byokConfig: BYOKConfiguration = BYOKConfiguration(),
        updatedAt: Date = Date()
    ) {
        self.alarmRule = alarmRule
        self.nextDayOverride = nextDayOverride
        self.holidayEntries = holidayEntries
        self.subscriptions = subscriptions
        self.selectedLocalCalendarIDs = selectedLocalCalendarIDs
        self.leaveKeywords = leaveKeywords
        self.byokConfig = byokConfig
        self.updatedAt = updatedAt
    }

    public static let defaultLeaveKeywords: [String] = [
        "请假", "休假", "年假", "病假", "调休", "PTO", "Leave", "Vacation", "Out of Office", "OOO"
    ]
}

// MARK: - Atomic App Group Store (`group.com.jstdlee.vibealarm`)

public final class SharedAlarmStore: @unchecked Sendable {
    public static let defaultAppGroupID = "group.com.jstdlee.vibealarm"

    private let fileURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public convenience init(appGroupID: String = SharedAlarmStore.defaultAppGroupID) {
        let baseDir: URL
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            baseDir = containerURL
        } else {
            baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let dir = baseDir.appendingPathComponent("VibeAlarmState", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("snapshot.json"))
    }

    public func load(referenceDate: Date = Date(), calendar: Calendar = AlarmScheduleEngine.defaultCalendar()) -> VibeAlarmSnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              var snapshot = try? decoder.decode(VibeAlarmSnapshot.self, from: data) else {
            return VibeAlarmSnapshot()
        }

        // Automatically expire stale NextDayOverride if targetDate < today (一键推迟和恢复次日闹钟)
        if snapshot.alarmRule.autoRestoreNextDay,
           let override = snapshot.nextDayOverride {
            let todayStr = AlarmScheduleEngine(calendar: calendar).dateString(from: referenceDate)
            if override.targetDate < todayStr {
                snapshot.nextDayOverride = nil
            }
        }
        return snapshot
    }

    @discardableResult
    public func save(_ snapshot: VibeAlarmSnapshot) throws -> VibeAlarmSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var copy = snapshot
        copy.updatedAt = Date()
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(copy)
        try data.write(to: fileURL, options: [.atomic])
        return copy
    }

    @discardableResult
    public func mutate(_ transform: (inout VibeAlarmSnapshot) -> Void) throws -> VibeAlarmSnapshot {
        var current = load()
        transform(&current)
        return try save(current)
    }

    // MARK: - Quick Tomorrow Actions (Shared by App, Widget, Shortcuts, Notification Actions)

    @discardableResult
    public func setTomorrowOverride(
        action: NextDayOverrideAction,
        referenceDate: Date = Date(),
        calendar: Calendar = AlarmScheduleEngine.defaultCalendar()
    ) throws -> VibeAlarmSnapshot {
        let engine = AlarmScheduleEngine(calendar: calendar)
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? referenceDate
        let tomorrowStr = engine.dateString(from: tomorrow)

        return try mutate { snapshot in
            if action == .none {
                snapshot.nextDayOverride = nil
            } else {
                snapshot.nextDayOverride = NextDayOverride(
                    action: action,
                    targetDate: tomorrowStr,
                    createdAt: referenceDate
                )
            }
        }
    }

    @discardableResult
    public func upsertHolidayEntries(_ newEntries: [HolidayCalendarEntry], replacingSource sourceToReplace: HolidayEntrySource? = nil) throws -> VibeAlarmSnapshot {
        try mutate { snapshot in
            if let src = sourceToReplace {
                snapshot.holidayEntries.removeAll { $0.source == src }
            }
            for entry in newEntries {
                snapshot.holidayEntries.removeAll { $0.date == entry.date && $0.source == entry.source && $0.title == entry.title }
                snapshot.holidayEntries.append(entry)
            }
            snapshot.holidayEntries.sort { $0.date < $1.date }
        }
    }
}
