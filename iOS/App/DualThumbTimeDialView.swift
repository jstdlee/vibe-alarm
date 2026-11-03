import SwiftUI
import UIKit
import VibeAlarmCore

/// Screen 2 ("Time Dial"): Ergonomic Braun/Apple Light Theme dual-thumb time picker.
/// - **Top card**: digital readout + `Active` toggle, plus horizontal mechanical rollers for
///   repeat mode and holiday policy.
/// - **Lower thumb zone**: left (`HOUR`) and right (`MIN`) semi-circular rotary dials anchored
///   to the screen edges, with a center quick-snap column.
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
                .navigationTitle(isEmbeddedInTab ? "" : "Time Dial")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(isEmbeddedInTab)
                .toolbar {
                    if !isEmbeddedInTab {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                dismiss()
                            }
                            .foregroundStyle(.vibeAccent)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(.vibeAccent)
                        }
                    }
                }
        }
        .tint(.vibeAccent)
        .preferredColorScheme(.light)
    }
}

public struct DualThumbTimeDialView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newSpecificDate: Date = Date()

    private let repeatOptions: [String] = [
        "Workdays", "Every Day", "Custom", "Dates"
    ]

    private let holidayPolicyOptions: [String] = [
        "Skip All", "Holidays", "PTO Only", "Manual"
    ]

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                topReadoutAndRollersCard

                if case .customDays(let selectedDays) = viewModel.snapshot.alarmRule.repeatMode {
                    customWeekdaysBar(selectedDays: selectedDays)
                } else if case .specificDates(let dates) = viewModel.snapshot.alarmRule.repeatMode {
                    specificDatesBar(dates: dates)
                }

                semiCircularRotaryDialsCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .background(Color.vibeCanvas)
    }

    // MARK: - 1. Top Digital Readout & Horizontal Rollers Card

    private var topReadoutAndRollersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WAKE ALARM")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Active", isOn: Binding(
                    get: { viewModel.snapshot.alarmRule.isEnabled },
                    set: { val in viewModel.updateAlarmRule { $0.isEnabled = val } }
                ))
                .labelsHidden()
                .tint(.vibeAccent)
                Text("Active")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(viewModel.snapshot.alarmRule.formattedBaseTime)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(repeatShortLabel) · \(holidayShortLabel)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .systemGray6))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }

            VStack(spacing: 10) {
                SkeuomorphicHorizontalRoller(
                    title: "REPEAT",
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

                SkeuomorphicHorizontalRoller(
                    title: "HOLIDAYS",
                    options: holidayPolicyOptions,
                    selectedIndex: holidayPolicyIndex
                ) { newIndex in
                    switch newIndex {
                    case 0:
                        viewModel.updateAlarmRule {
                            $0.skipPublicHolidays = true
                            $0.skipPersonalLeave = true
                        }
                    case 1:
                        viewModel.updateAlarmRule {
                            $0.skipPublicHolidays = true
                            $0.skipPersonalLeave = false
                        }
                    case 2:
                        viewModel.updateAlarmRule {
                            $0.skipPublicHolidays = false
                            $0.skipPersonalLeave = true
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
        }
        .padding(16)
        .vibeCard()
    }

    private var repeatShortLabel: String {
        repeatOptions[repeatModeIndex]
    }

    private var holidayShortLabel: String {
        holidayPolicyOptions[holidayPolicyIndex]
    }

    // MARK: - 2. Lower Thumb Zone: Semi-Circular Rotary Dials

    private var semiCircularRotaryDialsCard: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let totalH = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.vibeAluminumLight, Color.vibeAluminumDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                // LEFT SEMI-CIRCULAR DIAL (Hour 00-23, anchored on left edge)
                SemiCircularSkeuomorphicDial(
                    side: .left,
                    value: viewModel.snapshot.alarmRule.hour,
                    modulo: 24,
                    tickCount: 72,
                    unitTitle: "HOUR"
                ) { newHour in
                    viewModel.updateAlarmTime(
                        hour: newHour,
                        minute: viewModel.snapshot.alarmRule.minute
                    )
                }
                .frame(width: totalW * 0.44, height: totalH)
                .position(x: totalW * 0.22, y: totalH / 2)

                // RIGHT SEMI-CIRCULAR DIAL (Minute 00-59, anchored on right edge)
                SemiCircularSkeuomorphicDial(
                    side: .right,
                    value: viewModel.snapshot.alarmRule.minute,
                    modulo: 60,
                    tickCount: 60,
                    unitTitle: "MIN"
                ) { newMinute in
                    viewModel.updateAlarmTime(
                        hour: viewModel.snapshot.alarmRule.hour,
                        minute: newMinute
                    )
                }
                .frame(width: totalW * 0.44, height: totalH)
                .position(x: totalW * 0.78, y: totalH / 2)

                // CENTER QUICK-SNAP COLUMN
                VStack(spacing: 8) {
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
                                .frame(width: 52, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isCurrent ? Color.vibeAccent : Color.white)
                                        .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                                )
                                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
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
                            .foregroundStyle(.vibeAccent)
                            .frame(width: 52, height: 24)
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
        .frame(height: 290)
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
                        .background(active ? Color.vibeAccent : Color(uiColor: .systemGray6))
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .vibeCard()
    }

    private func specificDatesBar(dates: Set<String>) -> some View {
        HStack {
            DatePicker("Pick a Date", selection: $newSpecificDate, displayedComponents: .date)
                .font(.subheadline)
                .labelsHidden()
            Spacer()
            Button("Add Date") {
                let dStr = AlarmScheduleEngine().dateString(from: newSpecificDate)
                var next = dates
                next.insert(dStr)
                viewModel.updateAlarmRule { $0.repeatMode = .specificDates(next) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.vibeAccent)
        }
        .padding(10)
        .vibeCard()
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
            return 0
        } else if rule.skipPublicHolidays && !rule.skipPersonalLeave {
            return 1
        } else if !rule.skipPublicHolidays && rule.skipPersonalLeave {
            return 2
        } else {
            return 3
        }
    }
}

// MARK: - Skeuomorphic Horizontal Roller Axis

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
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Machined aluminum barrel with vertical knurled groove ticks
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.vibeAluminumDark, Color.vibeAluminumLight, Color.vibeAluminumLight, Color.vibeAluminumDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    HStack(spacing: 6) {
                        ForEach(0..<36, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 1, height: h - 8)
                        }
                    }

                    // Prev / Current / Next option row — current highlighted in a white capsule
                    HStack(spacing: 10) {
                        optionLabel(delta: -1, w: w)
                        currentOptionCapsule
                        optionLabel(delta: 1, w: w)
                    }
                    .offset(x: dragVisualOffset * 0.2)

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

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.14), lineWidth: 1)
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
                            let stepWidth: CGFloat = 60
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
            .frame(height: 36)
        }
    }

    private var currentOptionCapsule: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.vibeAccent)
                .frame(width: 5, height: 5)
            Text(options[selectedIndex])
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.vibeInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        )
    }

    private func optionLabel(delta: Int, w: CGFloat) -> some View {
        let idx = wrappedIndex(selectedIndex + delta)
        return Text(options[idx])
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.secondary.opacity(0.6))
            .lineLimit(1)
            .frame(width: w * 0.22)
            .onTapGesture {
                emitRollerTick(idx)
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

// MARK: - Semi-Circular Skeuomorphic Rotary Dial

public enum SemiCircularDialSide {
    case left
    case right
}

public struct SemiCircularSkeuomorphicDial: View {
    public let side: SemiCircularDialSide
    public let value: Int
    public let modulo: Int
    public let tickCount: Int
    public let unitTitle: String
    public let onChange: (Int) -> Void

    @State private var dragStartValue: Int?
    @State private var dragVisualFraction: CGFloat = 0

    public init(
        side: SemiCircularDialSide,
        value: Int,
        modulo: Int,
        tickCount: Int,
        unitTitle: String,
        onChange: @escaping (Int) -> Void
    ) {
        self.side = side
        self.value = value
        self.modulo = modulo
        self.tickCount = tickCount
        self.unitTitle = unitTitle
        self.onChange = onChange
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = min(w * 0.96, h * 0.48)
            // Anchor the wheel center just outside the screen edge so its semi-circle protrudes inward.
            let center = CGPoint(
                x: side == .left ? -radius * 0.06 : w + radius * 0.06,
                y: h / 2
            )
            let baseAngleDeg: Double = side == .left ? 0.0 : 180.0

            ZStack {
                Canvas { context, _ in
                    let wheelRect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let wheelPath = Path(ellipseIn: wheelRect)

                    context.drawLayer { shadowCtx in
                        shadowCtx.addFilter(.shadow(color: .black.opacity(0.16), radius: 8, x: side == .left ? 3 : -3, y: 2))
                        shadowCtx.fill(wheelPath, with: .color(Color.vibeAluminumLight))
                    }

                    context.stroke(wheelPath, with: .color(Color.black.opacity(0.18)), lineWidth: 1.5)

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
                    let fractionalShift = Double(dragVisualFraction) * 6.0
                    for i in 0..<tickCount {
                        let deg = Double(i) * (360.0 / Double(tickCount)) + fractionalShift
                        let rad = deg * .pi / 180.0
                        let cosA = CGFloat(cos(rad))
                        let sinA = CGFloat(sin(rad))

                        let pOuter1 = CGPoint(x: center.x + cosA * (radius * 0.94), y: center.y + sinA * (radius * 0.94))
                        let pOuter2 = CGPoint(x: center.x + cosA * (radius * 0.99), y: center.y + sinA * (radius * 0.99))
                        var tooth = Path()
                        tooth.move(to: pOuter1)
                        tooth.addLine(to: pOuter2)
                        context.stroke(tooth, with: .color(Color.vibeInk.opacity(0.22)), lineWidth: 1.0)

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
                            with: .color(isMajor ? Color.vibeInkMuted : Color.black.opacity(0.18)),
                            lineWidth: isMajor ? 1.5 : 0.8
                        )
                    }

                    // Sharp Braun Orange horizontal index needle pointing to the active value
                    let needleInnerR = radius * 0.30
                    let needleOuterR = radius * 0.80
                    let needleRad = baseAngleDeg * .pi / 180.0
                    let nCos = CGFloat(cos(needleRad))
                    let nSin = CGFloat(sin(needleRad))
                    var needle = Path()
                    needle.move(to: CGPoint(x: center.x + nCos * needleInnerR, y: center.y + nSin * needleInnerR))
                    needle.addLine(to: CGPoint(x: center.x + nCos * needleOuterR, y: center.y + nSin * needleOuterR))
                    context.stroke(needle, with: .color(Color.vibeAccent), lineWidth: 2.5)
                    let tipRect = CGRect(
                        x: center.x + nCos * needleOuterR - 3,
                        y: center.y + nSin * needleOuterR - 3,
                        width: 6, height: 6
                    )
                    context.fill(Path(ellipseIn: tipRect), with: .color(Color.vibeAccent))

                    // Center recessed hub cap
                    let hubR = radius * 0.30
                    let hubRect = CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)
                    context.fill(Path(ellipseIn: hubRect), with: .color(Color.vibeAluminumDark))
                    context.stroke(Path(ellipseIn: hubRect), with: .color(Color.black.opacity(0.15)), lineWidth: 1)
                }

                // Upright rotating numerals along the inner arc (-3...+3 from the active value)
                ForEach([-3, -2, -1, 0, 1, 2, 3], id: \.self) { delta in
                    let slotValue = wrapped(value + delta)
                    let isSelected = delta == 0
                    let stepAngleDeg: Double = 23.0
                    let angleDeg: Double = side == .left
                        ? (baseAngleDeg + Double(delta) * stepAngleDeg)
                        : (baseAngleDeg - Double(delta) * stepAngleDeg)
                    let angleRad = angleDeg * .pi / 180.0

                    let numRadius = radius * 0.69
                    let xPos = center.x + CGFloat(cos(angleRad)) * numRadius
                    let yPos = center.y + CGFloat(sin(angleRad)) * numRadius

                    Text(String(format: "%02d", slotValue))
                        .font(.system(
                            size: isSelected ? 20 : 14,
                            weight: isSelected ? .bold : .medium,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .foregroundStyle(
                            isSelected
                                ? Color.vibeAccent
                                : Color.vibeInk.opacity(max(0.26, 0.82 - Double(abs(delta)) * 0.18))
                        )
                        .position(x: xPos, y: yPos)
                        .onTapGesture {
                            guard delta != 0 else { return }
                            emitDialTick(slotValue)
                        }
                }

                // Inner hub label near the screen edge
                VStack(spacing: 2) {
                    Text(unitTitle)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.primary)
                }
                .position(
                    x: side == .left ? radius * 0.20 : w - radius * 0.20,
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
