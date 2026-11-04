import Foundation

// MARK: - Complete Persisted Snapshot Shared by App & Widget Extension

public struct VibeAlarmSnapshot: Codable, Equatable, Sendable {
    /// Every configured alarm. The product is a small list, not a single rule: a work alarm
    /// and a weekend alarm rarely share a time, and the home screen presents them as rows.
    public var alarmRules: [AlarmRule]
    public var nextDayOverride: NextDayOverride?
    public var holidayEntries: [HolidayCalendarEntry]
    public var subscriptions: [ExternalCalendarSubscription]
    public var selectedLocalCalendarIDs: [String]
    public var leaveKeywords: [String]
    public var byokConfig: BYOKConfiguration
    public var updatedAt: Date

    public init(
        alarmRules: [AlarmRule] = [AlarmRule()],
        nextDayOverride: NextDayOverride? = nil,
        holidayEntries: [HolidayCalendarEntry] = BuiltinHolidays.entries2026,
        subscriptions: [ExternalCalendarSubscription] = ExternalCalendarSubscription.defaultPresets,
        selectedLocalCalendarIDs: [String] = [],
        leaveKeywords: [String] = Self.defaultLeaveKeywords,
        byokConfig: BYOKConfiguration = BYOKConfiguration(),
        updatedAt: Date = Date()
    ) {
        self.alarmRules = alarmRules.isEmpty ? [AlarmRule()] : alarmRules
        self.nextDayOverride = nextDayOverride
        self.holidayEntries = holidayEntries
        self.subscriptions = subscriptions
        self.selectedLocalCalendarIDs = selectedLocalCalendarIDs
        self.leaveKeywords = leaveKeywords
        self.byokConfig = byokConfig
        self.updatedAt = updatedAt
    }

    /// The alarm the widget, the notification scheduler and the Siri intents speak about.
    /// It is the first enabled alarm, so a switched-off first row never silences the rest.
    public var alarmRule: AlarmRule {
        get { alarmRules.first(where: \.isEnabled) ?? alarmRules.first ?? AlarmRule() }
        set {
            if let index = alarmRules.firstIndex(where: { $0.id == newValue.id }) {
                alarmRules[index] = newValue
            } else if alarmRules.isEmpty {
                alarmRules = [newValue]
            } else {
                alarmRules[0] = newValue
            }
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case alarmRules
        case alarmRule
        case nextDayOverride
        case holidayEntries
        case subscriptions
        case selectedLocalCalendarIDs
        case leaveKeywords
        case byokConfig
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Snapshots written before alarms became a list only carry a single rule.
        if let rules = try container.decodeIfPresent([AlarmRule].self, forKey: .alarmRules) {
            alarmRules = rules.isEmpty ? [AlarmRule()] : rules
        } else if let single = try container.decodeIfPresent(AlarmRule.self, forKey: .alarmRule) {
            alarmRules = [single]
        } else {
            alarmRules = [AlarmRule()]
        }
        nextDayOverride = try container.decodeIfPresent(NextDayOverride.self, forKey: .nextDayOverride)
        holidayEntries = try container.decodeIfPresent([HolidayCalendarEntry].self, forKey: .holidayEntries) ?? BuiltinHolidays.entries2026
        subscriptions = try container.decodeIfPresent([ExternalCalendarSubscription].self, forKey: .subscriptions) ?? ExternalCalendarSubscription.defaultPresets
        selectedLocalCalendarIDs = try container.decodeIfPresent([String].self, forKey: .selectedLocalCalendarIDs) ?? []
        leaveKeywords = try container.decodeIfPresent([String].self, forKey: .leaveKeywords) ?? Self.defaultLeaveKeywords
        byokConfig = try container.decodeIfPresent(BYOKConfiguration.self, forKey: .byokConfig) ?? BYOKConfiguration()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alarmRules, forKey: .alarmRules)
        try container.encodeIfPresent(nextDayOverride, forKey: .nextDayOverride)
        try container.encode(holidayEntries, forKey: .holidayEntries)
        try container.encode(subscriptions, forKey: .subscriptions)
        try container.encode(selectedLocalCalendarIDs, forKey: .selectedLocalCalendarIDs)
        try container.encode(leaveKeywords, forKey: .leaveKeywords)
        try container.encode(byokConfig, forKey: .byokConfig)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public static let defaultLeaveKeywords: [String] = [
        "PTO", "Leave", "Vacation", "Annual Leave", "Day Off", "Sick Leave"
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

        // Automatically expire stale NextDayOverride if targetDate < today
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
    public func updateAlarm(id: UUID, _ transform: (inout AlarmRule) -> Void) throws -> VibeAlarmSnapshot {
        try mutate { snapshot in
            if let index = snapshot.alarmRules.firstIndex(where: { $0.id == id }) {
                transform(&snapshot.alarmRules[index])
            }
        }
    }

    @discardableResult
    public func setAlarmEnabled(id: UUID, isEnabled: Bool) throws -> VibeAlarmSnapshot {
        try updateAlarm(id: id) { $0.isEnabled = isEnabled }
    }

    @discardableResult
    public func addAlarm(_ alarm: AlarmRule) throws -> VibeAlarmSnapshot {
        try mutate { snapshot in
            snapshot.alarmRules.append(alarm)
        }
    }

    @discardableResult
    public func removeAlarm(id: UUID) throws -> VibeAlarmSnapshot {
        try mutate { snapshot in
            snapshot.alarmRules.removeAll { $0.id == id }
            if snapshot.alarmRules.isEmpty {
                snapshot.alarmRules = [AlarmRule(isEnabled: false)]
            }
        }
    }

    @discardableResult
    public func setSnoozeMinutes(_ minutes: Int) throws -> VibeAlarmSnapshot {
        try mutate { snapshot in
            let normalized = AlarmRule.normalizedSnoozeMinutes(minutes)
            for index in snapshot.alarmRules.indices {
                snapshot.alarmRules[index].snoozeMinutes = normalized
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
