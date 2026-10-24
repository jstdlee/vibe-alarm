import Foundation
import VibeAlarmCore

public enum AppConstants {
    public static var appGroupID: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "VibeAlarmAppGroup") as? String,
           !configured.isEmpty {
            return configured
        }
        return SharedAlarmStore.defaultAppGroupID
    }

    public static var keychainService: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "VibeAlarmKeychainGroup") as? String,
           !configured.isEmpty {
            return configured
        }
        return "com.jstdlee.vibealarm.byok"
    }

    public static let widgetKind = "VibeAlarmTwoDayWidget"
    public static let bedtimeCategoryIdentifier = "VIBE_BEDTIME_REMINDER_CATEGORY"
    public static let wakeAlarmCategoryIdentifier = "VIBE_WAKE_ALARM_CATEGORY"

    public static let actionSkipTomorrow = "VIBE_ACTION_SKIP_TOMORROW"
    public static let actionDelay30m = "VIBE_ACTION_DELAY_30M"
    public static let actionDelay60m = "VIBE_ACTION_DELAY_60M"
    public static let actionRestoreTomorrow = "VIBE_ACTION_RESTORE_TOMORROW"
    public static let actionKeepTomorrow = "VIBE_ACTION_KEEP_TOMORROW"
}
