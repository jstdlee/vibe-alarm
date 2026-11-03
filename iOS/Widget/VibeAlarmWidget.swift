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

// MARK: - Widget View (Small & Medium — Braun / Apple Light Clock Aesthetic)

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
            Color.vibeCard
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOMORROW · \(entry.tomorrow.weekdayText.uppercased())")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.vibeAccent)

            Spacer(minLength: 0)

            Text(entry.tomorrow.status.isRinging ? (entry.tomorrow.effectiveTime ?? entry.tomorrow.baseTime) : "OFF")
                .font(.system(size: 32, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.tomorrow.status.isRinging ? Color.vibeInk : Color.vibeInkMuted)

            Text(entry.tomorrow.reasonBadge)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button(intent: SkipTomorrowIntent()) {
                    Text("Skip")
                        .font(.caption2.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.vibeAccent)

                if entry.tomorrow.hasManualOverride {
                    Button(intent: RestoreTomorrowIntent()) {
                        Text("Restore")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.vibeAccent)
                } else {
                    Button(intent: DelayTomorrow30Intent()) {
                        Text("+30m")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.vibeAccent)
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
                    Text("Skip")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.vibeAccent)

                Button(intent: DelayTomorrow30Intent()) {
                    Text("+30m")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.vibeAccent)

                Button(intent: DelayTomorrow60Intent()) {
                    Text("+1h")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.vibeAccent)

                Button(intent: RestoreTomorrowIntent()) {
                    Text("Restore")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(entry.tomorrow.hasManualOverride ? Color.vibeAccent : Color.secondary)
            }
        }
    }

    private func dayBlock(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(isTomorrow ? "TOMORROW" : "TODAY") · \(day.weekdayText.uppercased())")
                .font(.system(size: 10, weight: .bold))
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
