import SwiftUI
import VibeAlarmCore

/// Screen 1 ("Alarms"): Braun/Apple Light Theme two-day dashboard.
/// Shows Today & Tomorrow as spacious hero cards, a one-tap action bar for tomorrow,
/// and a compact list of the next 5 days.
public struct TwoDayDashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var showEditAlarmSheet = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    heroCard(day: viewModel.todayAlarm, isTomorrow: false)
                    heroCard(day: viewModel.tomorrowAlarm, isTomorrow: true)
                    tomorrowActionBar
                    upcomingDaysCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .background(Color.vibeCanvas)
            .navigationBarHidden(true)
            .sheet(isPresented: $showEditAlarmSheet) {
                DualThumbTimeDialSheet(viewModel: viewModel)
            }
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VibeAlarm")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Smart Holiday & PTO Wake Schedule")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(viewModel.snapshot.alarmRule.formattedBaseTime) · \(repeatShortLabel)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .systemGray6))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private var repeatShortLabel: String {
        switch viewModel.snapshot.alarmRule.repeatMode {
        case .weekdays: return "Workdays"
        case .everyday: return "Every Day"
        case .customDays: return "Custom"
        case .specificDates: return "Dates"
        }
    }

    // MARK: - Hero Card (Today / Tomorrow)

    @ViewBuilder
    private func heroCard(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(isTomorrow ? "TOMORROW" : "TODAY") · \(dateCaption(for: day))")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                statusCapsule(for: day)
            }

            timeReadout(for: day)

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(for: day))
                    .frame(width: 7, height: 7)
                Text(day.reasonBadge)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .vibeCard()
        .contentShape(Rectangle())
        .onTapGesture {
            showEditAlarmSheet = true
        }
    }

    @ViewBuilder
    private func timeReadout(for day: ResolvedDayAlarm) -> some View {
        if day.status.isRinging {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(day.effectiveTime ?? day.baseTime)
                    .font(.system(size: 52, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let eff = day.effectiveTime, eff != day.baseTime {
                    Text(day.baseTime)
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("OFF")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.vibePTO)
                Text(day.baseTime)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusCapsule(for day: ResolvedDayAlarm) -> some View {
        Text(statusWord(for: day))
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(statusColor(for: day).opacity(0.14))
            .foregroundStyle(statusColor(for: day))
            .clipShape(Capsule())
    }

    private func statusWord(for day: ResolvedDayAlarm) -> String {
        switch day.status {
        case .scheduled: return "RINGING"
        case .delayed: return "DELAYED"
        case .skippedByHoliday, .skippedByPersonalLeave, .skippedManually, .noAlarm: return "SKIPPED"
        }
    }

    private func statusColor(for day: ResolvedDayAlarm) -> Color {
        switch day.status {
        case .scheduled: return .vibeAccent
        case .delayed: return .vibeWork
        case .skippedByHoliday, .skippedByPersonalLeave, .skippedManually, .noAlarm: return .vibePTO
        }
    }

    private func dateCaption(for day: ResolvedDayAlarm) -> String {
        "\(day.weekdayText.uppercased()) \(Self.monthDayCaption(day.date))"
    }

    // MARK: - Tomorrow One-Tap Action Bar

    private var tomorrowActionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionPill(title: "Skip", systemImage: "bell.slash", isActive: viewModel.tomorrowAlarm.status == .skippedManually) {
                    viewModel.performTomorrowOverride(.skipTomorrow)
                }
                actionPill(title: "+30m", systemImage: "clock", isActive: false) {
                    viewModel.incrementTomorrowDelay(by: 30)
                }
                actionPill(title: "+1h", systemImage: "clock.arrow.circlepath", isActive: false) {
                    viewModel.incrementTomorrowDelay(by: 60)
                }
                if viewModel.tomorrowAlarm.hasManualOverride {
                    actionPill(title: "Restore", systemImage: "arrow.uturn.backward", isActive: true) {
                        viewModel.performTomorrowOverride(.none)
                    }
                } else {
                    actionPill(title: "Keep On", systemImage: "bell", isActive: false) {
                        viewModel.performTomorrowOverride(.forceKeepTomorrow)
                    }
                }
            }
            Text("Auto-restores to \(viewModel.snapshot.alarmRule.formattedBaseTime) the following day")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .vibeCard()
    }

    private func actionPill(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isActive ? Color.vibeAccent : Color(uiColor: .systemGray6))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Upcoming 5 Days Card

    private var upcomingDaysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UPCOMING")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.upcomingWeek.dropFirst(2).enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    HStack {
                        Text("\(item.weekdayText) \(Self.monthDayCaption(item.date))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(width: 92, alignment: .leading)

                        Text(shortReasonTag(for: item))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Text(item.status.isRinging ? (item.effectiveTime ?? item.baseTime) : "OFF")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(item.status.isRinging ? Color.primary : Color.secondary)
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .padding(16)
        .vibeCard()
    }

    private func shortReasonTag(for day: ResolvedDayAlarm) -> String {
        switch day.status {
        case .scheduled, .delayed:
            return day.matchedEntries.contains(where: { $0.kind == .makeupWorkday }) ? "Makeup" : "Workday"
        case .skippedByHoliday:
            return "Holiday"
        case .skippedByPersonalLeave:
            return "PTO"
        case .skippedManually:
            return "Skipped"
        case .noAlarm:
            return "Off"
        }
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func monthDayCaption(_ dateString: String) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month) else {
            return dateString
        }
        return "\(monthAbbreviations[month - 1]) \(day)"
    }
}
