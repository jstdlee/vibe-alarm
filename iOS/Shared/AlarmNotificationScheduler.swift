import Foundation
import UserNotifications
import VibeAlarmCore

/// Shared local notification scheduler used by both the main App and Widget `AppIntent` actions.
/// Schedules:
/// 1. Pre-bedtime interactive notification (long-press for "Skip Tomorrow", "Delay 30m / 1h", or "Keep Ringing").
/// 2. Multi-burst Time-Sensitive wake-up alarm notifications for Today & Tomorrow.
public enum AlarmNotificationScheduler {
    private static let notificationPrefix = "com.jstdlee.vibealarm.scheduled."
    /// Stable identifier prefix for one-off snooze wake notifications (replaced on each snooze).
    public static let snoozeNotificationPrefix = "vibealarm.snooze."

    /// Registers notification categories. The wake category embeds the current snooze interval in
    /// its action title (e.g. "Snooze 8 min"); because UNNotificationAction titles are fixed once
    /// registered, callers must re-register whenever the snooze value changes.
    public static func registerNotificationCategories(snoozeMinutes: Int = 8) {
        let skipAction = UNNotificationAction(
            identifier: AppConstants.actionSkipTomorrow,
            title: "Skip Tomorrow (Auto-Restores)",
            options: []
        )
        let delay30Action = UNNotificationAction(
            identifier: AppConstants.actionDelay30m,
            title: "Delay 30 Minutes (+30m)",
            options: []
        )
        let delay60Action = UNNotificationAction(
            identifier: AppConstants.actionDelay60m,
            title: "Delay 1 Hour (+1h)",
            options: []
        )
        let restoreAction = UNNotificationAction(
            identifier: AppConstants.actionRestoreTomorrow,
            title: "Restore Original Time",
            options: []
        )
        let keepAction = UNNotificationAction(
            identifier: AppConstants.actionKeepTomorrow,
            title: "Keep Tomorrow's Alarm On",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: AppConstants.actionSnooze,
            title: "Snooze \(AlarmRule.normalizedSnoozeMinutes(snoozeMinutes)) min",
            options: []
        )

        let bedtimeCategory = UNNotificationCategory(
            identifier: AppConstants.bedtimeCategoryIdentifier,
            actions: [skipAction, delay30Action, delay60Action, restoreAction, keepAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let wakeCategory = UNNotificationCategory(
            identifier: AppConstants.wakeAlarmCategoryIdentifier,
            actions: [snoozeAction, delay30Action, restoreAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([bedtimeCategory, wakeCategory])
    }

    public static func syncNotificationsFromStore(referenceDate: Date = Date()) async {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = store.load(referenceDate: referenceDate)
        await syncNotifications(for: snapshot, referenceDate: referenceDate)
    }

    public static func syncNotifications(
        for snapshot: VibeAlarmSnapshot,
        referenceDate: Date = Date()
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
        if !existingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIDs)
        }

        guard snapshot.alarmRule.isEnabled else { return }

        let calendar = AlarmScheduleEngine.defaultCalendar()
        let engine = AlarmScheduleEngine(calendar: calendar)
        let (today, tomorrow) = engine.resolveTwoDayDashboard(
            rule: snapshot.alarmRule,
            entries: snapshot.holidayEntries,
            override: snapshot.nextDayOverride,
            referenceDate: referenceDate
        )

        // 1. Schedule wake-up multi-burst notifications for Today & Tomorrow if still in the future
        for resolved in [today, tomorrow] {
            guard resolved.status.isRinging,
                  let effHour = resolved.effectiveHour,
                  let effMin = resolved.effectiveMinute,
                  let baseDate = engine.date(from: resolved.date) else {
                continue
            }

            var comps = calendar.dateComponents([.year, .month, .day], from: baseDate)
            comps.hour = effHour
            comps.minute = effMin
            comps.second = 0

            guard let fireDate = calendar.date(from: comps), fireDate > referenceDate else {
                continue
            }

            // Schedule 3 rapid wake-up bursts (0s, +20s, +40s) with Time Sensitive interruption level
            for burstIndex in 0..<3 {
                guard let burstDate = calendar.date(byAdding: .second, value: burstIndex * 20, to: fireDate) else {
                    continue
                }
                let burstComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: burstDate)
                let content = UNMutableNotificationContent()
                content.title = "⏰ \(snapshot.alarmRule.label) · \(resolved.effectiveTime ?? resolved.baseTime)"
                content.subtitle = "\(resolved.displayLabel) (\(resolved.weekdayText)) · \(resolved.reasonBadge)"
                content.body = "Long-press this notification to delay by 30 minutes. Tomorrow's schedule restores automatically."
                content.sound = .defaultCritical
                content.categoryIdentifier = AppConstants.wakeAlarmCategoryIdentifier
                content.interruptionLevel = .timeSensitive

                let trigger = UNCalendarNotificationTrigger(dateMatching: burstComps, repeats: false)
                let reqID = "\(notificationPrefix)wake.\(resolved.date).\(burstIndex)"
                let req = UNNotificationRequest(identifier: reqID, content: content, trigger: trigger)
                try? await center.add(req)
            }
        }

        // 2. Schedule Pre-Bedtime Reminder Notification previewing tomorrow's alarm status
        if snapshot.alarmRule.bedtimeReminderEnabled {
            let bedHour = snapshot.alarmRule.preBedtimeReminderMinutes / 60
            let bedMin = snapshot.alarmRule.preBedtimeReminderMinutes % 60
            var bedComps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            bedComps.hour = bedHour
            bedComps.minute = bedMin
            bedComps.second = 0

            if let bedDate = calendar.date(from: bedComps), bedDate > referenceDate {
                let content = UNMutableNotificationContent()
                if let effTime = tomorrow.effectiveTime, tomorrow.status.isRinging {
                    content.title = "🌙 Bedtime Check · Tomorrow Rings at \(effTime)"
                    content.subtitle = "Tomorrow (\(tomorrow.weekdayText)) · \(tomorrow.reasonBadge)"
                    content.body = "Long-press this notification to Skip Tomorrow or Delay +30m/+1h. The day after restores automatically."
                } else {
                    content.title = "🌙 Bedtime Check · No Alarm Tomorrow (\(tomorrow.reasonBadge))"
                    content.subtitle = "Tomorrow (\(tomorrow.weekdayText)) was skipped from \(tomorrow.baseTime)"
                    content.body = "Sleep in tomorrow! If you need to wake up anyway, long-press to Keep Tomorrow's Alarm On."
                }
                content.sound = .default
                content.categoryIdentifier = AppConstants.bedtimeCategoryIdentifier
                content.interruptionLevel = .timeSensitive

                let trigger = UNCalendarNotificationTrigger(dateMatching: bedComps, repeats: false)
                let reqID = "\(notificationPrefix)bedtime.\(today.date)"
                let req = UNNotificationRequest(identifier: reqID, content: content, trigger: trigger)
                try? await center.add(req)
            }
        }
    }

    /// Schedules a one-off wake notification `rule.snoozeMinutes` minutes after `referenceDate`,
    /// reusing the wake alarm category. Any previously pending snooze is replaced first.
    public static func scheduleSnooze(referenceDate: Date = Date()) async {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = store.load(referenceDate: referenceDate)
        let rule = snapshot.alarmRule
        let calendar = AlarmScheduleEngine.defaultCalendar()
        let engine = AlarmScheduleEngine(calendar: calendar)
        let fireDate = engine.snoozeFireDate(after: referenceDate, rule: rule)

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending.map(\.identifier).filter { $0.hasPrefix(snoozeNotificationPrefix) }
        if !existingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIDs)
        }

        let minutes = AlarmRule.normalizedSnoozeMinutes(rule.snoozeMinutes)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(rule.label) · Snoozed \(minutes) min"
        content.subtitle = "Snooze alarm"
        content.body = "Long-press this notification to delay by 30 minutes."
        content.sound = .defaultCritical
        content.categoryIdentifier = AppConstants.wakeAlarmCategoryIdentifier
        content.interruptionLevel = .timeSensitive

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let reqID = "\(snoozeNotificationPrefix)pending"
        let req = UNNotificationRequest(identifier: reqID, content: content, trigger: trigger)
        try? await center.add(req)
    }
}
