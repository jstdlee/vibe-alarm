import SwiftUI
import UIKit

/// Shared geometry for the blank dial plate and the scale drawn on top of it.
///
/// `ringInner` matches `RING_INNER` in `scripts/make-dial-plates.py`. The plate
/// bitmap is a square whose circle fills the frame. Ticks, numerals, and the
/// reading well are placed from the same centre, so they stay registered to
/// the brass ring. The bitmap has no ticks and no numerals.
enum BedsidePlateMetrics {
    static let ringInner: CGFloat = 0.818
    static let tickOuter: CGFloat = 0.792
    static let tickInnerMinor: CGFloat = 0.758
    static let tickInnerMajor: CGFloat = 0.722
    static let numeralRadius: CGFloat = 0.70
}

enum BedsideDialColor {
    static func accent(scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        if scheme == .dark {
            return contrast == .increased
                ? Color(red: 1.0, green: 0.91, blue: 0.72)
                : Color(red: 0.93, green: 0.76, blue: 0.48)
        }
        return contrast == .increased
            ? Color(red: 0.52, green: 0.26, blue: 0.06)
            : Color(red: 0.80, green: 0.46, blue: 0.16)
    }
}

/// One rotary disc for the bedside wake editor.
///
/// The face, brass ring, glass, and center cap come from a blank plate image.
/// Every tick and numeral is drawn here, at a true angle, and turns with the
/// value so the current number sits on the reading well. Dragging around the
/// disc steps the value. VoiceOver changes it with the adjustable action.
struct BedsideDisc: View {
    let valueCount: Int
    let majorStep: Int
    let unitLabel: String
    let diameter: CGFloat
    /// Direction of the reading well. 0 is three o'clock; negative is above the horizontal.
    let wellAngleDegrees: Double
    /// Distance of the well centre from the disc centre, as a fraction of the radius.
    let wellRadiusFraction: CGFloat
    let value: Int
    let onChange: (Int) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var numeralMetric: CGFloat = 13
    @ScaledMetric(relativeTo: .title2) private var wellMetric: CGFloat = 28

    @State private var dragStartAngle: Double?
    @State private var dragStartValue: Int

    init(
        value: Int,
        valueCount: Int,
        majorStep: Int,
        unitLabel: String,
        diameter: CGFloat,
        wellAngleDegrees: Double,
        wellRadiusFraction: CGFloat,
        onChange: @escaping (Int) -> Void
    ) {
        self.value = value
        self.valueCount = valueCount
        self.majorStep = max(1, majorStep)
        self.unitLabel = unitLabel
        self.diameter = diameter
        self.wellAngleDegrees = wellAngleDegrees
        self.wellRadiusFraction = wellRadiusFraction
        self.onChange = onChange
        _dragStartValue = State(initialValue: value)
    }

