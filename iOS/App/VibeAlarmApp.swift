import SwiftUI
import UIKit
import UserNotifications
import VibeAlarmCore
import WidgetKit

@main
struct VibeAlarmApp: App {
    @UIApplicationDelegateAdaptor(VibeAlarmNotificationDelegate.self) private var notificationDelegate
    @StateObject private var viewModel: AppViewModel
    @StateObject private var appearance: AppearanceStore
    @Environment(\.scenePhase) private var scenePhase
    private let previewScreen: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        let appearance = AppearanceStore()
        if let idx = args.firstIndex(of: "-ui-preview-theme"), idx + 1 < args.count,
           let style = AppearanceStyle(rawValue: args[idx + 1]) {
            appearance.select(style)
        }
        _appearance = StateObject(wrappedValue: appearance)
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
                .modifier(RefreshVibeTokens())
                .environment(\.appearanceStyle, appearance.style)
                .environmentObject(appearance)
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
    @Environment(\.appearanceStyle) private var appearanceStyle
    @Environment(\.vibeTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: MainAppTab

    init(viewModel: AppViewModel, initialTab: MainAppTab = .alarms) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        if appearanceStyle == .bedside {
            bedsideTabs
        } else {
            systemTabs
        }
    }

    private var systemTabs: some View {
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

    private var bedsideTabs: some View {
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
        .background(tokens.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Rectangle().fill(tokens.hairline).frame(height: 0.5)
                HStack(spacing: 0) {
                    ForEach(MainAppTab.allCases, id: \.self) { tab in
                        let selected = tab == selectedTab
                        Button {
                            guard !selected else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(tab.title)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? tokens.ink : tokens.inkSoft)
                                Capsule()
                                    .fill(selected ? tokens.accent : Color.clear)
                                    .frame(width: 18, height: 3)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }
            .background(tokens.paper)
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
