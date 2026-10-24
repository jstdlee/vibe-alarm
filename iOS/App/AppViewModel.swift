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
    private let referenceDateOverride: Date?

    public init(
        store: SharedAlarmStore = SharedAlarmStore(appGroupID: AppConstants.appGroupID),
        referenceDateOverride: Date? = nil
    ) {
        self.store = store
        self.referenceDateOverride = referenceDateOverride
        let refDate = referenceDateOverride ?? Date()
        let loaded = store.load(referenceDate: refDate)
        self.snapshot = loaded
        let (today, tomorrow) = engine.resolveTwoDayDashboard(
            rule: loaded.alarmRule,
            entries: loaded.holidayEntries,
            override: loaded.nextDayOverride,
            referenceDate: refDate
        )
        self.todayAlarm = today
        self.tomorrowAlarm = tomorrow
        self.upcomingWeek = engine.resolveSchedule(
            rule: loaded.alarmRule,
            entries: loaded.holidayEntries,
            override: loaded.nextDayOverride,
            referenceDate: refDate,
            daysCount: 7
        )
    }

    /// Creates a pre-seeded demo ViewModel for UI previews and Simulator screenshot capture.
    public static func makeDemoPreview() -> AppViewModel {
        let engine = AlarmScheduleEngine()
        // Reference date: Sunday 2026-11-08 (so Tomorrow is Monday 2026-11-09 Deepavali Observed Holiday)
        // With today (2026-11-08) marked as a statutory makeup workday ("调休补班") to showcase both cases cleanly.
        let refDate = engine.date(from: "2026-11-08") ?? Date()
        var entries = BuiltinHolidays.entries2026
        entries.removeAll { $0.date == "2026-11-08" }
        entries.append(
            HolidayCalendarEntry(
                date: "2026-11-08",
                title: "调休补班",
                kind: .makeupWorkday,
                source: .externalICS
            )
        )
        entries.append(
            HolidayCalendarEntry(
                date: "2026-11-11",
                title: "个人年假",
                kind: .personalLeave,
                source: .localEventKit
            )
        )
        entries.sort { $0.date < $1.date }

        let demoSnapshot = VibeAlarmSnapshot(
            alarmRule: AlarmRule(
                label: "起床",
                hour: 7,
                minute: 30,
                isEnabled: true,
                repeatMode: .weekdays,
                skipPublicHolidays: true,
                skipPersonalLeave: true,
                autoRestoreNextDay: true,
                preBedtimeReminderMinutes: 22 * 60 + 30,
                bedtimeReminderEnabled: true
            ),
            nextDayOverride: nil,
            holidayEntries: entries,
            subscriptions: ExternalCalendarSubscription.defaultPresets
        )
        let vm = AppViewModel(referenceDateOverride: refDate)
        vm.applySnapshot(demoSnapshot, persist: false)
        return vm
    }

    public func reloadFromStore() {
        let refDate = referenceDateOverride ?? Date()
        let loaded = store.load(referenceDate: refDate)
        applySnapshot(loaded, persist: false)
    }

    public func applySnapshot(_ newSnapshot: VibeAlarmSnapshot, persist: Bool = true) {
        let refDate = referenceDateOverride ?? Date()
        var current = newSnapshot
        if persist {
            current = (try? store.save(newSnapshot, referenceDate: refDate)) ?? newSnapshot
        }
        snapshot = current
        let (today, tomorrow) = engine.resolveTwoDayDashboard(
            rule: current.alarmRule,
            entries: current.holidayEntries,
            override: current.nextDayOverride,
            referenceDate: refDate
        )
        todayAlarm = today
        tomorrowAlarm = tomorrow
        upcomingWeek = engine.resolveSchedule(
            rule: current.alarmRule,
            entries: current.holidayEntries,
            override: current.nextDayOverride,
            referenceDate: refDate,
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

    // MARK: - Next-Day One-Tap Quick Actions

    public func performTomorrowOverride(_ action: NextDayOverrideAction) {
        let refDate = referenceDateOverride ?? Date()
        guard let updated = try? store.setTomorrowOverride(action: action, referenceDate: refDate) else { return }
        applySnapshot(updated, persist: false)
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
                showBanner("未获得系统日历读取权限")
                return
            }
        }
        let leaveEntries = localCalendarManager.scanPersonalLeaveEntries(
            selectedCalendarIDs: snapshot.selectedLocalCalendarIDs,
            keywords: snapshot.leaveKeywords
        )
        if let updated = try? store.upsertHolidayEntries(leaveEntries, replacingSource: .localEventKit) {
            applySnapshot(updated, persist: false)
            showBanner("已同步 \(leaveEntries.count) 条日历休假记录")
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
        if successCount > 0 {
            showBanner("已更新 \(successCount) 个订阅日历")
        }
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
                        name: "日历订阅",
                        url: url,
                        regionHint: .custom,
                        isEnabled: true
                    )
                )
            }
        }
        applySnapshot(copy)
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
            content.title = "明日闹钟确认 · \(eff)"
            content.subtitle = "明天 (\(tomorrowAlarm.weekdayText)) · \(tomorrowAlarm.reasonBadge)"
            content.body = "长按此通知可选择「跳过明日闹钟」或「推迟 30 分钟」，后天自动恢复。"
        } else {
            content.title = "明日免响铃 · \(tomorrowAlarm.reasonBadge)"
            content.subtitle = "明天 (\(tomorrowAlarm.weekdayText)) 原定 \(tomorrowAlarm.baseTime)"
            content.body = "长按此通知可选择「恢复响铃」或「推迟 30 分钟」。"
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
    }

    public func showBanner(_ message: String) {
        statusBannerMessage = message
    }
}
