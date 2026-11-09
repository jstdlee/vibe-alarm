import SwiftUI
import UIKit
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
        case "editor-repeat":
            TimeEditorView(viewModel: viewModel, alarmID: viewModel.alarmRows.first?.id ?? UUID(), initialSheet: .repeatDays)
        case "editor":
            TimeEditorView(viewModel: viewModel, alarmID: viewModel.alarmRows.first?.id ?? UUID())
        case "calendar":
            MainTabView(viewModel: viewModel, initialTab: .calendar)
        case "sources":
            MainTabView(viewModel: viewModel, initialTab: .sources)
        case "widgets":
            WidgetGalleryView(viewModel: viewModel)
        case "byok":
            BYOKInputSheet(viewModel: viewModel, preloadPreview: true)
        case "search":
            // A preset query surfaces several countries, including the one the demo view model
            // already subscribes to, so the added state is visible.
            HolidayCatalogSearchSheet(viewModel: viewModel, initialQuery: "si")
        default:
            MainTabView(viewModel: viewModel, initialTab: .alarms)
        }
    }
}

// MARK: - Main Navigation

enum MainAppTab: Hashable, CaseIterable {
    case alarms
    case calendar
    case sources

    var title: String {
        switch self {
        case .alarms: return "Alarms"
        case .calendar: return "Calendar"
        case .sources: return "Sources"
        }
    }

    var symbolName: String {
        switch self {
        case .alarms: return "alarm"
        case .calendar: return "calendar"
        case .sources: return "list.bullet"
        }
    }
}

/// System tab bar. On iOS 26 and later the bar adopts Liquid Glass when this target is built
/// with the current SDK. The deployment target stays iOS 17, so this view uses `TabView`
/// rather than a newer glass API.
struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: MainAppTab

    init(viewModel: AppViewModel, initialTab: MainAppTab = .alarms) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AlarmListView(viewModel: viewModel)
                .tabItem { Label(MainAppTab.alarms.title, systemImage: MainAppTab.alarms.symbolName) }
                .tag(MainAppTab.alarms)

            HolidayCalendarView(viewModel: viewModel)
                .tabItem { Label(MainAppTab.calendar.title, systemImage: MainAppTab.calendar.symbolName) }
                .tag(MainAppTab.calendar)

            SettingsView(viewModel: viewModel)
                .tabItem { Label(MainAppTab.sources.title, systemImage: MainAppTab.sources.symbolName) }
                .tag(MainAppTab.sources)
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
