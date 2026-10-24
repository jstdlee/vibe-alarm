import Foundation
import UserNotifications
import VibeAlarmCore

/// Shared local notification scheduler used by both the main App and Widget `AppIntent` actions.
/// Schedules:
/// 1. Pre-bedtime interactive notification (长按可直接选择「跳过明日」「推迟 30m」「推迟 1h」「保持响铃」).
/// 2. Multi-burst Time-Sensitive wake-up alarm notifications for Today & Tomorrow.
public enum AlarmNotificationScheduler {
    private static let notificationPrefix = "com.jstdlee.vibealarm.scheduled."

    public static func registerNotificationCategories() {
        let skipAction = UNNotificationAction(
            identifier: AppConstants.actionSkipTomorrow,
            title: "跳过明日闹钟 (次日自动恢复)",
            options: []
        )
        let delay30Action = UNNotificationAction(
            identifier: AppConstants.actionDelay30m,
            title: "推迟 30 分钟 (+30m)",
            options: []
        )
        let delay60Action = UNNotificationAction(
            identifier: AppConstants.actionDelay60m,
            title: "推迟 1 小时 (+1h)",
            options: []
        )
        let restoreAction = UNNotificationAction(
            identifier: AppConstants.actionRestoreTomorrow,
            title: "恢复原定时间",
            options: []
        )
        let keepAction = UNNotificationAction(
            identifier: AppConstants.actionKeepTomorrow,
            title: "强制保持明日响铃",
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
            actions: [delay30Action, restoreAction],
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
                content.body = "长按通知可选择「推迟 30 分钟」。次日排期将自动恢复正常。"
                content.sound = .defaultCritical
                content.categoryIdentifier = AppConstants.wakeAlarmCategoryIdentifier
                content.interruptionLevel = .timeSensitive

                let trigger = UNCalendarNotificationTrigger(dateMatching: burstComps, repeats: false)
                let reqID = "\(notificationPrefix)wake.\(resolved.date).\(burstIndex)"
                let req = UNNotificationRequest(identifier: reqID, content: content, trigger: trigger)
                try? await center.add(req)
            }
        }

        // 2. Schedule Pre-Bedtime Reminder Notification (睡觉前提醒明日闹钟状态)
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
                    content.title = "🌙 睡前闹钟确认：明天 \(effTime) 响铃"
                    content.subtitle = "明天 (\(tomorrow.weekdayText)) · \(tomorrow.reasonBadge)"
                    content.body = "长按此通知可一键「跳过明日闹钟」或「推迟 30m / 1h」，后天将自动恢复原定排期。"
                } else {
                    content.title = "🌙 睡前提醒：明天无需早起 (\(tomorrow.reasonBadge))"
                    content.subtitle = "明天 (\(tomorrow.weekdayText)) 原定 \(tomorrow.baseTime) 已跳过"
                    content.body = "明天可安心睡个懒觉！如需临时早起，长按此通知可选择「强制保持明日响铃」。"
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
}
