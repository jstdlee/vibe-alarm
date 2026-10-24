import SwiftUI
import VibeAlarmCore

/// Primary Interface:
/// - Focused on **Today & Tomorrow's Alarms (最近两天闹钟)**
/// - One-tap Tomorrow Controls: Skip Tomorrow, Delay +30m / +1h, Restore Tomorrow, Force Keep
/// - Ergonomic Dual-Thumb Hour/Minute Dial + Repeat & Date Settings
/// - Quick entry to BYOK AI Holiday Parser, Built-in Holiday Calendar, and Privacy/EventKit Settings
public struct TwoDayDashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var showBYOKSheet = false
    @State private var showHolidayCalendar = false
    @State private var showSettings = false
    @State private var show7DayPreview = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let banner = viewModel.statusBannerMessage {
                        statusBanner(banner)
                    }

                    // 1. Two-Day Alarm Cards (界面显示最近两天闹钟即可)
                    twoDayHeaderSection

                    // 2. One-Tap Tomorrow Action Bar (不打扰模式一键推迟和恢复次日闹钟)
                    tomorrowQuickActionsSection

                    // 3. Ergonomic Dual-Thumb Dial (左右手划动设置 hour minute 转盘 + 下方设定重复和日期)
                    DualThumbTimeDialView(viewModel: viewModel)

                    // 4. Holiday Sources & BYOK Quick Entry Bar
                    holidaySourcesBar

                    // 5. Optional Expandable 7-Day Schedule Preview
                    upcomingWeekDisclosure
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.12),
                        Color(red: 0.08, green: 0.10, blue: 0.17)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Vibe 假期闹钟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHolidayCalendar = true
                    } label: {
                        Label("假期日历", systemImage: "calendar.badge.clock")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showBYOKSheet = true
                        } label: {
                            Label("AI 录假期", systemImage: "sparkles")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showBYOKSheet) {
                BYOKInputSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showHolidayCalendar) {
                HolidayCalendarView(viewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Status Banner

    private func statusBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Button {
                viewModel.statusBannerMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Recent Two Days Section (今明两天闹钟状态)

    private var twoDayHeaderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最近两天闹钟排期", systemImage: "alarm.waves.left.and.right.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("100% 本地零云端")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.mint.opacity(0.18))
                    .foregroundStyle(.mint)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                dayCard(day: viewModel.todayAlarm, isTomorrow: false)
                dayCard(day: viewModel.tomorrowAlarm, isTomorrow: true)
            }
        }
    }

    private func dayCard(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(day.displayLabel) · \(day.weekdayText)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(isTomorrow ? .orange : .white.opacity(0.85))
                Spacer()
                Text(day.date.suffix(5))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let eff = day.effectiveTime, day.status.isRinging {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(eff)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    if eff != day.baseTime {
                        Text(day.baseTime)
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("免响铃")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.mint)
                    Text(day.baseTime)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: day.status.isRinging ? "bell.badge.fill" : "moon.zzz.fill")
                    .font(.caption2)
                    .foregroundStyle(day.status.isRinging ? .orange : .mint)
                Text(day.reasonBadge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isTomorrow
                        ? Color.orange.opacity(0.14)
                        : Color.white.opacity(0.06)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isTomorrow ? Color.orange.opacity(0.45) : Color.white.opacity(0.08),
                            lineWidth: 1.2
                        )
                )
        )
    }

    // MARK: - One-Tap Tomorrow Override Bar

    private var tomorrowQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("次日闹钟一键控制 (单次生效 · 后天自动恢复)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.tomorrowAlarm.hasManualOverride {
                    Text("已设临时覆盖")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                quickActionButton(
                    title: "跳过明日",
                    icon: "bell.slash.fill",
                    tint: .red
                ) {
                    viewModel.performTomorrowOverride(.skipTomorrow)
                }

                quickActionButton(
                    title: "推迟 +30m",
                    icon: "clock.arrow.circlepath",
                    tint: .orange
                ) {
                    viewModel.incrementTomorrowDelay(by: 30)
                }

                quickActionButton(
                    title: "推迟 +1h",
                    icon: "plus.circle.fill",
                    tint: .yellow
                ) {
                    viewModel.incrementTomorrowDelay(by: 60)
                }

                if viewModel.tomorrowAlarm.hasManualOverride {
                    quickActionButton(
                        title: "一键恢复",
                        icon: "arrow.uturn.backward.circle.fill",
                        tint: .green
                    ) {
                        viewModel.performTomorrowOverride(.none)
                    }
                } else {
                    quickActionButton(
                        title: "强制保持",
                        icon: "lock.fill",
                        tint: .cyan
                    ) {
                        viewModel.performTomorrowOverride(.forceKeepTomorrow)
                    }
                }
            }
        }
    }

    private func quickActionButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Holiday Sources & BYOK Quick Entry

    private var holidaySourcesBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showBYOKSheet = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("粘贴邮件/公告 · BYOK 智能录假期")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("支持自带 Key 调 LLM 或离线识别请假、调休与 .ics 链接")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.syncLocalCalendars() }
                } label: {
                    Label("读取本地日历请假", systemImage: "calendar.badge.checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.mint.opacity(0.16))
                        .foregroundStyle(.mint)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.syncExternalSubscriptions() }
                } label: {
                    Label(
                        viewModel.isSyncingICS ? "同步订阅中..." : "刷新外部假期订阅",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.16))
                    .foregroundStyle(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Expandable 7-Day Preview

    private var upcomingWeekDisclosure: some View {
        DisclosureGroup(isExpanded: $show7DayPreview) {
            VStack(spacing: 6) {
                ForEach(viewModel.upcomingWeek) { item in
                    HStack {
                        Text("\(item.displayLabel) (\(item.weekdayText))")
                            .font(.caption.weight(.semibold))
                            .frame(width: 84, alignment: .leading)
                        Text(item.date)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.reasonBadge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(item.effectiveTime ?? "免响")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(item.status.isRinging ? .orange : .mint)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("查看未来 7 天排期推演 (已存 \(viewModel.snapshot.holidayEntries.count) 条假期记录)", systemImage: "list.bullet.rectangle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
