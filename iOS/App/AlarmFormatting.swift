import Foundation
import VibeAlarmCore

/// Shared display copy for the alarm screens. Scheduling stays in `VibeAlarmCore`.
enum AlarmFormatting {
    static let weekOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    static func repeatTitle(_ mode: AlarmRepeatMode) -> String {
        switch mode {
        case .weekdays: return "Weekdays"
        case .everyday: return "Every Day"
        case .weekends: return "Weekends"
        case .customDays(let days):
            return days.isEmpty ? "Never" : "Custom"
        case .specificDates: return "Once"
        }
    }

    static func repeatSummary(_ rule: AlarmRule) -> String {
        switch rule.repeatMode {
        case .weekdays: return "Monday to Friday · holiday aware"
        case .everyday: return "Every day"
        case .weekends: return "Saturday and Sunday"
        case .customDays(let days):
            if days.isEmpty { return "No days selected" }
            return weekOrder.filter { days.contains($0) }.map(\.shortWeekdayName).joined(separator: " ")
        case .specificDates(let dates):
            if dates.isEmpty { return "No dates set" }
            return dates.sorted().joined(separator: ", ")
        }
    }

    static func dayStateText(_ day: ResolvedDayAlarm) -> String {
        switch day.status {
        case .delayed(let minutes):
            let time = day.effectiveTime ?? day.baseTime
            return "\(time) · Delayed \(minutes) min"
        case .scheduled:
            return day.effectiveTime ?? day.baseTime
        case .skippedManually:
            return "Skipped"
        case .skippedByHoliday(let reason), .skippedByPersonalLeave(let reason):
            return reason
        case .noAlarm:
            return "Off"
        }
    }

    static func shortReason(_ day: ResolvedDayAlarm) -> String {
        switch day.status {
        case .skippedByHoliday(let reason), .skippedByPersonalLeave(let reason):
            return reason
        case .skippedManually:
            return "Skipped"
        case .noAlarm:
            return "No alarm"
        case .delayed(let minutes):
            return "Delayed \(minutes) min"
        case .scheduled:
            return "Ringing"
        }
    }

    static func activeDays(_ mode: AlarmRepeatMode) -> Set<Weekday> {
        switch mode {
        case .weekdays: return Weekday.standardWeekdays
        case .everyday: return Set(Weekday.allCases)
        case .weekends: return [.saturday, .sunday]
        case .customDays(let days): return days
        case .specificDates: return []
        }
    }
}
