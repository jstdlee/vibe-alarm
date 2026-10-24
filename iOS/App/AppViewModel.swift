import Foundation
import SwiftUI
import UserNotifications
import VibeAlarmCore
import WidgetKit

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var snapshot: VibeAlarmSnapshot
    @Published public private(set) var todayAlarm: ResolvedDayAlarm
    @Published public private(set) var tomorrowAlarm: ResolvedDayAlarm
    @Published public private(set) var upcomingWeek: [ResolvedDayAlarm] = []
    @Published public var statusBannerMessage: String?
    @Published public var isSyncingICS: Bool = false

    public let store: SharedAlarmStore
    public let localCalendarManager = LocalCalendarManager()
    private let engine = AlarmScheduleEngine()

    public init(store: SharedAlarmStore = SharedAlarmStore(appGroupID: AppConstants.appGroupID)) {
        self.store = store
        let loaded = store.load()
        self.snapshot = loaded
        let (today, tomorrow) = engine.resolveTwoDayDashboard(
            rule: loaded.alarmRule,
            entries: loaded.holidayEntries,
            override: loaded.nextDayOverride
        )
        self.todayAlarm = today
        self.tomorrowAlarm = tomorrow
        self.upcomingWeek = engine.resolveSchedule(
            rule: loaded.alarmRule,
            entries: loaded.holidayEntries,
            override: loaded.nextDayOverride,
            daysCount: 7
        )
    }

    public func reloadFromStore() {
        let loaded = store.load()
        applySnapshot(loaded, persist: false)
    }

    public func applySnapshot(_ newSnapshot: VibeAlarmSnapshot, persist: Bool = true) {
        var current = newSnapshot
        if persist {
            current = (try? store.save(newSnapshot)) ?? newSnapshot
        }
        snapshot = current
        let (today, tomorrow) = engine.resolveTwoDayDashboard(
            rule: current.alarmRule,
            entries: current.holidayEntries,
            override: current.nextDayOverride
        )
        todayAlarm = today
        tomorrowAlarm = tomorrow
        upcomingWeek = engine.resolveSchedule(
            rule: current.alarmRule,
            entries: current.holidayEntries,
            override: current.nextDayOverride,
            daysCount: 7
        )

        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await AlarmNotificationScheduler.syncNotifications(for: current)
        }
    }

    // MARK: - Alarm Time & Rule Mutations

    public func updateAlarmTime(hour: Int, minute: Int) {
        var copy = snapshot
        copy.alarmRule.hour = max(0, min(23, hour))
        copy.alarmRule.minute = max(0, min(59, minute))
        applySnapshot(copy)
    }

    public func updateAlarmRule(_ transform: (inout AlarmRule) -> Void) {
        var copy = snapshot
        transform(&copy.alarmRule)
        applySnapshot(copy)
    }

    // MARK: - Next-Day One-Tap Quick Actions (跳过明日 / 推迟 / 一键恢复 / 强制保持)

    public func performTomorrowOverride(_ action: NextDayOverrideAction) {
        guard let updated = try? store.setTomorrowOverride(action: action) else { return }
        applySnapshot(updated, persist: false)
        switch action {
        case .skipTomorrow:
            showBanner("已跳过明日闹钟，后天自动恢复原定排期")
        case .delayTomorrow(let minutes):
            showBanner("明日闹钟已推迟 \(minutes) 分钟，后天自动恢复")
        case .forceKeepTomorrow:
            showBanner("已锁定明日正常响铃（忽略节假日跳过）")
        case .none:
            showBanner("已恢复明日智能排期")
        }
    }

    public func incrementTomorrowDelay(by deltaMinutes: Int) {
        let currentDelay: Int
        if let override = snapshot.nextDayOverride,
           case .delayTomorrow(let existing) = override.action {
            currentDelay = existing + deltaMinutes
        } else {
            currentDelay = deltaMinutes
        }
        performTomorrowOverride(.delayTomorrow(minutes: currentDelay))
    }

    // MARK: - Local EventKit Calendar Sync

    public func syncLocalCalendars() async {
        if !localCalendarManager.hasReadAccess {
            let granted = await localCalendarManager.requestAccess()
            if !granted {
                showBanner("未获得系统日历读取权限，可在系统设置中开启")
                return
            }
        }
        let leaveEntries = localCalendarManager.scanPersonalLeaveEntries(
            selectedCalendarIDs: snapshot.selectedLocalCalendarIDs,
            keywords: snapshot.leaveKeywords
        )
        if let updated = try? store.upsertHolidayEntries(leaveEntries, replacingSource: .localEventKit) {
            applySnapshot(updated, persist: false)
            showBanner("已从本地日历同步 \(leaveEntries.count) 条个人休假/调休记录")
        }
    }

    // MARK: - External ICS Subscription Sync

    public func syncExternalSubscriptions() async {
        isSyncingICS = true
        defer { isSyncingICS = false }

        let parser = ICSHolidayParser()
        var collected: [HolidayCalendarEntry] = []
        var updatedSubs = snapshot.subscriptions
        var successCount = 0

        for idx in updatedSubs.indices where updatedSubs[idx].isEnabled {
            let rawURL = updatedSubs[idx].url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: rawURL) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let text = String(data: data, encoding: .utf8) {
                    let parsed = parser.parse(icsContent: text, source: .externalICS)
                    collected.append(contentsOf: parsed)
                    updatedSubs[idx].lastSyncedAt = Date()
                    successCount += 1
                }
            } catch {
                continue
            }
        }

        var copy = snapshot
        copy.subscriptions = updatedSubs
        if !collected.isEmpty {
            copy.holidayEntries.removeAll { $0.source == .externalICS }
            copy.holidayEntries.append(contentsOf: collected)
            copy.holidayEntries.sort { $0.date < $1.date }
        }
        applySnapshot(copy)
        showBanner(
            successCount > 0
                ? "已同步 \(successCount) 个外部日历订阅 (\(collected.count) 条节假日/调休)"
                : "外部订阅同步完成（离线状态下继续使用内置与已缓存节假日）"
        )
    }

    // MARK: - Holiday Entries & Subscriptions Management

    public func mergeExtractedEntries(_ entries: [HolidayCalendarEntry], discoveredURLs: [String]) {
        var copy = snapshot
        for entry in entries {
            copy.holidayEntries.removeAll { $0.date == entry.date && $0.title == entry.title }
            copy.holidayEntries.append(entry)
        }
        copy.holidayEntries.sort { $0.date < $1.date }

        for url in discoveredURLs {
            if !copy.subscriptions.contains(where: { $0.url.caseInsensitiveCompare(url) == .orderedSame }) {
                copy.subscriptions.append(
                    ExternalCalendarSubscription(
                        name: "从通知提取的日历订阅",
                        url: url,
                        regionHint: .custom,
                        isEnabled: true
                    )
                )
            }
        }
        applySnapshot(copy)
        showBanner("已写入 \(entries.count) 条假期/调休记录")
    }

    public func deleteHolidayEntry(_ entry: HolidayCalendarEntry) {
        var copy = snapshot
        copy.holidayEntries.removeAll { $0.id == entry.id }
        applySnapshot(copy)
    }

    public func addManualHolidayEntry(date: String, title: String, kind: HolidayEntryKind) {
        let entry = HolidayCalendarEntry(date: date, title: title, kind: kind, source: .builtin)
        mergeExtractedEntries([entry], discoveredURLs: [])
    }

    public func addSubscription(name: String, url: String, region: HolidayRegionHint) {
        var copy = snapshot
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "webcal://", with: "https://")
        copy.subscriptions.append(
            ExternalCalendarSubscription(name: name, url: cleanURL, regionHint: region, isEnabled: true)
        )
        applySnapshot(copy)
    }

    public func removeSubscription(id: UUID) {
        var copy = snapshot
        copy.subscriptions.removeAll { $0.id == id }
        applySnapshot(copy)
    }

    // MARK: - Notification Permission & Test Trigger

    public func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        AlarmNotificationScheduler.registerNotificationCategories()
        await AlarmNotificationScheduler.syncNotifications(for: snapshot)
    }

    public func sendInstantBedtimePreviewNotification() async {
        await requestNotificationPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        if let eff = tomorrowAlarm.effectiveTime, tomorrowAlarm.status.isRinging {
            content.title = "🌙 睡前提醒预览：明天 \(eff) 响铃"
            content.subtitle = "明天 (\(tomorrowAlarm.weekdayText)) · \(tomorrowAlarm.reasonBadge)"
            content.body = "长按此通知即可直接选择「跳过明日闹钟」或「推迟 30m / 1h」，后天自动恢复！"
        } else {
            content.title = "🌙 睡前提醒预览：明天免响铃 (\(tomorrowAlarm.reasonBadge))"
            content.subtitle = "明天 (\(tomorrowAlarm.weekdayText)) 原定 \(tomorrowAlarm.baseTime)"
            content.body = "长按此通知可测试「强制保持明日响铃」或「恢复原定时间」。"
        }
        content.sound = .default
        content.categoryIdentifier = AppConstants.bedtimeCategoryIdentifier
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let req = UNNotificationRequest(
            identifier: "com.jstdlee.vibealarm.preview.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(req)
        showBanner("将在 2 秒后弹出可交互睡前提醒通知（可长按操作）")
    }

    public func showBanner(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            statusBannerMessage = message
        }
    }
}
