import SwiftUI
import UIKit
import VibeAlarmCore

/// Ergonomic Skeuomorphic Dual-Thumb Time Picker Sheet / Tab (`设定时间`):
/// - **Light Theme (`#F2F2F7` / `#FFFFFF` / Braun-Apple tactile metallic-ivory surfaces)**.
/// - **Upper area**: Clean digital readout (`07 : 30`) + alarm label so no high thumb reach is required.
/// - **Middle area**: Skeuomorphic Horizontal Roller Axes (`横向拟物滚动轴`) replacing traditional dropdowns for Repeat Mode (`重复周期`) and Smart Holiday Policy (`假期与调休策略`).
/// - **Middle-Lower area**: Left & Right Semi-Circular Skeuomorphic Rotary Dials (`左右半圆拟物转盘`) anchored to the left and right edges of the lower half of the screen for effortless two-handed thumb rotation.
public struct DualThumbTimeDialSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    public var isEmbeddedInTab: Bool

    public init(viewModel: AppViewModel, isEmbeddedInTab: Bool = false) {
        self.viewModel = viewModel
        self.isEmbeddedInTab = isEmbeddedInTab
    }

    public var body: some View {
        NavigationStack {
            DualThumbTimeDialView(viewModel: viewModel)
                .navigationTitle("设定闹钟时间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !isEmbeddedInTab {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                dismiss()
                            }
                            .foregroundStyle(.orange)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") {
                                dismiss()
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            Text("双手拇指拟物拨盘")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.showBanner("已保存闹钟 \(viewModel.snapshot.alarmRule.formattedBaseTime)")
                            } label: {
                                Text("已实时保存")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
        }
        .tint(.orange)
        .preferredColorScheme(.light)
    }
}

