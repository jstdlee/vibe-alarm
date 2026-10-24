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
                smallView
            default:
                mediumView
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.12, green: 0.15, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.tomorrow.status.isRinging ? "alarm.waves.left.and.right.fill" : "moon.zzz.fill")
                    .foregroundStyle(entry.tomorrow.status.isRinging ? .orange : .mint)
                    .font(.caption)
                Text("明日 · \(entry.tomorrow.weekdayText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }

            Text(entry.tomorrow.effectiveTime ?? "休 · 免响")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)

            Text(entry.tomorrow.reasonBadge)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)

            Spacer(minLength: 2)

            HStack(spacing: 6) {
                Button(intent: SkipTomorrowIntent()) {
                    Text("跳过")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.75))

                if entry.tomorrow.hasManualOverride {
                    Button(intent: RestoreTomorrowIntent()) {
                        Text("恢复")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green.opacity(0.8))
                } else {
                    Button(intent: DelayTomorrow30Intent()) {
                        Text("+30m")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange.opacity(0.85))
                }
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Header
            HStack {
                Label("Vibe 假期闹钟 · 最近两天", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(entry.alarmLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

            // Two-Day Cards (Today + Tomorrow)
            HStack(spacing: 10) {
                dayColumn(day: entry.today, isTomorrow: false)
                dayColumn(day: entry.tomorrow, isTomorrow: true)
            }

            // Interactive AppIntent Action Bar
            HStack(spacing: 8) {
                Button(intent: SkipTomorrowIntent()) {
                    Label("跳过明日", systemImage: "bell.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.78))

                Button(intent: DelayTomorrow30Intent()) {
                    Label("推迟 +30m", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange.opacity(0.85))

                Button(intent: RestoreTomorrowIntent()) {
                    Label("恢复原定", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(entry.tomorrow.hasManualOverride ? .green.opacity(0.85) : .gray.opacity(0.45))
            }
        }
    }

    private func dayColumn(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(day.displayLabel) · \(day.weekdayText)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isTomorrow ? .orange : .white.opacity(0.85))
                Spacer()
                Circle()
                    .fill(day.status.isRinging ? Color.green : Color.mint)
                    .frame(width: 6, height: 6)
            }

            if let eff = day.effectiveTime, day.status.isRinging {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(eff)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if eff != day.baseTime {
                        Text(day.baseTime)
                            .font(.system(size: 10))
                            .strikethrough()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("免响铃")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.mint)
                    Text(day.baseTime)
                        .font(.system(size: 10))
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Text(day.reasonBadge)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isTomorrow ? 0.12 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .configurationDisplayName("Vibe 最近两天假期闹钟")
        .description("实时显示今明两天闹钟与节假日状态，桌面一键跳过明日、推迟或恢复闹钟。")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}
