import SwiftUI
import UserNotifications
import VibeAlarmCore
import WidgetKit

@main
struct VibeAlarmApp: App {
    @UIApplicationDelegateAdaptor(VibeAlarmNotificationDelegate.self) private var notificationDelegate
    @StateObject private var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let previewScreen: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-ui-preview-screen"), idx + 1 < args.count {
            self.previewScreen = args[idx + 1]
            _viewModel = StateObject(wrappedValue: AppViewModel.makeDemoPreview())
        } else {
            self.previewScreen = nil
            _viewModel = StateObject(wrappedValue: AppViewModel())
        }
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .task {
                    notificationDelegate.viewModel = viewModel
                    if previewScreen == nil {
                        await viewModel.requestNotificationPermissionIfNeeded()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && previewScreen == nil {
                        viewModel.reloadFromStore()
                    }
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch previewScreen {
        case "dial":
            DualThumbTimeDialSheet(viewModel: viewModel)
        case "widget":
            WidgetAndBedtimeShowcaseView(viewModel: viewModel)
        case "calendar":
            HolidayCalendarView(viewModel: viewModel)
        case "byok":
            BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
        default:
            TwoDayDashboardView(viewModel: viewModel)
        }
    }
}

// MARK: - Native Showcase View for Interactive Widget & Bedtime Notification Preview

struct WidgetAndBedtimeShowcaseView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            widgetDayColumn(day: viewModel.todayAlarm, isTomorrow: false)
                            Divider()
                                .overlay(Color.white.opacity(0.14))
                                .padding(.horizontal, 6)
                            widgetDayColumn(day: viewModel.tomorrowAlarm, isTomorrow: true)
                        }

                        HStack(spacing: 8) {
                            widgetPillButton(title: "跳过明日")
                            widgetPillButton(title: "推迟 30 分钟")
                            widgetPillButton(title: "恢复原定")
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("桌面交互小组件 (中号 · SystemMedium)")
                        .textCase(nil)
                } footer: {
                    Text("添加至主屏幕后无需打开应用即可直接控制明日闹钟，后天自动恢复原定排期。")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "alarm.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("闹钟 · 睡前提醒")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("22:30")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("明日免响铃 · \(viewModel.tomorrowAlarm.reasonBadge)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        Text("明天 (\(viewModel.tomorrowAlarm.weekdayText)) 原定 \(viewModel.tomorrowAlarm.baseTime)。长按通知可临时更改明日排期。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    notificationActionRow(title: "跳过明日闹钟", systemImage: "bell.slash")
                    notificationActionRow(title: "推迟 30 分钟", systemImage: "plus.circle")
                    notificationActionRow(title: "推迟 1 小时", systemImage: "clock.arrow.circlepath")
                    notificationActionRow(title: "恢复原定时间", systemImage: "arrow.uturn.backward")
                } header: {
                    Text("睡前确认通知 (22:30 长按快捷操作)")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("小组件与睡前通知")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }

    private func widgetDayColumn(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                Text("\(day.displayLabel) · \(day.weekdayText)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isTomorrow ? .orange : .secondary)

            Text(day.effectiveTime ?? day.baseTime)
                .font(.system(size: 34, weight: .light))
                .monospacedDigit()
                .foregroundStyle(day.status.isRinging ? .white : Color(uiColor: .tertiaryLabel))

            Text(day.status.isRinging ? day.reasonBadge : "不响铃 · \(day.reasonBadge)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func widgetPillButton(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(Capsule())
    }

    private func notificationActionRow(title: String, systemImage: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Notification Center Delegate (Handles Long-Press Bedtime & Wake Actions)

final class VibeAlarmNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var viewModel: AppViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AlarmNotificationScheduler.registerNotificationCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        switch response.actionIdentifier {
        case AppConstants.actionSkipTomorrow:
            _ = try? store.setTomorrowOverride(action: .skipTomorrow)
        case AppConstants.actionDelay30m:
            _ = try? store.setTomorrowOverride(action: .delayTomorrow(minutes: 30))
        case AppConstants.actionDelay60m:
            _ = try? store.setTomorrowOverride(action: .delayTomorrow(minutes: 60))
        case AppConstants.actionRestoreTomorrow:
            _ = try? store.setTomorrowOverride(action: .none)
        case AppConstants.actionKeepTomorrow:
            _ = try? store.setTomorrowOverride(action: .forceKeepTomorrow)
        default:
            break
        }

        await AlarmNotificationScheduler.syncNotificationsFromStore()
        WidgetCenter.shared.reloadAllTimelines()

        if let vm = viewModel {
            await MainActor.run {
                vm.reloadFromStore()
            }
        }
    }
}
