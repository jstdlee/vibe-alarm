import AppIntents
import Foundation
import VibeAlarmCore
import WidgetKit

// MARK: - Interactive Widget & Shortcuts Intents (iOS 17+ AppIntents)

public struct SkipTomorrowIntent: AppIntent {
    public static var title: LocalizedStringResource = "跳过明日闹钟"
    public static var description = IntentDescription("一键跳过明天的早起闹钟，后天自动恢复原定排期。")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .skipTomorrow)
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已跳过明日闹钟，后天将自动恢复正常排期。")
    }
}

public struct DelayTomorrow30Intent: AppIntent {
    public static var title: LocalizedStringResource = "推迟明日闹钟 30 分钟"
    public static var description = IntentDescription("将明天的闹钟推迟 30 分钟，后天自动恢复原定时间。")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let current = store.load()
        let baseDelay: Int
        if let override = current.nextDayOverride,
           case .delayTomorrow(let existing) = override.action {
            baseDelay = existing + 30
        } else {
            baseDelay = 30
        }
        let snapshot = try store.setTomorrowOverride(action: .delayTomorrow(minutes: baseDelay))
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已将明日闹钟推迟 \(baseDelay) 分钟，后天自动恢复。")
    }
}

public struct DelayTomorrow60Intent: AppIntent {
    public static var title: LocalizedStringResource = "推迟明日闹钟 1 小时"
    public static var description = IntentDescription("将明天的闹钟推迟 60 分钟，后天自动恢复原定时间。")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .delayTomorrow(minutes: 60))
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已将明日闹钟推迟 1 小时，后天自动恢复。")
    }
}

public struct RestoreTomorrowIntent: AppIntent {
    public static var title: LocalizedStringResource = "恢复明日原定闹钟"
    public static var description = IntentDescription("清除对明日闹钟的临时推迟或跳过，恢复智能假期排期。")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .none)
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已恢复明日原定闹钟排期。")
    }
}

public struct ForceKeepTomorrowIntent: AppIntent {
    public static var title: LocalizedStringResource = "强制保持明日闹钟"
    public static var description = IntentDescription("即使明天是节假日或请假，也强制按基础时间响铃。")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .forceKeepTomorrow)
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已设置明天强制按时响铃。")
    }
}

// MARK: - Siri & Shortcuts AppShortcutsProvider

public struct VibeAlarmShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SkipTomorrowIntent(),
            phrases: [
                "用 \(.applicationName) 跳过明天闹钟",
                "取消明天的 \(.applicationName)"
            ],
            shortTitle: "跳过明日闹钟",
            systemImageName: "bell.slash.fill"
        )
        AppShortcut(
            intent: DelayTomorrow30Intent(),
            phrases: [
                "用 \(.applicationName) 推迟明天闹钟半小时",
                "明天 \(.applicationName) 晚半小时响"
            ],
            shortTitle: "推迟明日 +30m",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: DelayTomorrow60Intent(),
            phrases: [
                "用 \(.applicationName) 推迟明天闹钟一小时"
            ],
            shortTitle: "推迟明日 +1h",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: RestoreTomorrowIntent(),
            phrases: [
                "恢复明天的 \(.applicationName)",
                "用 \(.applicationName) 恢复次日闹钟"
            ],
            shortTitle: "恢复次日闹钟",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
    }
}
