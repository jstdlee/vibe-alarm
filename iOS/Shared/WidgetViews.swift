import SwiftUI
import UIKit
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

// MARK: - Widget Key

/// A plain key for interactive widgets. WidgetKit renders `Button(intent:)` labels without
/// a custom `ButtonStyle` hit area, so the fill is drawn on the label itself.
struct WidgetKeyLabel: View {
    let title: String
    let active: Bool
    @Environment(\.vibeTokens) private var tokens
    @Environment(\.appearanceStyle) private var appearanceStyle

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(active ? tokens.ink : tokens.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                appearanceStyle == .bedside
                    ? (active ? tokens.raised : tokens.well)
                    : (active ? Color(.tertiarySystemFill) : Color(.quaternarySystemFill)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

// MARK: - Small Widget (Tomorrow)

public struct SmallWidgetContentView: View {
    public let tomorrow: ResolvedDayAlarm
    @Environment(\.vibeTokens) private var tokens

    public init(tomorrow: ResolvedDayAlarm) {
        self.tomorrow = tomorrow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tomorrow")
                .font(.caption)
                .foregroundStyle(tokens.inkSoft)

            Spacer(minLength: 4)

            Text(widgetTimeText(tomorrow))
                .font(.title.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tomorrow.status.isRinging ? tokens.ink : tokens.inkFaint)
                .fontDesign(tokens.timeDesign)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(widgetStateLine(tomorrow))
                .font(.caption)
                .foregroundStyle(tokens.inkSoft)
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
    @Environment(\.vibeTokens) private var tokens

    public init(today: ResolvedDayAlarm, tomorrow: ResolvedDayAlarm) {
        self.today = today
        self.tomorrow = tomorrow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                dayColumn(today, label: "Today")
                dayColumn(tomorrow, label: "Tomorrow")
            }

            HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(tokens.inkSoft)

            Text(widgetTimeText(day))
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .fontDesign(tokens.timeDesign)
                .foregroundStyle(day.status.isRinging ? tokens.ink : tokens.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(widgetStateLine(day))
                .font(.caption)
                .foregroundStyle(tokens.inkSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
