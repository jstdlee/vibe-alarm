import AppIntents
import SwiftUI
import VibeAlarmCore
import WidgetKit

// MARK: - Timeline Entry

struct VibeAlarmWidgetEntry: TimelineEntry {
    let date: Date
    let alarmLabel: String
    let today: ResolvedDayAlarm
    let tomorrow: ResolvedDayAlarm
}

// MARK: - Timeline Provider

struct VibeAlarmTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VibeAlarmWidgetEntry {
        makeEntry(for: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (VibeAlarmWidgetEntry) -> Void) {
        completion(makeEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VibeAlarmWidgetEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(for: now)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(for date: Date) -> VibeAlarmWidgetEntry {
        let store = SharedAlarmStore(appGroupID: AppConstants.appGroupID)
        let snapshot = store.load(referenceDate: date)
        let engine = AlarmScheduleEngine()
        let (today, tomorrow) = engine.resolveTwoDayDashboard(
            rule: snapshot.alarmRule,
            entries: snapshot.holidayEntries,
            override: snapshot.nextDayOverride,
            referenceDate: date
        )
        return VibeAlarmWidgetEntry(
            date: date,
            alarmLabel: snapshot.alarmRule.label,
            today: today,
            tomorrow: tomorrow
        )
    }
}

// MARK: - Widget View (Small & Medium)

struct VibeAlarmWidgetEntryView: View {
    var entry: VibeAlarmWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetContentView(tomorrow: entry.tomorrow)
            default:
                MediumWidgetContentView(today: entry.today, tomorrow: entry.tomorrow)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

// MARK: - Widget Bundle

@main
struct VibeAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        VibeAlarmTwoDayWidget()
    }
}

struct VibeAlarmTwoDayWidget: Widget {
    let kind: String = AppConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VibeAlarmTimelineProvider()) { entry in
            VibeAlarmWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Two-Day Alarm")
        .description("See today and tomorrow's alarm at a glance. Skip, delay, or restore tomorrow right from the Home Screen.")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}
