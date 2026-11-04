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
            TimeEditorView(viewModel: viewModel)
        case "calendar":
            MainTabView(viewModel: viewModel, initialTab: .calendar)
        case "settings":
            MainTabView(viewModel: viewModel, initialTab: .settings)
        case "widget":
            WidgetGalleryView(viewModel: viewModel)
        case "byok":
            BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
        case "search":
            // Preset query surfaces several countries including Singapore, which the demo
            // view model subscribes to so a checkmark state is visible.
            HolidayCatalogSearchSheet(viewModel: viewModel, initialQuery: "si")
        case "editor":
            TimeEditorView(viewModel: viewModel)
        default:
            MainTabView(viewModel: viewModel, initialTab: .dashboard)
        }
    }
}

// MARK: - Main Tab Bar Navigation (Light Theme)

enum MainAppTab: Hashable {
    case dashboard
    case calendar
    case settings
}

struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: MainAppTab

    init(viewModel: AppViewModel, initialTab: MainAppTab = .dashboard) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TwoDayDashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Alarm", systemImage: "alarm")
                }
                .tag(MainAppTab.dashboard)

            HolidayCalendarView(viewModel: viewModel)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(MainAppTab.calendar)

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Sources", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(MainAppTab.settings)
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
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
        let snapshot = SharedAlarmStore(appGroupID: AppConstants.appGroupID).load()
        AlarmNotificationScheduler.registerNotificationCategories(snoozeMinutes: snapshot.alarmRule.snoozeMinutes)
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
        case AppConstants.actionSnooze:
            await AlarmNotificationScheduler.scheduleSnooze()
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
