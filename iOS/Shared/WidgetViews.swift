import SwiftUI
import VibeAlarmCore
import WidgetKit

// MARK: - Shared Copy

func widgetTimeText(_ day: ResolvedDayAlarm) -> String {
    if day.status.isRinging {
        return day.effectiveTime ?? day.baseTime
    }
    if day.status == .skippedManually {
        return "Skipped"
    }
    return "Off"
}

func widgetStateLine(_ day: ResolvedDayAlarm) -> String {
    switch day.status {
    case .scheduled:
        return day.matchedEntries.first(where: { $0.kind == .makeupWorkday })?.title ?? "Ringing"
    case .delayed(let minutes):
        return "Delayed \(minutes) min"
    case .skippedByHoliday(let reason):
        return reason
    case .skippedByPersonalLeave(let reason):
        return reason
    case .skippedManually:
        return "Skipped"
    case .noAlarm:
        return "No alarm"
    }
}

/// Actions only make sense while tomorrow will actually ring and has no override yet.
func widgetCanAdjustTomorrow(_ day: ResolvedDayAlarm) -> Bool {
    day.status.isRinging && !day.hasManualOverride
}

// MARK: - Machined Key (Widget-safe)

/// A milled key for interactive widgets. WidgetKit renders `Button(intent:)` labels without
/// custom `ButtonStyle` hit areas, so the volume is drawn as a background of the label itself.
struct WidgetKeyLabel: View {
    let title: String
    let active: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(active ? VibePalette.amber : VibePalette.inkFaint.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? VibePalette.paperRaised : VibePalette.paperDeep.opacity(0.5))
                    .shadow(
                        color: VibePalette.shadow.opacity(active ? 0.14 : 0.0),
                        radius: 2,
                        x: 0,
                        y: active ? 1.5 : 0
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(VibePalette.hairline.opacity(active ? 0.7 : 0.35), lineWidth: 0.5)
            )
    }
}

// MARK: - Small Widget (Tomorrow)

public struct SmallWidgetContentView: View {
    public let tomorrow: ResolvedDayAlarm

    public init(tomorrow: ResolvedDayAlarm) {
        self.tomorrow = tomorrow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tomorrow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VibePalette.inkFaint)

            Spacer(minLength: 4)

            Text(widgetTimeText(tomorrow))
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tomorrow.status.isRinging ? VibePalette.ink : VibePalette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(widgetStateLine(tomorrow))
                .font(.caption)
                .foregroundStyle(VibePalette.inkSoft)
                .lineLimit(1)

            Spacer(minLength: 6)

            if tomorrow.hasManualOverride {
                Button(intent: RestoreTomorrowIntent()) {
                    WidgetKeyLabel(title: "Restore", active: true)
                }
                .buttonStyle(.plain)
            } else if widgetCanAdjustTomorrow(tomorrow) {
                Button(intent: SkipTomorrowIntent()) {
                    WidgetKeyLabel(title: "Skip", active: true)
                }
                .buttonStyle(.plain)
            } else {
                WidgetKeyLabel(title: "Skip", active: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium Widget (Today & Tomorrow + Keys)

public struct MediumWidgetContentView: View {
    public let today: ResolvedDayAlarm
    public let tomorrow: ResolvedDayAlarm

    public init(today: ResolvedDayAlarm, tomorrow: ResolvedDayAlarm) {
        self.today = today
        self.tomorrow = tomorrow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                dayColumn(today, label: "Today")
                Rectangle()
                    .fill(VibePalette.hairline)
                    .frame(width: 0.6)
                dayColumn(tomorrow, label: "Tomorrow")
            }

            HStack(spacing: 7) {
                if widgetCanAdjustTomorrow(tomorrow) {
                    Button(intent: SkipTomorrowIntent()) {
                        WidgetKeyLabel(title: "Skip", active: true)
                    }
                    .buttonStyle(.plain)

                    Button(intent: DelayTomorrow30Intent()) {
                        WidgetKeyLabel(title: "+10 min", active: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    WidgetKeyLabel(title: "Skip", active: false)
                    WidgetKeyLabel(title: "+10 min", active: false)
                }

                if tomorrow.hasManualOverride {
                    Button(intent: RestoreTomorrowIntent()) {
                        WidgetKeyLabel(title: "Restore", active: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    WidgetKeyLabel(title: "Restore", active: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func dayColumn(_ day: ResolvedDayAlarm, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VibePalette.inkFaint)

            Text(widgetTimeText(day))
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(day.status.isRinging ? VibePalette.ink : VibePalette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(widgetStateLine(day))
                .font(.caption)
                .foregroundStyle(VibePalette.inkSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
