import Foundation

public struct AlarmScheduleEngine: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = Self.defaultCalendar()) {
        self.calendar = calendar
    }

    public static func defaultCalendar(timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday
        return cal
    }

    // MARK: - Date Formatting Helpers

    public func dateString(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let y = components.year ?? 2026
        let m = components.month ?? 1
        let d = components.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public func date(from dateString: String) -> Date? {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 12
        comps.minute = 0
        return calendar.date(from: comps)
    }

    public func weekday(for date: Date) -> Weekday {
        let raw = calendar.component(.weekday, from: date)
        return Weekday(rawValue: raw) ?? .monday
    }

    // MARK: - Resolve Next N Days (Default: Today + Tomorrow = 2 Days, or 7 Days)

    public func resolveSchedule(
        rule: AlarmRule,
        entries: [HolidayCalendarEntry],
        override: NextDayOverride?,
        referenceDate: Date = Date(),
        daysCount: Int = 7
    ) -> [ResolvedDayAlarm] {
        let startOfRef = calendar.startOfDay(for: referenceDate)
        var results: [ResolvedDayAlarm] = []
        let entriesByDate = Dictionary(grouping: entries, by: \.date)

        for offset in 0..<max(1, daysCount) {
            guard let targetDate = calendar.date(byAdding: .day, value: offset, to: startOfRef) else {
                continue
            }
            let dStr = dateString(from: targetDate)
            let dayEntries = entriesByDate[dStr] ?? []
            let label = relativeLabel(forOffset: offset, date: targetDate)
            let resolved = resolveSingleDay(
                date: targetDate,
                dateString: dStr,
                displayLabel: label,
                rule: rule,
                dayEntries: dayEntries,
                override: override
            )
            results.append(resolved)
        }
        return results
    }

    /// Convenience helper returning strictly Today and Tomorrow.
    public func resolveTwoDayDashboard(
        rule: AlarmRule,
        entries: [HolidayCalendarEntry],
        override: NextDayOverride?,
        referenceDate: Date = Date()
    ) -> (today: ResolvedDayAlarm, tomorrow: ResolvedDayAlarm) {
        let list = resolveSchedule(
            rule: rule,
            entries: entries,
            override: override,
            referenceDate: referenceDate,
            daysCount: 2
        )
        let today = list[0]
        let tomorrow = list.count > 1 ? list[1] : list[0]
        return (today, tomorrow)
    }

    // MARK: - Single Day Resolution Logic

    public func resolveSingleDay(
        date: Date,
        dateString: String,
        displayLabel: String,
        rule: AlarmRule,
        dayEntries: [HolidayCalendarEntry],
        override: NextDayOverride?
    ) -> ResolvedDayAlarm {
        let wday = weekday(for: date)
        let baseTimeStr = rule.formattedBaseTime

        guard rule.isEnabled else {
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortWeekdayName,
                baseTime: baseTimeStr,
                effectiveTime: nil,
                effectiveHour: nil,
                effectiveMinute: nil,
                status: .noAlarm,
                reasonBadge: "Alarm Disabled",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )
        }

        // 1. Check active manual override for this specific targetDate
        if let override, override.isActive(for: dateString) {
            switch override.action {
            case .skipTomorrow:
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedManually,
                    reasonBadge: rule.autoRestoreNextDay ? "Manually Skipped · Auto-Restores Tomorrow" : "Manually Skipped This Time",
                    hasManualOverride: true,
                    matchedEntries: dayEntries
                )
            case .delayTomorrow(let delayMinutes):
                let (newH, newM) = Self.addMinutes(hour: rule.hour, minute: rule.minute, delta: delayMinutes)
                let effStr = String(format: "%02d:%02d", newH, newM)
                let sign = delayMinutes >= 0 ? "+\(delayMinutes)m" : "\(delayMinutes)m"
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: effStr,
                    effectiveHour: newH,
                    effectiveMinute: newM,
                    status: .delayed(minutes: delayMinutes),
                    reasonBadge: rule.autoRestoreNextDay
                        ? "Delayed (\(sign)) · Auto-Restores to \(baseTimeStr)"
                        : "One-Time Delay (\(sign))",
                    hasManualOverride: true,
                    matchedEntries: dayEntries
                )
            case .forceKeepTomorrow:
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: baseTimeStr,
                    effectiveHour: rule.hour,
                    effectiveMinute: rule.minute,
                    status: .scheduled,
                    reasonBadge: "Manually Kept Ringing (Overrides Holiday Skip)",
                    hasManualOverride: true,
                    matchedEntries: dayEntries
                )
            case .none:
                break
            }
        }

        // 2. Check Personal Leave (EventKit / BYOK personal leave) first if enabled
        if rule.skipPersonalLeave,
           let leaveEntry = dayEntries.first(where: { $0.kind == .personalLeave }) {
            let shouldNormallyRing = matchesBaseRepeat(rule: rule, weekday: wday, dateString: dateString, dayEntries: dayEntries)
            if shouldNormallyRing {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByPersonalLeave(reason: leaveEntry.title),
                    reasonBadge: "\(leaveEntry.title) · Auto-Skipped",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
        }

        // 3. Check Public Holiday & Statutory Makeup Workday
        let makeupEntry = dayEntries.first(where: { $0.kind == .makeupWorkday })
        let publicHolidayEntry = dayEntries.first(where: { $0.kind == .publicHoliday })

        switch rule.repeatMode {
        case .weekdays:
            if rule.skipPublicHolidays {
                if let holiday = publicHolidayEntry {
                    return ResolvedDayAlarm(
                        date: dateString,
                        displayLabel: displayLabel,
                        weekdayText: wday.shortWeekdayName,
                        baseTime: baseTimeStr,
                        effectiveTime: nil,
                        effectiveHour: nil,
                        effectiveMinute: nil,
                        status: .skippedByHoliday(reason: holiday.title),
                        reasonBadge: "\(holiday.title) · Holiday Auto-Skip",
                        hasManualOverride: false,
                        matchedEntries: dayEntries
                    )
                }
                if wday.isWeekend {
                    if let makeup = makeupEntry {
                        return ResolvedDayAlarm(
                            date: dateString,
                            displayLabel: displayLabel,
                            weekdayText: wday.shortWeekdayName,
                            baseTime: baseTimeStr,
                            effectiveTime: baseTimeStr,
                            effectiveHour: rule.hour,
                            effectiveMinute: rule.minute,
                            status: .scheduled,
                            reasonBadge: "\(makeup.title) · Makeup Workday Auto-Enabled",
                            hasManualOverride: false,
                            matchedEntries: dayEntries
                        )
                    } else {
                        return ResolvedDayAlarm(
                            date: dateString,
                            displayLabel: displayLabel,
                            weekdayText: wday.shortWeekdayName,
                            baseTime: baseTimeStr,
                            effectiveTime: nil,
                            effectiveHour: nil,
                            effectiveMinute: nil,
                            status: .noAlarm,
                            reasonBadge: "Weekend Rest · No Alarm",
                            hasManualOverride: false,
                            matchedEntries: dayEntries
                        )
                    }
                }
            } else if wday.isWeekend {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "Weekend Rest · No Alarm",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }

            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortWeekdayName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "Workday · Normal Ring",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )

        case .everyday:
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · Holiday Auto-Skip",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortWeekdayName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "Daily Alarm · Normal Ring",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )

        case .weekends:
            guard wday.isWeekend else {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "Weekday · No Alarm",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · Holiday Auto-Skip",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortWeekdayName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "Weekend · Normal Ring",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )

        case .customDays(let days):
            let isMakeup = rule.skipPublicHolidays && makeupEntry != nil
            guard days.contains(wday) || isMakeup else {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "Not a Repeat Day · No Alarm",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · Holiday Auto-Skip",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            let badge = isMakeup ? "\(makeupEntry!.title) · Makeup Workday Auto-Enabled" : "Weekly Schedule · Normal Ring"
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortWeekdayName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: badge,
                hasManualOverride: false,
                matchedEntries: dayEntries
            )

        case .specificDates(let dates):
            guard dates.contains(dateString) else {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "Not a Selected Date · No Alarm",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortWeekdayName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · Holiday Auto-Skip",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortWeekdayName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "Selected Date · Normal Ring",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )
        }
    }

    private func matchesBaseRepeat(
        rule: AlarmRule,
        weekday: Weekday,
        dateString: String,
        dayEntries: [HolidayCalendarEntry]
    ) -> Bool {
        let hasMakeup = rule.skipPublicHolidays && dayEntries.contains(where: { $0.kind == .makeupWorkday })
        switch rule.repeatMode {
        case .weekdays:
            return !weekday.isWeekend || hasMakeup
        case .everyday:
            return true
        case .weekends:
            return weekday.isWeekend
        case .customDays(let days):
            return days.contains(weekday) || hasMakeup
        case .specificDates(let dates):
            return dates.contains(dateString)
        }
    }

    private func relativeLabel(forOffset offset: Int, date: Date) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2: return "In 2 Days"
        default:
            let m = calendar.component(.month, from: date)
            let d = calendar.component(.day, from: date)
            return "\(Self.monthAbbreviation(m)) \(d)"
        }
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func monthAbbreviation(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "" }
        return monthAbbreviations[month - 1]
    }

    /// Pure computation of the next fire date when the user snoozes, adding the rule's
    /// normalized snooze interval (in minutes) to the supplied fire/now date.
    public func snoozeFireDate(after date: Date, rule: AlarmRule) -> Date {
        let minutes = AlarmRule.normalizedSnoozeMinutes(rule.snoozeMinutes)
        return calendar.date(byAdding: .minute, value: minutes, to: date)
            ?? date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public static func addMinutes(hour: Int, minute: Int, delta: Int) -> (hour: Int, minute: Int) {
        let total = ((hour * 60 + minute + delta) % 1440 + 1440) % 1440
        return (total / 60, total % 60)
    }
}
