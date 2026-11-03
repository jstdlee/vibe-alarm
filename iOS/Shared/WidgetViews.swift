import SwiftUI
import VibeAlarmCore
import WidgetKit

/// Pure SwiftUI widget content, shared by the Widget extension and the in-app
/// widget gallery preview screen so both render identical visuals.

func widgetTimeOrStatusText(_ day: ResolvedDayAlarm) -> String {
    if day.status.isRinging {
        return day.effectiveTime ?? day.baseTime
    }
    if day.status == .skippedManually {
        return "Skipped"
    }
    return "Off"
}

func widgetShortReason(_ day: ResolvedDayAlarm) -> String? {
    switch day.status {
    case .scheduled:
        return day.matchedEntries.first(where: { $0.kind == .makeupWorkday })?.title
    case .delayed(let minutes):
        return "Delayed \(minutes) min"
    case .skippedByHoliday(let reason):
        return reason
    case .skippedByPersonalLeave(let reason):
        return reason
    case .skippedManually:
        return "Manually skipped"
    case .noAlarm:
        return nil
    }
}

// MARK: - Small Widget (Tomorrow Only)

/// Skip and delay only make sense when tomorrow will actually ring and has no override yet.
func widgetCanAdjustTomorrow(_ day: ResolvedDayAlarm) -> Bool {
    day.status.isRinging && !day.hasManualOverride
}

/// Non-interactive placeholder that matches the bordered button shape, shown when an action does not apply.
struct WidgetInactivePill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.body)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .accessibilityLabel("\(title), unavailable")
    }
}

public struct SmallWidgetContentView: View {
    public let tomorrow: ResolvedDayAlarm

    public init(tomorrow: ResolvedDayAlarm) {
        self.tomorrow = tomorrow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tomorrow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(widgetTimeOrStatusText(tomorrow))
                .font(.system(size: 30, weight: .light))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if let reason = widgetShortReason(tomorrow) {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if tomorrow.hasManualOverride {
                Button(intent: RestoreTomorrowIntent()) {
                    Text("Restore")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.vibeAccent)
            } else if widgetCanAdjustTomorrow(tomorrow) {
                Button(intent: SkipTomorrowIntent()) {
                    Text("Skip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.vibeAccent)
            } else {
                WidgetInactivePill(title: "Skip")
            }
        }
    }
}

// MARK: - Medium Widget (Today & Tomorrow + Actions)

public struct MediumWidgetContentView: View {
    public let today: ResolvedDayAlarm
    public let tomorrow: ResolvedDayAlarm

    public init(today: ResolvedDayAlarm, tomorrow: ResolvedDayAlarm) {
        self.today = today
        self.tomorrow = tomorrow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                dayColumn(today, label: "Today")
                dayColumn(tomorrow, label: "Tomorrow")
            }

            HStack(spacing: 8) {
                if widgetCanAdjustTomorrow(tomorrow) {
                    Button(intent: SkipTomorrowIntent()) {
                        Text("Skip").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.vibeAccent)

                    Button(intent: DelayTomorrow30Intent()) {
                        Text("+30 min").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.vibeAccent)
                } else {
                    WidgetInactivePill(title: "Skip")
                    WidgetInactivePill(title: "+30 min")
                }

                if tomorrow.hasManualOverride {
                    Button(intent: RestoreTomorrowIntent()) {
                        Text("Restore").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.vibeAccent)
                } else {
                    WidgetInactivePill(title: "Restore")
                }
            }
        }
    }

    private func dayColumn(_ day: ResolvedDayAlarm, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(widgetTimeOrStatusText(day))
                .font(.system(size: 26, weight: .light))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if let reason = widgetShortReason(day) {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