public struct DualThumbTimeDialView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newSpecificDate: Date = Date()

    private let repeatOptions: [String] = [
        "法定工作日",
        "每天响铃",
        "自定义星期",
        "指定日期"
    ]

    private let holidayPolicyOptions: [String] = [
        "节假日跳+补班响",
        "节假日+请假全跳",
        "仅跳过法定节假日",
        "不启用假期跳过"
    ]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // 1. TOP READOUT CARD (Upper zone: clean digital display + label, no high reach needed)
                topDigitalReadoutCard

                // 2. MIDDLE ZONE: SKEUOMORPHIC HORIZONTAL ROLLER AXES (横向滚动轴模拟拟物 Dropdown)
                horizontalRollerDropdownCard

                // Optional inline expansion when Custom Weekdays or Specific Dates is selected on the roller
                if case .customDays(let selectedDays) = viewModel.snapshot.alarmRule.repeatMode {
                    customWeekdaysBar(selectedDays: selectedDays)
                } else if case .specificDates(let dates) = viewModel.snapshot.alarmRule.repeatMode {
                    specificDatesBar(dates: dates)
                }

                // 3. MIDDLE-LOWER ZONE: LEFT & RIGHT SEMI-CIRCULAR SKEUOMORPHIC ROTARY DIALS
                // Positioned in the middle-to-lower half of the screen where left & right thumbs naturally rotate!
                semiCircularRotaryDialsCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - 1. Top Digital Readout Card

    private var topDigitalReadoutCard: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    TextField("起床闹钟", text: Binding(
                        get: { viewModel.snapshot.alarmRule.label },
                        set: { val in viewModel.updateAlarmRule { $0.label = val } }
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                }

                Spacer()

                Text("明日状态: \(viewModel.tomorrowAlarm.status.isRinging ? (viewModel.tomorrowAlarm.effectiveTime ?? viewModel.tomorrowAlarm.baseTime) : "免响铃")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(viewModel.tomorrowAlarm.status.isRinging ? Color.secondary : Color.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .systemGray6))
                    .clipShape(Capsule())
            }

            // Recessed LCD / Ceramic Readout Bezel
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(spacing: 2) {
                    Text(String(format: "%02d", viewModel.snapshot.alarmRule.hour))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                    Text("左手半圆 · 时 (HOUR)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Text(":")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.orange)
                    .offset(y: -10)

                VStack(spacing: 2) {
                    Text(String(format: "%02d", viewModel.snapshot.alarmRule.minute))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                    Text("右手半圆 · 分 (MIN)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.95, blue: 0.96),
                                Color(red: 0.99, green: 0.99, blue: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - 2. Middle Zone: Skeuomorphic Horizontal Roller Axes (拟物横向滚动轴 Dropdown)

    private var horizontalRollerDropdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("周期与假期规则 · 横向拟物滚轴", systemImage: "cylinder.split.1x2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("左右滑动滚轴切换")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Horizontal Roller 1: Repeat Mode
            SkeuomorphicHorizontalRoller(
                title: "重复周期",
                options: repeatOptions,
                selectedIndex: repeatModeIndex
            ) { newIndex in
                switch newIndex {
                case 0:
                    viewModel.updateAlarmRule { $0.repeatMode = .weekdays }
                case 1:
                    viewModel.updateAlarmRule { $0.repeatMode = .everyday }
                case 2:
                    viewModel.updateAlarmRule { $0.repeatMode = .customDays(Weekday.standardWeekdays) }
                case 3:
                    let tomorrowStr = viewModel.tomorrowAlarm.date
                    viewModel.updateAlarmRule { $0.repeatMode = .specificDates([tomorrowStr]) }
                default:
                    break
                }
            }

            // Horizontal Roller 2: Smart Holiday & Makeup Workday Policy
            SkeuomorphicHorizontalRoller(
                title: "假期策略",
                options: holidayPolicyOptions,
                selectedIndex: holidayPolicyIndex
            ) { newIndex in
                switch newIndex {
                case 0:
                    viewModel.updateAlarmRule {
                        $0.skipPublicHolidays = true
                        $0.skipPersonalLeave = false
                    }
                case 1:
                    viewModel.updateAlarmRule {
                        $0.skipPublicHolidays = true
                        $0.skipPersonalLeave = true
                    }
                case 2:
                    viewModel.updateAlarmRule {
                        $0.skipPublicHolidays = true
                        $0.skipPersonalLeave = false
                    }
                case 3:
                    viewModel.updateAlarmRule {
                        $0.skipPublicHolidays = false
                        $0.skipPersonalLeave = false
                    }
                default:
                    break
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - 3. Middle-Lower Zone: Left & Right Semi-Circular Skeuomorphic Rotary Dials

    private var semiCircularRotaryDialsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Label("左右半圆拟物转盘 (屏幕中下部双手拇指区)", systemImage: "dial.medium.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("上下拨动转盘边缘")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 4)

            GeometryReader { geo in
                let totalW = geo.size.width
                let totalH = geo.size.height

                ZStack {
                    // Subtle machined recessed chassis plate
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.94, green: 0.94, blue: 0.96),
                                    Color(red: 0.90, green: 0.90, blue: 0.93)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        )

                    // LEFT SEMI-CIRCULAR ROTARY DIAL (Hour 00-23, anchored on left edge)
                    SemiCircularSkeuomorphicDial(
                        side: .left,
                        value: viewModel.snapshot.alarmRule.hour,
                        modulo: 24,
                        unitTitle: "时",
                        subtitle: "左手旋时"
                    ) { newHour in
                        viewModel.updateAlarmTime(
                            hour: newHour,
                            minute: viewModel.snapshot.alarmRule.minute
                        )
                    }
                    .frame(width: totalW * 0.44, height: totalH)
                    .position(x: totalW * 0.22, y: totalH / 2)

                    // RIGHT SEMI-CIRCULAR ROTARY DIAL (Minute 00-59, anchored on right edge)
                    SemiCircularSkeuomorphicDial(
                        side: .right,
                        value: viewModel.snapshot.alarmRule.minute,
                        modulo: 60,
                        unitTitle: "分",
                        subtitle: "右手旋分"
                    ) { newMinute in
                        viewModel.updateAlarmTime(
                            hour: viewModel.snapshot.alarmRule.hour,
                            minute: newMinute
                        )
                    }
                    .frame(width: totalW * 0.44, height: totalH)
                    .position(x: totalW * 0.78, y: totalH / 2)

                    // CENTER MECHANICAL SPINE: Dual Pointer Needles + Quick Minute Detents
                    VStack(spacing: 10) {
                        Text("拇指刻度盘")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        // Center Dual Index Pointer Bridge pointing left (Hour) and right (Minute)
                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrowtriangle.left.fill")
                                    .font(.system(size: 9))
                                Text("时")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .clipShape(Capsule())

                            HStack(spacing: 2) {
                                Text("分")
                                    .font(.system(size: 11, weight: .bold))
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .clipShape(Capsule())
                        }
                        .shadow(color: Color.orange.opacity(0.3), radius: 3, x: 0, y: 1)

                        // Quick tactile minute preset buttons in the center column
                        VStack(spacing: 6) {
                            ForEach([0, 15, 30, 45], id: \.self) { presetMin in
                                let isCurrent = viewModel.snapshot.alarmRule.minute == presetMin
                                Button {
                                    let gen = UIImpactFeedbackGenerator(style: .light)
                                    gen.impactOccurred()
                                    viewModel.updateAlarmTime(
                                        hour: viewModel.snapshot.alarmRule.hour,
                                        minute: presetMin
                                    )
                                } label: {
                                    Text(String(format: ":%02d", presetMin))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .frame(width: 54, height: 26)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isCurrent ? Color.orange : Color.white)
                                                .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                                        )
                                        .foregroundStyle(isCurrent ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            let gen = UIImpactFeedbackGenerator(style: .rigid)
                            gen.impactOccurred()
                            let nextMin = (viewModel.snapshot.alarmRule.minute + 5) % 60
                            viewModel.updateAlarmTime(
                                hour: viewModel.snapshot.alarmRule.hour,
                                minute: nextMin
                            )
                        } label: {
                            Text("+5m")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 54, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.9))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: totalW * 0.22)
                    .position(x: totalW * 0.5, y: totalH / 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(height: 292)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: - Optional Aux Bars for Custom Weekdays / Specific Dates

    private func customWeekdaysBar(selectedDays: Set<Weekday>) -> some View {
        HStack(spacing: 6) {
            ForEach([Weekday.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], id: \.self) { day in
                let active = selectedDays.contains(day)
                Button {
                    var next = selectedDays
                    if active { next.remove(day) } else { next.insert(day) }
                    viewModel.updateAlarmRule { $0.repeatMode = .customDays(next) }
                } label: {
                    Text(day.compactLabel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(active ? Color.orange : Color(uiColor: .systemGray6))
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    private func specificDatesBar(dates: Set<String>) -> some View {
        VStack(spacing: 8) {
            HStack {
                DatePicker("选择特定日期", selection: $newSpecificDate, displayedComponents: .date)
                    .font(.subheadline)
                Button("添加日期") {
                    let dStr = AlarmScheduleEngine().dateString(from: newSpecificDate)
                    var next = dates
                    next.insert(dStr)
                    viewModel.updateAlarmRule { $0.repeatMode = .specificDates(next) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    private var repeatModeIndex: Int {
        switch viewModel.snapshot.alarmRule.repeatMode {
        case .weekdays: return 0
        case .everyday: return 1
        case .customDays: return 2
        case .specificDates: return 3
        }
    }

    private var holidayPolicyIndex: Int {
        let rule = viewModel.snapshot.alarmRule
        if rule.skipPublicHolidays && rule.skipPersonalLeave {
            return 1
        } else if rule.skipPublicHolidays && !rule.skipPersonalLeave {
            return 0
        } else {
            return 3
        }
    }
}

// MARK: - Skeuomorphic Horizontal Roller Axis (横向滚动轴模拟拟物 Dropdown)

public struct SkeuomorphicHorizontalRoller: View {
    public let title: String
    public let options: [String]
    public let selectedIndex: Int
    public let onSelect: (Int) -> Void

    @State private var dragStartIndex: Int?
    @State private var dragVisualOffset: CGFloat = 0

    public init(
        title: String,
        options: [String],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) {
        self.title = title
        self.options = options
        self.selectedIndex = max(0, min(max(0, options.count - 1), selectedIndex))
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Left title label
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            // Recessed Mechanical Horizontal Cylinder Slot
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // 1. Metallic/ivory horizontal barrel base with vertical knurled ridges
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.86, green: 0.86, blue: 0.89),
                                    Color(red: 0.98, green: 0.98, blue: 0.99),
                                    Color(red: 0.99, green: 0.99, blue: 1.0),
                                    Color(red: 0.85, green: 0.85, blue: 0.88)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    // 2. Fine vertical mechanical knurling lines across the horizontal roller
                    HStack(spacing: 6) {
                        ForEach(0..<36, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.045))
                                .frame(width: 1, height: h - 6)
                        }
                    }

                    // 3. 3D Horizontally Rotated Option Labels (-1, 0, +1 along the horizontal axis)
                    ZStack {
                        ForEach([-1, 0, 1], id: \.self) { delta in
                            let idx = wrappedIndex(selectedIndex + delta)
                            let isCenter = delta == 0
                            let xOffset = CGFloat(delta) * (w * 0.35) + dragVisualOffset * 0.25

                            Text(options[idx])
                                .font(.system(size: isCenter ? 13 : 11, weight: isCenter ? .bold : .medium))
                                .foregroundStyle(
                                    isCenter
                                        ? Color(red: 0.10, green: 0.10, blue: 0.12)
                                        : Color.secondary.opacity(0.65)
                                )
                                .lineLimit(1)
                                .rotation3DEffect(
                                    .degrees(Double(delta) * -32),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.45
                                )
                                .scaleEffect(isCenter ? 1.0 : 0.86)
                                .offset(x: xOffset)
                                .onTapGesture {
                                    guard delta != 0 else { return }
                                    emitRollerTick(idx)
                                }
                        }
                    }

                    // 4. Center Magnification Window & Top/Bottom Orange Index Pointers
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.orange.opacity(0.75), lineWidth: 1.2)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .frame(width: w * 0.44, height: h - 6)

                    VStack {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.orange)
                        Spacer()
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 1)

                    // 5. Left & Right Cylindrical Edge Shadow Overlay + Step Chevrons
                    HStack {
                        Button {
                            emitRollerTick(wrappedIndex(selectedIndex - 1))
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: h)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            emitRollerTick(wrappedIndex(selectedIndex + 1))
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: h)
                        }
                        .buttonStyle(.plain)
                    }

                    // Recessed inner border
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.16), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { gesture in
                            if dragStartIndex == nil {
                                dragStartIndex = selectedIndex
                            }
                            let base = dragStartIndex ?? selectedIndex
                            let stepWidth: CGFloat = 52
                            let steps = Int((-gesture.translation.width / stepWidth).rounded())
                            let candidate = wrappedIndex(base + steps)
                            dragVisualOffset = gesture.translation.width.truncatingRemainder(dividingBy: stepWidth)
                            if candidate != selectedIndex {
                                emitRollerTick(candidate)
                            }
                        }
                        .onEnded { _ in
                            dragStartIndex = nil
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                dragVisualOffset = 0
                            }
                        }
                )
            }
            .frame(height: 38)
        }
    }

    private func wrappedIndex(_ raw: Int) -> Int {
        guard !options.isEmpty else { return 0 }
        return ((raw % options.count) + options.count) % options.count
    }

    private func emitRollerTick(_ idx: Int) {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
        onSelect(idx)
    }
}

// MARK: - Semi-Circular Skeuomorphic Rotary Dial (左右半个转盘拟物形式旋转)

public enum SemiCircularDialSide {
    case left
    case right
}

public struct SemiCircularSkeuomorphicDial: View {
    public let side: SemiCircularDialSide
    public let value: Int
    public let modulo: Int
    public let unitTitle: String
    public let subtitle: String
    public let onChange: (Int) -> Void

    @State private var dragStartValue: Int?
    @State private var dragVisualFraction: CGFloat = 0

    public init(
        side: SemiCircularDialSide,
        value: Int,
        modulo: Int,
        unitTitle: String,
        subtitle: String,
        onChange: @escaping (Int) -> Void
    ) {
        self.side = side
        self.value = value
        self.modulo = modulo
        self.unitTitle = unitTitle
        self.subtitle = subtitle
        self.onChange = onChange
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = min(w * 0.96, h * 0.48)
            // Anchor the wheel center on the outer left or outer right edge so the semi-circle protrudes inward!
            let center = CGPoint(
                x: side == .left ? -8 : w + 8,
                y: h / 2
            )

            ZStack {
                // 1. Machined Skeuomorphic Wheel Disc & Ticks via SwiftUI Canvas
                Canvas { context, _ in
                    let wheelRect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let wheelPath = Path(ellipseIn: wheelRect)

                    // Outer drop shadow
                    context.drawLayer { shadowCtx in
                        shadowCtx.addFilter(.shadow(color: .black.opacity(0.16), radius: 8, x: side == .left ? 3 : -3, y: 2))
                        shadowCtx.fill(wheelPath, with: .color(Color(red: 0.97, green: 0.97, blue: 0.98)))
                    }

                    // Outer metallic/ceramic rim stroke
                    context.stroke(wheelPath, with: .color(Color.black.opacity(0.18)), lineWidth: 1.5)

                    // Concentric machined rings
                    for factor in [0.92, 0.82, 0.56, 0.34] as [CGFloat] {
                        let r = radius * factor
                        let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                        context.stroke(
                            Path(ellipseIn: ringRect),
                            with: .color(Color.black.opacity(factor == 0.82 ? 0.12 : 0.07)),
                            lineWidth: 1
                        )
                    }

                    // Knurled outer teeth & radial graduation ticks
                    let totalTeeth = 60
                    let fractionalShift = Double(dragVisualFraction) * 6.0
                    for i in 0..<totalTeeth {
                        let deg = Double(i) * (360.0 / Double(totalTeeth)) + fractionalShift
                        let rad = deg * .pi / 180.0
                        let cosA = CGFloat(cos(rad))
                        let sinA = CGFloat(sin(rad))

                        // Outer knurled serration tooth
                        let pOuter1 = CGPoint(x: center.x + cosA * (radius * 0.94), y: center.y + sinA * (radius * 0.94))
                        let pOuter2 = CGPoint(x: center.x + cosA * (radius * 0.99), y: center.y + sinA * (radius * 0.99))
                        var tooth = Path()
                        tooth.move(to: pOuter1)
                        tooth.addLine(to: pOuter2)
                        context.stroke(tooth, with: .color(Color.black.opacity(0.22)), lineWidth: 1.2)

                        // Inner graduation tick on track
                        let isMajor = i % 5 == 0
                        let innerR = radius * (isMajor ? 0.83 : 0.86)
                        let outerR = radius * 0.91
                        let p1 = CGPoint(x: center.x + cosA * innerR, y: center.y + sinA * innerR)
                        let p2 = CGPoint(x: center.x + cosA * outerR, y: center.y + sinA * outerR)
                        var tick = Path()
                        tick.move(to: p1)
                        tick.addLine(to: p2)
                        context.stroke(
                            tick,
                            with: .color(isMajor ? Color.orange.opacity(0.85) : Color.black.opacity(0.20)),
                            lineWidth: isMajor ? 1.8 : 0.9
                        )
                    }

                    // Center recessed hub cap
                    let hubR = radius * 0.34
                    let hubRect = CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)
                    context.fill(Path(ellipseIn: hubRect), with: .color(Color(red: 0.91, green: 0.91, blue: 0.94)))
                    context.stroke(Path(ellipseIn: hubRect), with: .color(Color.black.opacity(0.15)), lineWidth: 1)
                }

                // 2. Radial Rotating Numbers along the Semi-Circular Arc (-3, -2, -1, 0, +1, +2, +3)
                ForEach([-3, -2, -1, 0, 1, 2, 3], id: \.self) { delta in
                    let slotValue = wrapped(value + delta)
                    let isSelected = delta == 0
                    let stepAngleDeg: Double = 23.0
                    let baseAngleDeg: Double = side == .left ? 0.0 : 180.0
                    // For left wheel (0° pointing right), +delta goes downward (+deg);
                    // For right wheel (180° pointing left), +delta also goes downward (-deg in standard polar).
                    let angleDeg: Double = side == .left
                        ? (baseAngleDeg + Double(delta) * stepAngleDeg)
                        : (baseAngleDeg - Double(delta) * stepAngleDeg)
                    let angleRad = angleDeg * .pi / 180.0

                    let numRadius = radius * 0.69
                    let xPos = center.x + CGFloat(cos(angleRad)) * numRadius
                    let yPos = center.y + CGFloat(sin(angleRad)) * numRadius

                    Text(String(format: "%02d", slotValue))
                        .font(.system(
                            size: isSelected ? 21 : 15,
                            weight: isSelected ? .bold : .medium,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .foregroundStyle(
                            isSelected
                                ? Color.orange
                                : Color(red: 0.22, green: 0.22, blue: 0.25).opacity(max(0.28, 0.85 - Double(abs(delta)) * 0.18))
                        )
                        .padding(.horizontal, isSelected ? 6 : 0)
                        .padding(.vertical, isSelected ? 2 : 0)
                        .background(
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.orange.opacity(0.14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.orange, lineWidth: 1.2)
                                        )
                                }
                            }
                        )
                        .position(x: xPos, y: yPos)
                        .onTapGesture {
                            guard delta != 0 else { return }
                            emitDialTick(slotValue)
                        }
                }

                // 3. Inner Hub Label near the screen edge
                VStack(spacing: 2) {
                    Image(systemName: side == .left ? "arrow.up.and.down.circle.fill" : "arrow.up.and.down.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    Text(unitTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .position(
                    x: side == .left ? radius * 0.23 : w - radius * 0.23,
                    y: h / 2
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        if dragStartValue == nil {
                            dragStartValue = value
                        }
                        let base = dragStartValue ?? value
                        let stepHeight: CGFloat = 24
                        let steps = Int((-gesture.translation.height / stepHeight).rounded())
                        let candidate = wrapped(base + steps)
                        dragVisualFraction = (gesture.translation.height / stepHeight).truncatingRemainder(dividingBy: 1.0)
                        if candidate != value {
                            emitDialTick(candidate)
                        }
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
                            dragVisualFraction = 0
                        }
                    }
            )
        }
    }

    private func wrapped(_ raw: Int) -> Int {
        ((raw % modulo) + modulo) % modulo
    }

    private func emitDialTick(_ newValue: Int) {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        onChange(newValue)
    }
}
