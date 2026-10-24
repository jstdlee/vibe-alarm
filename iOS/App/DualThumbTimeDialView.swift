import SwiftUI
import UIKit
import VibeAlarmCore

/// Ergonomic Dual-Thumb Time Dial:
/// - Left column: Left thumb vertical drag wheel for Hour (`00`–`23`)
/// - Right column: Right thumb vertical drag wheel for Minute (`00`–`59`)
/// - Bottom section: Repeat mode, custom weekdays / specific dates, and smart holiday switches.
public struct DualThumbTimeDialView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newSpecificDate: Date = Date()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Label("左右手双转盘设定", systemImage: "hand.draw.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.isEnabled },
                    set: { enabled in viewModel.updateAlarmRule { $0.isEnabled = enabled } }
                ))
                .labelsHidden()
                .tint(.orange)
            }

            // Dual-Thumb Ergonomic Drum Wheels (Left Hand = Hour, Right Hand = Minute)
            HStack(spacing: 14) {
                ThumbDrumColumn(
                    title: "左手划 · 时 (HOUR)",
                    value: viewModel.snapshot.alarmRule.hour,
                    modulo: 24,
                    accentColor: .orange
                ) { newHour in
                    viewModel.updateAlarmTime(
                        hour: newHour,
                        minute: viewModel.snapshot.alarmRule.minute
                    )
                }

                Text(":")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))

                ThumbDrumColumn(
                    title: "右手划 · 分 (MIN)",
                    value: viewModel.snapshot.alarmRule.minute,
                    modulo: 60,
                    accentColor: .cyan
                ) { newMinute in
                    viewModel.updateAlarmTime(
                        hour: viewModel.snapshot.alarmRule.hour,
                        minute: newMinute
                    )
                }
            }

            // Quick Minute Step Pills for Right Thumb
            HStack(spacing: 8) {
                Text("快捷分:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach([0, 15, 30, 45], id: \.self) { presetMin in
                    Button {
                        triggerHaptic()
                        viewModel.updateAlarmTime(
                            hour: viewModel.snapshot.alarmRule.hour,
                            minute: presetMin
                        )
                    } label: {
                        Text(String(format: ":%02d", presetMin))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                viewModel.snapshot.alarmRule.minute == presetMin
                                    ? Color.cyan.opacity(0.28)
                                    : Color.white.opacity(0.08)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    triggerHaptic()
                    let (_, newM) = AlarmScheduleEngine.addMinutes(
                        hour: viewModel.snapshot.alarmRule.hour,
                        minute: viewModel.snapshot.alarmRule.minute,
                        delta: 5
                    )
                    viewModel.updateAlarmTime(hour: viewModel.snapshot.alarmRule.hour, minute: newM)
                } label: {
                    Text("+5m")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.22))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Color.white.opacity(0.12))

            // Repeat Mode & Date Selector (下方设定重复和日期)
            repeatAndDateSection

            Divider().overlay(Color.white.opacity(0.12))

            // Smart Holiday & Bedtime Toggles
            smartTogglesSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.11, green: 0.13, blue: 0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Repeat Mode & Specific Date Section

    private var repeatAndDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("重复周期与指定日期", systemImage: "repeat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.snapshot.alarmRule.repeatMode.summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            // 4 Mode Pills
            HStack(spacing: 6) {
                repeatModePill(title: "智能工作日", isSelected: isWeekdaysMode) {
                    viewModel.updateAlarmRule { $0.repeatMode = .weekdays }
                }
                repeatModePill(title: "每天", isSelected: isEverydayMode) {
                    viewModel.updateAlarmRule { $0.repeatMode = .everyday }
                }
                repeatModePill(title: "自定义周", isSelected: isCustomDaysMode) {
                    if !isCustomDaysMode {
                        viewModel.updateAlarmRule { $0.repeatMode = .customDays(Weekday.standardWeekdays) }
                    }
                }
                repeatModePill(title: "指定日期", isSelected: isSpecificDatesMode) {
                    if !isSpecificDatesMode {
                        let tomorrowStr = viewModel.tomorrowAlarm.date
                        viewModel.updateAlarmRule { $0.repeatMode = .specificDates([tomorrowStr]) }
                    }
                }
            }

            // Conditional Sub-Selector: Custom Weekdays OR Specific Dates
            if case .customDays(let selectedDays) = viewModel.snapshot.alarmRule.repeatMode {
                HStack(spacing: 6) {
                    ForEach([Weekday.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], id: \.self) { day in
                        let active = selectedDays.contains(day)
                        Button {
                            triggerHaptic()
                            var next = selectedDays
                            if active {
                                next.remove(day)
                            } else {
                                next.insert(day)
                            }
                            viewModel.updateAlarmRule { $0.repeatMode = .customDays(next) }
                        } label: {
                            Text(day.compactLabel)
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(active ? Color.orange : Color.white.opacity(0.08))
                                .foregroundStyle(active ? .black : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if case .specificDates(let dates) = viewModel.snapshot.alarmRule.repeatMode {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        DatePicker(
                            "选择日期",
                            selection: $newSpecificDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .colorScheme(.dark)

                        Button {
                            triggerHaptic()
                            let dStr = AlarmScheduleEngine().dateString(from: newSpecificDate)
                            var next = dates
                            next.insert(dStr)
                            viewModel.updateAlarmRule { $0.repeatMode = .specificDates(next) }
                        } label: {
                            Label("添加日期", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.25))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if !dates.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(dates.sorted(), id: \.self) { dStr in
                                    HStack(spacing: 4) {
                                        Text(dStr)
                                            .font(.caption2.weight(.semibold))
                                        Button {
                                            var next = dates
                                            next.remove(dStr)
                                            viewModel.updateAlarmRule { $0.repeatMode = .specificDates(next) }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Smart Holiday & Bedtime Toggles

    private var smartTogglesSection: some View {
        VStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { viewModel.snapshot.alarmRule.skipPublicHolidays },
                set: { val in viewModel.updateAlarmRule { $0.skipPublicHolidays = val } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("智能公共假期跳过 & 调休补班响铃")
                        .font(.footnote.weight(.medium))
                    Text("自动跳过法定假日；遇到周末调休补班自动开启闹钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)

            Toggle(isOn: Binding(
                get: { viewModel.snapshot.alarmRule.skipPersonalLeave },
                set: { val in viewModel.updateAlarmRule { $0.skipPersonalLeave = val } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("结合个人休假 (本地日历 / BYOK 录入)")
                        .font(.footnote.weight(.medium))
                    Text("检测到年假/请假/PTO 自动跳过，不打扰休假睡眠")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.mint)

            HStack {
                Toggle(isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.bedtimeReminderEnabled },
                    set: { val in viewModel.updateAlarmRule { $0.bedtimeReminderEnabled = val } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("睡前通知提醒明日闹钟 (\(viewModel.snapshot.alarmRule.formattedBedtimeReminder))")
                            .font(.footnote.weight(.medium))
                        Text("长按通知可直接选「跳过明日」「推迟」或「保持」")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.cyan)
            }
        }
    }

    private var isWeekdaysMode: Bool {
        if case .weekdays = viewModel.snapshot.alarmRule.repeatMode { return true }
        return false
    }

    private var isEverydayMode: Bool {
        if case .everyday = viewModel.snapshot.alarmRule.repeatMode { return true }
        return false
    }

    private var isCustomDaysMode: Bool {
        if case .customDays = viewModel.snapshot.alarmRule.repeatMode { return true }
        return false
    }

    private var isSpecificDatesMode: Bool {
        if case .specificDates = viewModel.snapshot.alarmRule.repeatMode { return true }
        return false
    }

    private func repeatModePill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            triggerHaptic()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange : Color.white.opacity(0.08))
                .foregroundStyle(isSelected ? .black : .white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// MARK: - Single Thumb Drum Wheel Column (Vertical Drag + Curved Cylinder Slots)

private struct ThumbDrumColumn: View {
    let title: String
    let value: Int
    let modulo: Int
    let accentColor: Color
    let onChange: (Int) -> Void

    @State private var dragStartValue: Int?
    @State private var visualOffset: CGFloat = 0

    private let stepHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accentColor)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(accentColor.opacity(0.35), lineWidth: 1.2)
                    )

                // Center selection highlight band
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.16))
                    .frame(height: 50)
                    .padding(.horizontal, 8)

                // 5 visible drum slots (-2, -1, 0, +1, +2)
                VStack(spacing: 4) {
                    ForEach([-2, -1, 0, 1, 2], id: \.self) { delta in
                        let slotVal = wrapped(value + delta)
                        Text(String(format: "%02d", slotVal))
                            .font(.system(
                                size: delta == 0 ? 36 : (abs(delta) == 1 ? 20 : 14),
                                weight: delta == 0 ? .heavy : .semibold,
                                design: .rounded
                            ))
                            .foregroundStyle(
                                delta == 0
                                    ? Color.white
                                    : Color.white.opacity(abs(delta) == 1 ? 0.42 : 0.18)
                            )
                            .scaleEffect(delta == 0 ? 1.0 : (abs(delta) == 1 ? 0.88 : 0.75))
                            .frame(height: delta == 0 ? 44 : 24)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard delta != 0 else { return }
                                emitTick(newValue: slotVal)
                            }
                    }
                }
                .offset(y: visualOffset * 0.25)
            }
            .frame(height: 168)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        if dragStartValue == nil {
                            dragStartValue = value
                        }
                        let base = dragStartValue ?? value
                        let steps = Int((-gesture.translation.height / stepHeight).rounded())
                        let candidate = wrapped(base + steps)
                        visualOffset = gesture.translation.height.truncatingRemainder(dividingBy: stepHeight)
                        if candidate != value {
                            emitTick(newValue: candidate)
                        }
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                            visualOffset = 0
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func wrapped(_ raw: Int) -> Int {
        ((raw % modulo) + modulo) % modulo
    }

    private func emitTick(newValue: Int) {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.impactOccurred(intensity: 0.65)
        onChange(newValue)
    }
}
