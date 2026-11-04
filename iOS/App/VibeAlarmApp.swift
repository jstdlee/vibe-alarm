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
        case .alarms: return "ALARMS"
        case .calendar: return "CALENDAR"
        case .sources: return "SOURCES"
        }
    }
}

/// Three paper tabs and an amber index that slides under the active one. The bar is drawn, not a
/// system material, so it belongs to the same machined surface as everything else.
struct MainTabView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: MainAppTab
    @Namespace private var indexNamespace

    init(viewModel: AppViewModel, initialTab: MainAppTab = .alarms) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .alarms:
                    AlarmListView(viewModel: viewModel)
                case .calendar:
                    HolidayCalendarView(viewModel: viewModel)
                case .sources:
                    SettingsView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(VibePalette.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(MainAppTab.allCases, id: \.self) { tab in
                    tabKey(tab)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
        .background(VibePalette.paper.opacity(0.97))
    }

    private func tabKey(_ tab: MainAppTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 7) {
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .tracking(1.9)
                    .foregroundStyle(isSelected ? VibePalette.ink : VibePalette.inkFaint)
                Group {
                    if isSelected {
                        Capsule()
                            .fill(VibePalette.amber)
                            .frame(width: 18, height: 2.4)
                            .matchedGeometryEffect(id: "tab-index", in: indexNamespace)
                    } else {
                        Color.clear.frame(width: 18, height: 2.4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title.capitalized)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
