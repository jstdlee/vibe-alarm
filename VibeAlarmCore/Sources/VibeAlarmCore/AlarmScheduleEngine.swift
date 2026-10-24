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

    /// Convenience helper returning strictly Today and Tomorrow (最近两天闹钟).
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
                weekdayText: wday.shortChineseName,
                baseTime: baseTimeStr,
                effectiveTime: nil,
                effectiveHour: nil,
                effectiveMinute: nil,
                status: .noAlarm,
                reasonBadge: "闹钟总开关已关闭",
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
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedManually,
                    reasonBadge: rule.autoRestoreNextDay ? "已手动跳过 · 次日自动恢复" : "已手动跳过本次闹钟",
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
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: effStr,
                    effectiveHour: newH,
                    effectiveMinute: newM,
                    status: .delayed(minutes: delayMinutes),
                    reasonBadge: rule.autoRestoreNextDay
                        ? "已推迟 (\(sign)) · 次日自动恢复 \(baseTimeStr)"
                        : "单次推迟 (\(sign))",
                    hasManualOverride: true,
                    matchedEntries: dayEntries
                )
            case .forceKeepTomorrow:
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: baseTimeStr,
                    effectiveHour: rule.hour,
                    effectiveMinute: rule.minute,
                    status: .scheduled,
                    reasonBadge: "手动保持响铃 (忽略假期跳过)",
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
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByPersonalLeave(reason: leaveEntry.title),
                    reasonBadge: "\(leaveEntry.title) · 自动跳过",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
        }

        // 3. Check Public Holiday & Statutory Makeup Workday (调休补班)
        let makeupEntry = dayEntries.first(where: { $0.kind == .makeupWorkday })
        let publicHolidayEntry = dayEntries.first(where: { $0.kind == .publicHoliday })

        switch rule.repeatMode {
        case .weekdays:
            if rule.skipPublicHolidays {
                if let holiday = publicHolidayEntry {
                    return ResolvedDayAlarm(
                        date: dateString,
                        displayLabel: displayLabel,
                        weekdayText: wday.shortChineseName,
                        baseTime: baseTimeStr,
                        effectiveTime: nil,
                        effectiveHour: nil,
                        effectiveMinute: nil,
                        status: .skippedByHoliday(reason: holiday.title),
                        reasonBadge: "\(holiday.title) · 假期自动跳过",
                        hasManualOverride: false,
                        matchedEntries: dayEntries
                    )
                }
                if wday.isWeekend {
                    if let makeup = makeupEntry {
                        return ResolvedDayAlarm(
                            date: dateString,
                            displayLabel: displayLabel,
                            weekdayText: wday.shortChineseName,
                            baseTime: baseTimeStr,
                            effectiveTime: baseTimeStr,
                            effectiveHour: rule.hour,
                            effectiveMinute: rule.minute,
                            status: .scheduled,
                            reasonBadge: "\(makeup.title) · 调休自动开启",
                            hasManualOverride: false,
                            matchedEntries: dayEntries
                        )
                    } else {
                        return ResolvedDayAlarm(
                            date: dateString,
                            displayLabel: displayLabel,
                            weekdayText: wday.shortChineseName,
                            baseTime: baseTimeStr,
                            effectiveTime: nil,
                            effectiveHour: nil,
                            effectiveMinute: nil,
                            status: .noAlarm,
                            reasonBadge: "周末休息 · 不响铃",
                            hasManualOverride: false,
                            matchedEntries: dayEntries
                        )
                    }
                }
            } else if wday.isWeekend {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "周末休息 · 不响铃",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }

            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortChineseName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "工作日正常响铃",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )

        case .everyday:
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · 假期自动跳过",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortChineseName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "每日闹钟 · 正常响铃",
                hasManualOverride: false,
                matchedEntries: dayEntries
            )

        case .customDays(let days):
            let isMakeup = rule.skipPublicHolidays && makeupEntry != nil
            guard days.contains(wday) || isMakeup else {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "非设定重复日 · 不响铃",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · 假期自动跳过",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            let badge = isMakeup ? "\(makeupEntry!.title) · 调休自动开启" : "按周排期 · 正常响铃"
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortChineseName,
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
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .noAlarm,
                    reasonBadge: "非指定日期 · 不响铃",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            if rule.skipPublicHolidays, let holiday = publicHolidayEntry {
                return ResolvedDayAlarm(
                    date: dateString,
                    displayLabel: displayLabel,
                    weekdayText: wday.shortChineseName,
                    baseTime: baseTimeStr,
                    effectiveTime: nil,
                    effectiveHour: nil,
                    effectiveMinute: nil,
                    status: .skippedByHoliday(reason: holiday.title),
                    reasonBadge: "\(holiday.title) · 假期自动跳过",
                    hasManualOverride: false,
                    matchedEntries: dayEntries
                )
            }
            return ResolvedDayAlarm(
                date: dateString,
                displayLabel: displayLabel,
                weekdayText: wday.shortChineseName,
                baseTime: baseTimeStr,
                effectiveTime: baseTimeStr,
                effectiveHour: rule.hour,
                effectiveMinute: rule.minute,
                status: .scheduled,
                reasonBadge: "指定日期 · 正常响铃",
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
        case .customDays(let days):
            return days.contains(weekday) || hasMakeup
        case .specificDates(let dates):
            return dates.contains(dateString)
        }
    }

    private func relativeLabel(forOffset offset: Int, date: Date) -> String {
        switch offset {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default:
            let m = calendar.component(.month, from: date)
            let d = calendar.component(.day, from: date)
            return "\(m)月\(d)日"
        }
    }

    public static func addMinutes(hour: Int, minute: Int, delta: Int) -> (hour: Int, minute: Int) {
        let total = ((hour * 60 + minute + delta) % 1440 + 1440) % 1440
        return (total / 60, total % 60)
    }
}
