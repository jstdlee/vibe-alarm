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

// MARK: - Widget View (Small & Medium — Apple Native Light Clock Aesthetic)

struct VibeAlarmWidgetEntryView: View {
    var entry: VibeAlarmWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            default:
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            Color.white
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                Text("明日 · \(entry.tomorrow.weekdayText)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.orange)

            Spacer(minLength: 0)

            Text(entry.tomorrow.effectiveTime ?? entry.tomorrow.baseTime)
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.tomorrow.status.isRinging ? Color.primary : Color.secondary)

            Text(entry.tomorrow.status.isRinging ? entry.tomorrow.reasonBadge : "不响铃 · \(entry.tomorrow.reasonBadge)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button(intent: SkipTomorrowIntent()) {
                    Text("跳过")
                        .font(.caption2.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                if entry.tomorrow.hasManualOverride {
                    Button(intent: RestoreTomorrowIntent()) {
                        Text("恢复")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else {
                    Button(intent: DelayTomorrow30Intent()) {
                        Text("+30m")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                dayBlock(day: entry.today, isTomorrow: false)
                Divider()
                    .padding(.horizontal, 4)
                dayBlock(day: entry.tomorrow, isTomorrow: true)
            }

            HStack(spacing: 8) {
                Button(intent: SkipTomorrowIntent()) {
                    Text("跳过明日")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(intent: DelayTomorrow30Intent()) {
                    Text("推迟 30 分钟")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(intent: RestoreTomorrowIntent()) {
                    Text("恢复原定")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(entry.tomorrow.hasManualOverride ? Color.orange : Color.secondary)
            }
        }
    }

    private func dayBlock(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "alarm.fill")
                    .font(.caption2)
                Text("\(day.displayLabel) · \(day.weekdayText)")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isTomorrow ? Color.orange : Color.secondary)

            Text(day.effectiveTime ?? day.baseTime)
                .font(.system(size: 32, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(day.status.isRinging ? Color.primary : Color.secondary)

            Text(day.status.isRinging ? day.reasonBadge : "不响铃 · \(day.reasonBadge)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .configurationDisplayName("近两日闹钟")
        .description("查看今明两日闹钟状态，支持在桌面跳过明日、推迟 30 分钟或恢复原定排期。")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}