    private var radius: CGFloat { diameter / 2 }
    private var stepDegrees: Double { 360.0 / Double(max(valueCount, 1)) }
    private var accent: Color { BedsideDialColor.accent(scheme: scheme, contrast: contrast) }
    private var dark: Bool { scheme == .dark }
    private var settle: Animation? {
        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.72)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(dark ? 0.45 : 0.14))
                .frame(width: diameter * 0.92, height: diameter * 0.92)
                .blur(radius: diameter * 0.035)
                .offset(y: diameter * 0.02)
                .accessibilityHidden(true)

            plate
            rotatingScale
            readWell
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(turnGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unitLabel)
        .accessibilityValue(String(format: "%02d", value))
        .accessibilityHint("Swipe up or down to change.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: emit(wrapped(value + 1))
            case .decrement: emit(wrapped(value - 1))
            default: break
            }
        }
    }

    // MARK: - Plate

    /// The plate is a loose bundle image, not an asset catalog, so the app does not
    /// need an AppIcon set. `UIImage(named:)` finds `BedsideDialPlateLight.png`.
    private var plate: some View {
        let name = dark ? "BedsideDialPlateDark" : "BedsideDialPlateLight"
        return Group {
            if let image = UIImage(named: name) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Circle().fill(dark ? Color(white: 0.1) : Color(red: 0.95, green: 0.93, blue: 0.90))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - Scale

    /// Ticks and numerals share one rotation, so each numeral stays on its tick.
    /// Value 0 is drawn at 12 o'clock and the rotation carries the current value
    /// to the reading well.
    private var rotatingScale: some View {
        let ringRotation = wellAngleDegrees + 90.0 - Double(value) * stepDegrees
        return ZStack {
            tickSkirt
            numeralRing(counterRotation: ringRotation)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(ringRotation))
        .animation(settle, value: value)
        .allowsHitTesting(false)
    }

    private var tickSkirt: some View {
        Canvas { context, _ in
            let step = stepDegrees
            for index in 0..<valueCount {
                let isMajor = index % majorStep == 0
                let rad = (Double(index) * step - 90.0) * .pi / 180.0
                let inner = radius * (isMajor ? BedsidePlateMetrics.tickInnerMajor : BedsidePlateMetrics.tickInnerMinor)
                var path = Path()
                path.move(to: point(rad: rad, r: inner))
                path.addLine(to: point(rad: rad, r: radius * BedsidePlateMetrics.tickOuter))
                let color = isMajor ? tickMajor : tickMinor
                context.stroke(path, with: .color(color), lineWidth: isMajor ? 1.15 : 0.7)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func numeralRing(counterRotation: Double) -> some View {
        let count = max(1, valueCount / majorStep)
        let size = numeralSize
        return ZStack {
            ForEach(0..<count, id: \.self) { slot in
                let raw = slot * majorStep
                let selected = raw == value
                Text(String(format: "%02d", raw))
                    .font(.system(size: selected ? size * 1.28 : size, weight: selected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(selected ? accent : numeralColor)
                    .rotationEffect(.degrees(-counterRotation))
                    .position(
                        point(
                            rad: (Double(raw) * stepDegrees - 90.0) * .pi / 180.0,
                            r: radius * BedsidePlateMetrics.numeralRadius
                        )
                    )
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var numeralSize: CGFloat {
        let cap = diameter * (contrast == .increased ? 0.046 : 0.040)
        return min(max(11, numeralMetric), cap)
    }

    // MARK: - Reading well

    private var wellSize: CGFloat {
        min(radius * 0.30, 72)
    }

    private var readWell: some View {
        let rad = wellAngleDegrees * .pi / 180.0
        let digit = min(wellMetric, wellSize * 0.46)
        return ZStack {
            Capsule()
                .fill(accent.opacity(contrast == .increased ? 0.9 : 0.55))
                .frame(width: 1.1, height: radius * 0.12)
                .rotationEffect(.degrees(wellAngleDegrees + 90))
                .position(point(rad: rad, r: radius * (wellRadiusFraction + 0.14)))

            VStack(spacing: 0) {
                Text(String(format: "%02d", value))
                    .font(.system(size: digit, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(wellInk)
                    .contentTransition(.numericText(value: Double(value)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unitLabel.uppercased())
                    .font(.system(size: max(8, wellSize * 0.14), weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(wellCaption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: wellSize, height: wellSize)
            .background {
                Circle()
                    .fill(wellFill.shadow(.inner(color: Color.black.opacity(dark ? 0.55 : 0.18), radius: 5, y: 2)))
                    .overlay(
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(dark ? 0.16 : 0.7),
                                    Color.black.opacity(dark ? 0.35 : 0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                    )
            }
            .position(point(rad: rad, r: radius * wellRadiusFraction))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Ink

    private var numeralColor: Color {
        if dark {
            return Color(red: 0.93, green: 0.89, blue: 0.80).opacity(contrast == .increased ? 0.95 : 0.72)
        }
        return Color(red: 0.22, green: 0.17, blue: 0.12).opacity(contrast == .increased ? 0.9 : 0.55)
    }

    private var tickMajor: Color {
        dark
            ? Color(red: 0.86, green: 0.74, blue: 0.50).opacity(contrast == .increased ? 0.95 : 0.75)
            : Color(red: 0.28, green: 0.22, blue: 0.14).opacity(contrast == .increased ? 0.85 : 0.45)
    }

    private var tickMinor: Color {
        tickMajor.opacity(contrast == .increased ? 0.7 : 0.55)
    }

    private var wellFill: Color {
        dark
            ? Color(red: 0.06, green: 0.055, blue: 0.05)
            : Color(red: 0.90, green: 0.875, blue: 0.835)
    }

    private var wellInk: Color {
        dark ? Color(red: 0.96, green: 0.93, blue: 0.86) : Color(red: 0.16, green: 0.13, blue: 0.10)
    }

    private var wellCaption: Color {
        dark
            ? Color(red: 0.82, green: 0.76, blue: 0.64)
            : Color(red: 0.40, green: 0.34, blue: 0.26)
    }

    // MARK: - Turning

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                guard diameter > 0 else { return }
                let angle = atan2(
                    Double(gesture.location.y - diameter / 2),
                    Double(gesture.location.x - diameter / 2)
                ) * 180.0 / .pi
                if dragStartAngle == nil {
                    dragStartAngle = angle
                    dragStartValue = value
                }
                guard let startAngle = dragStartAngle else { return }
                let steps = Int((-normalizedDelta(angle - startAngle) / stepDegrees).rounded())
                let candidate = wrapped(dragStartValue + steps)
                if candidate != value {
                    emit(candidate)
                }
            }
            .onEnded { _ in
                dragStartAngle = nil
                dragStartValue = value
            }
    }

    private func point(rad: Double, r: CGFloat) -> CGPoint {
        CGPoint(
            x: diameter / 2 + CGFloat(cos(rad)) * r,
            y: diameter / 2 + CGFloat(sin(rad)) * r
        )
    }

    private func normalizedDelta(_ raw: Double) -> Double {
        let radians = raw * .pi / 180.0
        return atan2(sin(radians), cos(radians)) * 180.0 / .pi
    }

    private func wrapped(_ raw: Int) -> Int {
        guard valueCount > 0 else { return 0 }
        return ((raw % valueCount) + valueCount) % valueCount
    }

    private func emit(_ newValue: Int) {
        guard newValue != value else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onChange(newValue)
    }
}

/// Hour disc on the left, minute disc on the right.
///
/// The discs are wider than the phone. Each centre sits past the bezel, so the
/// lower half runs off the bottom and the upper half fills the space under the
/// wake options. Reading wells stay on the visible inner face.
struct BedsideDiscPair: View {
    let diameter: CGFloat
    var gap: CGFloat = 16
    let hour: Int
    let minute: Int
    let onHourChange: (Int) -> Void
    let onMinuteChange: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let radius = diameter / 2
            let cap = max(1, (geo.size.width - gap) / 2)
            let centreInset = cap - radius
            let left = wellPlacement(centerX: centreInset, targetX: geo.size.width * 0.27, radius: radius)
            let right = wellPlacement(centerX: geo.size.width - centreInset, targetX: geo.size.width * 0.73, radius: radius)
            ZStack(alignment: .topLeading) {
                BedsideDisc(
                    value: hour,
                    valueCount: 24,
                    majorStep: 1,
                    unitLabel: "Hour",
                    diameter: diameter,
                    wellAngleDegrees: left.angle,
                    wellRadiusFraction: left.fraction,
                    onChange: onHourChange
                )
                .position(x: centreInset, y: diameter / 2)

                BedsideDisc(
                    value: minute,
                    valueCount: 60,
                    majorStep: 5,
                    unitLabel: "Min",
                    diameter: diameter,
                    wellAngleDegrees: right.angle,
                    wellRadiusFraction: right.fraction,
                    onChange: onMinuteChange
                )
                .position(x: geo.size.width - centreInset, y: diameter / 2)
            }
            .frame(width: geo.size.width, height: diameter, alignment: .topLeading)
        }
        .frame(height: diameter)
    }

    /// Aims the well at a point on the visible face, then keeps it inside the numeral ring.
    private func wellPlacement(centerX: CGFloat, targetX: CGFloat, radius: CGFloat) -> (angle: Double, fraction: CGFloat) {
        let dx = targetX - centerX
        let dy = -radius * 0.20
        let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
        let needed = hypot(dx, dy) / max(radius, 1)
        let fraction = min(0.50, max(0.36, needed))
        return (angle, fraction)
    }
}
