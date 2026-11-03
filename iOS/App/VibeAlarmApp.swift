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
                .preferredColorScheme(.light)
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
            MainTabView(viewModel: viewModel, initialTab: .dial)
        case "calendar":
            MainTabView(viewModel: viewModel, initialTab: .calendar)
        case "settings":
            MainTabView(viewModel: viewModel, initialTab: .settings)
        case "widget":
            MainTabView(viewModel: viewModel, initialTab: .widget)
        case "byok":
            BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
        default:
            MainTabView(viewModel: viewModel, initialTab: .dashboard)
        }
    }
}

// MARK: - Main Tab Bar Navigation (Light Theme)

enum MainAppTab: Hashable {
    case dashboard
    case dial
    case calendar
    case settings
    case widget
}

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: MainAppTab
    private let showWidgetTab: Bool

    init(viewModel: AppViewModel, initialTab: MainAppTab = .dashboard) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: initialTab)
        self.showWidgetTab = (initialTab == .widget)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TwoDayDashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Alarms", systemImage: "alarm.fill")
                }
                .tag(MainAppTab.dashboard)

            DualThumbTimeDialSheet(viewModel: viewModel, isEmbeddedInTab: true)
                .tabItem {
                    Label("Time Dial", systemImage: "dial.medium.fill")
                }
                .tag(MainAppTab.dial)

            HolidayCalendarView(viewModel: viewModel)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(MainAppTab.calendar)

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Sources", systemImage: "slider.horizontal.3")
                }
                .tag(MainAppTab.settings)

            if showWidgetTab {
                WidgetAndBedtimeShowcaseView(viewModel: viewModel)
                    .tabItem {
                        Label("Widgets", systemImage: "rectangle.grid.2x2.fill")
                    }
                    .tag(MainAppTab.widget)
            }
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }
}

// MARK: - Screen 5: Widget, Bedtime Notification & BYOK AI Showcase (Light Theme)

struct WidgetAndBedtimeShowcaseView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var didSendPreview = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    widgetPreviewCard
                    bedtimeNotificationCard
                    byokParserCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color.vibeCanvas)
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }

    // MARK: 1. SystemMedium Widget Preview

    private var widgetPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(caption: "DESKTOP WIDGET", trailing: "SystemMedium")

            HStack(alignment: .top, spacing: 14) {
                widgetDayColumn(day: viewModel.todayAlarm, isTomorrow: false)
                widgetDayColumn(day: viewModel.tomorrowAlarm, isTomorrow: true)
            }

            HStack(spacing: 8) {
                widgetPillButton(title: "Skip")
                widgetPillButton(title: "+30m")
                widgetPillButton(title: "+1h")
                widgetPillButton(title: "Restore")
            }
        }
        .padding(16)
        .vibeCard()
    }

    private func widgetDayColumn(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isTomorrow ? "TOMORROW" : "TODAY")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(isTomorrow ? Color.vibeAccent : Color.vibeInkMuted)

            Text(day.status.isRinging ? (day.effectiveTime ?? day.baseTime) : "OFF")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(day.status.isRinging ? Color.vibeInk : Color.vibeInkMuted)

            Text(day.reasonBadge)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func widgetPillButton(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.vibeAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.vibeAccent.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: 2. Bedtime Confirmation Notification

    private var bedtimeNotificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(caption: "BEDTIME CONFIRMATION", trailing: viewModel.snapshot.alarmRule.formattedBedtimeReminder)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.tomorrowAlarm.status.isRinging ? "Tomorrow Rings · \(viewModel.tomorrowAlarm.effectiveTime ?? viewModel.tomorrowAlarm.baseTime)" : "No Alarm Tomorrow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(viewModel.tomorrowAlarm.reasonBadge)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                notificationActionPill(title: "Skip Tomorrow") {
                    viewModel.performTomorrowOverride(.skipTomorrow)
                }
                notificationActionPill(title: "Delay +30m") {
                    viewModel.incrementTomorrowDelay(by: 30)
                }
                notificationActionPill(title: "Delay +1h") {
                    viewModel.incrementTomorrowDelay(by: 60)
                }
                notificationActionPill(title: "Keep Ringing") {
                    viewModel.performTomorrowOverride(.forceKeepTomorrow)
                }
            }

            Button {
                Task {
                    await viewModel.sendInstantBedtimePreviewNotification()
                    didSendPreview = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                    Text(didSendPreview ? "Preview Sent" : "Send Live Preview")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.vibeAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .vibeCard()
    }

    private func notificationActionPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(uiColor: .systemGray6))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 3. BYOK AI Parser Summary

    private var byokParserCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader(caption: "ON-DEVICE AI PARSER", trailing: "BYOK")
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.vibeAccent)
                Text("Parses HR notices and leave emails into calendar entries")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .padding(16)
        .vibeCard()
    }

    // MARK: Shared Card Header

    private func cardHeader(caption: String, trailing: String) -> some View {
        HStack {
            Text(caption)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer()
            Text(trailing)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.vibeAccent)
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
