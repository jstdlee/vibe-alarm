import AppIntents
import Foundation
import VibeAlarmCore
import WidgetKit

// MARK: - Interactive Widget & Shortcuts Intents (iOS 17+ AppIntents)

public struct SkipTomorrowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Skip Tomorrow's Alarm"
    public static var description = IntentDescription("Skips tomorrow's wake alarm in one tap. The day after tomorrow automatically restores the normal schedule.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .skipTomorrow)
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Tomorrow's alarm has been skipped. It will automatically restore the day after.")
    }
}

public struct DelayTomorrow30Intent: AppIntent {
    public static var title: LocalizedStringResource = "Delay Tomorrow's Alarm 10 Minutes"
    public static var description = IntentDescription("Delays tomorrow's alarm by 10 minutes; each tap adds 10 more. The day after tomorrow automatically restores the original time.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let current = store.load()
        let baseDelay: Int
        if let override = current.nextDayOverride,
           case .delayTomorrow(let existing) = override.action {
            baseDelay = existing + 10
        } else {
            baseDelay = 10
        }
        let snapshot = try store.setTomorrowOverride(action: .delayTomorrow(minutes: baseDelay))
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Tomorrow's alarm has been delayed by \(baseDelay) minutes. It will automatically restore the day after.")
    }
}

public struct DelayTomorrow60Intent: AppIntent {
    public static var title: LocalizedStringResource = "Delay Tomorrow's Alarm 1 Hour"
    public static var description = IntentDescription("Delays tomorrow's alarm by 60 minutes. The day after tomorrow automatically restores the original time.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .delayTomorrow(minutes: 60))
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Tomorrow's alarm has been delayed by 1 hour. It will automatically restore the day after.")
    }
}

public struct RestoreTomorrowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Restore Tomorrow's Alarm"
    public static var description = IntentDescription("Clears any temporary delay or skip on tomorrow's alarm, restoring the smart holiday schedule.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .none)
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Tomorrow's alarm has been restored to its normal schedule.")
    }
}

public struct ForceKeepTomorrowIntent: AppIntent {
    public static var title: LocalizedStringResource = "Keep Tomorrow's Alarm On"
    public static var description = IntentDescription("Keeps tomorrow's alarm ringing at the base time even if it's a holiday or leave day.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = try store.setTomorrowOverride(action: .forceKeepTomorrow)
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Tomorrow's alarm will ring on schedule, regardless of holiday or leave status.")
    }
}

// MARK: - Siri & Shortcuts AppShortcutsProvider

public struct VibeAlarmShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SkipTomorrowIntent(),
            phrases: [
                "Skip tomorrow's alarm with \(.applicationName)",
                "Cancel tomorrow's \(.applicationName) alarm"
            ],
            shortTitle: "Skip Tomorrow",
            systemImageName: "bell.slash.fill"
        )
        AppShortcut(
            intent: DelayTomorrow30Intent(),
            phrases: [
                "Delay tomorrow's alarm half an hour with \(.applicationName)",
                "Make tomorrow's \(.applicationName) alarm 10 minutes later"
            ],
            shortTitle: "Delay +10m",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: DelayTomorrow60Intent(),
            phrases: [
                "Delay tomorrow's alarm one hour with \(.applicationName)"
            ],
            shortTitle: "Delay +1h",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: RestoreTomorrowIntent(),
            phrases: [
                "Restore tomorrow's \(.applicationName) alarm",
                "Reset tomorrow's alarm with \(.applicationName)"
            ],
            shortTitle: "Restore Tomorrow",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
    }
}
