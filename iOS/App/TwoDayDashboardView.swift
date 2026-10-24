import SwiftUI
import VibeAlarmCore

/// Primary iOS Clock-style ("闹钟") screen:
/// - Pure Apple HIG dark aesthetic (`#000000` background, `#1C1C1E` inset grouped cells, `#FF9F0A` orange tint, light SF numerals).
/// - Focused on **Today & Tomorrow (近两日)**: clearly shows statutory holiday skips, makeup workday activation, and one-tap temporary overrides that automatically restore the day after tomorrow.
public struct TwoDayDashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var showEditAlarmSheet = false
    @State private var showHolidayCalendar = false
    @State private var showBYOKSheet = false
    @State private var showSettings = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Today & Tomorrow (近两日排期)
                Section {
                    clockAlarmRow(day: viewModel.todayAlarm, isTomorrow: false)
                    clockAlarmRow(day: viewModel.tomorrowAlarm, isTomorrow: true)
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "bed.double.fill")
                        Text("睡眠｜起床闹钟 · 近两日")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .textCase(nil)
                } footer: {
                    Text("次日操作（「跳过明日」或「推迟 30 分钟」）仅对明天单次生效，后天自动恢复原定排期。")
                        .font(.footnote)
                }

                // Section 2: Next 5 Days Schedule (近期排期)
                Section {
                    ForEach(Array(viewModel.upcomingWeek.dropFirst(2))) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.weekdayText) · \(item.date.suffix(5))")
                                    .font(.body)
                                    .foregroundStyle(.white)
                                Text(item.reasonBadge)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let eff = item.effectiveTime, item.status.isRinging {
                                Text(eff)
                                    .font(.system(size: 22, weight: .light))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                            } else {
                                Text("不响铃")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("后续 5 日排期")
                        .textCase(nil)
                }

                // Section 3: Holiday & Calendar Sources (节假日与日历)
                Section {
                    Button {
                        showHolidayCalendar = true
                    } label: {
                        HStack {
                            Label("公共假期与调休订阅", systemImage: "calendar")
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(viewModel.snapshot.subscriptions.count) 个订阅源")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Button {
                        showBYOKSheet = true
                    } label: {
                        HStack {
                            Label("解析放假通知或请假文本", systemImage: "doc.text.magnifyingglass")
                                .foregroundStyle(.white)
                            Spacer()
                            Text("本地 / BYOK")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Button {
                        Task { await viewModel.syncLocalCalendars() }
                    } label: {
                        HStack {
                            Label("同步系统日历请假日程", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                            Spacer()
                            if let message = viewModel.statusBannerMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text("节假日与请假数据源")
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("闹钟")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("设置") {
                        showSettings = true
                    }
                    .foregroundStyle(.orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditAlarmSheet = true
                    } label: {
                        Text("设定时间")
                            .fontWeight(.regular)
                    }
                    .foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showEditAlarmSheet) {
                DualThumbTimeDialSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showHolidayCalendar) {
                HolidayCalendarView(viewModel: viewModel)
            }
            .sheet(isPresented: $showBYOKSheet) {
                BYOKInputSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
    }

    // MARK: - Native iOS Clock-Style Alarm Row

    @ViewBuilder
    private func clockAlarmRow(day: ResolvedDayAlarm, isTomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    // Subtle top metadata line
                    HStack(spacing: 6) {
                        Text("\(day.displayLabel) · \(day.weekdayText)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isTomorrow ? Color.orange : Color.secondary)
                        Text("(\(day.date.suffix(5)))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    // Large thin Apple Clock numeral
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(day.effectiveTime ?? day.baseTime)
                            .font(.system(size: 56, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(day.status.isRinging ? Color.white : Color(uiColor: .tertiaryLabel))

                        if let eff = day.effectiveTime, eff != day.baseTime, day.status.isRinging {
                            Text("原定 \(day.baseTime)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Clean status subtitle
                    Text(statusSubtitle(for: day))
                        .font(.subheadline)
                        .foregroundStyle(day.status.isRinging ? Color.secondary : Color.orange)
                }

                Spacer()

                if isTomorrow {
                    Toggle("", isOn: Binding(
                        get: { day.status.isRinging },
                        set: { shouldRing in
                            if shouldRing {
                                if day.hasManualOverride {
                                    viewModel.performTomorrowOverride(.none)
                                } else {
                                    viewModel.performTomorrowOverride(.forceKeepTomorrow)
                                }
                            } else {
                                viewModel.performTomorrowOverride(.skipTomorrow)
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(.green)
                } else {
                    Button {
                        showEditAlarmSheet = true
                    } label: {
                        Text("更改")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showEditAlarmSheet = true
            }

            // Clean secondary action bar for Tomorrow only (Apple Clock capsule buttons)
            if isTomorrow {
                Divider()
                HStack(spacing: 8) {
                    tomorrowCapsuleButton(
                        title: "跳过明日",
                        systemImage: "bell.slash",
                        isActive: day.status == .skippedManually
                    ) {
                        viewModel.performTomorrowOverride(.skipTomorrow)
                    }

                    tomorrowCapsuleButton(
                        title: "推迟 30 分钟",
                        systemImage: "plus.circle",
                        isActive: isDelayed(day)
                    ) {
                        viewModel.incrementTomorrowDelay(by: 30)
                    }

                    if day.hasManualOverride {
                        tomorrowCapsuleButton(
                            title: "恢复原定",
                            systemImage: "arrow.uturn.backward",
                            isActive: true
                        ) {
                            viewModel.performTomorrowOverride(.none)
                        }
                    } else if !day.status.isRinging {
                        tomorrowCapsuleButton(
                            title: "明日照常响铃",
                            systemImage: "bell",
                            isActive: false
                        ) {
                            viewModel.performTomorrowOverride(.forceKeepTomorrow)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusSubtitle(for day: ResolvedDayAlarm) -> String {
        if day.status.isRinging {
            return "\(viewModel.snapshot.alarmRule.label)，\(day.reasonBadge)"
        } else {
            return "不响铃 · \(day.reasonBadge)"
        }
    }

    private func isDelayed(_ day: ResolvedDayAlarm) -> Bool {
        if case .delayed = day.status { return true }
        return false
    }

    private func tomorrowCapsuleButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                isActive
                    ? Color.orange.opacity(0.22)
                    : Color(uiColor: .tertiarySystemFill)
            )
            .foregroundStyle(.orange)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
