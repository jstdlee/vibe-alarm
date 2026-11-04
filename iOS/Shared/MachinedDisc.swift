import SwiftUI
import UIKit

/// One large machined disc for choosing a number: the hour, the minute, anything countable.
///
/// The disc is a matte volume lit from above. It casts a soft shadow down into the paper and
/// catches a thin highlight along its top edge. Its face carries two machined grooves, a fine
/// tick skirt and a ring of engraved numerals that turn with the rim. The numeral for the current
/// value is printed in amber and sits on a ray running out from a recessed well, so one reading
/// line runs from the rim to the centre of the disc.
///
/// Two of these hang over the left and right bottom corners of the wake time editor, each mostly
/// off screen, so a pair of three-hundred-point discs shares one phone without crowding. The
/// wells face the middle of the screen, a thumb's width from either bezel.
///
/// Turning it feels heavy: every step clicks a selection haptic and the rim settles on a spring
/// with a small overshoot instead of snapping.
public struct MachinedDisc: View {
    /// Number of discrete values (24 for hours, 60 for minutes).
    public let valueCount: Int
    /// Interval between engraved numerals on the rim (1 for hours, 5 for minutes).
    public let majorStep: Int
    /// Caption inside the read well, e.g. "HOUR".
    public let unitLabel: String
    public let diameter: CGFloat
    public let value: Int
    /// Direction of the read well from the disc centre, in degrees, where 0 is three o'clock and
    /// negative values point above the horizontal.
    public let wellAngleDegrees: Double
    /// Distance of the well's centre from the disc centre, as a fraction of the radius. Kept
    /// separate from the angle so the pair can push the well toward the middle of the screen
    /// while the numerals stay out at the rim.
    public let wellRadiusFraction: CGFloat
    public let onChange: (Int) -> Void

    @State private var dragStartAngle: Double?
    @State private var dragStartValue: Int

    public init(
        value: Int,
        valueCount: Int,
        majorStep: Int = 1,
        unitLabel: String,
        diameter: CGFloat,
        wellAngleDegrees: Double,
        wellRadiusFraction: CGFloat = 0.44,
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
    private var stepDegrees: Double { 360.0 / Double(valueCount) }

    public var body: some View {
        ZStack {
            discBody
            grooves
            tickSkirt
            numeralRing
            readWell
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(turnGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unitLabel.capitalized)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: emit(wrapped(value + 1))
            case .decrement: emit(wrapped(value - 1))
            default: break
            }
        }
    }

    // MARK: - Volume

    private var discBody: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [VibePalette.paperRaised, VibePalette.paperDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(Circle().strokeBorder(VibePalette.hairline.opacity(0.5), lineWidth: 0.7))
            .shadow(color: VibePalette.shadow.opacity(0.17), radius: 16, x: 0, y: 8)
            .shadow(color: Color.white.opacity(0.9), radius: 1.6, x: 0, y: -1.6)
    }

    /// Two machined grooves. Each is a dark hairline with a light one just inside it, so it reads
    /// as a cut in the face rather than a stroke laid on top of it.
    private var grooves: some View {
        ZStack {
            Circle()
                .strokeBorder(VibePalette.hairline.opacity(0.7), lineWidth: 0.9)
                .frame(width: diameter * 0.9)
            Circle()
                .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.9)
                .frame(width: diameter * 0.9 - 2.4)
            Circle()
                .strokeBorder(VibePalette.hairline.opacity(0.26), lineWidth: 0.7)
                .frame(width: diameter * 0.64)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Rim

    /// Fine ticks just inside the outer edge, one per value, longer at every major step.
    private var tickSkirt: some View {
        Canvas { context, _ in
            let step = 360.0 / Double(valueCount)
            for index in 0..<valueCount {
                let isMajor = index % majorStep == 0
                let rad = (Double(index) * step - 90.0) * .pi / 180.0
                var path = Path()
                path.move(to: point(rad: rad, r: radius * (isMajor ? 0.868 : 0.9)))
                path.addLine(to: point(rad: rad, r: radius * 0.952))
                context.stroke(
                    path,
                    with: .color(VibePalette.hairline.opacity(isMajor ? 0.8 : 0.38)),
                    lineWidth: isMajor ? 1.1 : 0.7
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    /// The engraved numerals turn with the face, each one counter-rotated to stay upright. The
    /// current value is printed in amber at the end of the reading ray.
    private var numeralRing: some View {
        let count = max(1, valueCount / majorStep)
        let ringRotation = wellAngleDegrees + 90.0 - Double(value) * stepDegrees
        return ZStack {
            ForEach(0..<count, id: \.self) { slot in
                let raw = slot * majorStep
                Text(String(format: "%02d", raw))
                    .font(.system(size: raw == value ? numeralSize * 1.3 : numeralSize,
                                  weight: raw == value ? .medium : .regular))
                    .monospacedDigit()
                    .foregroundStyle(raw == value ? VibePalette.amber : VibePalette.ink.opacity(0.4))
                    // Rotate before positioning: the text turns about its own centre, then the
                    // ring's rotation cancels it so every numeral stays upright.
                    .rotationEffect(.degrees(-ringRotation))
                    .position(point(rad: (Double(raw) * stepDegrees - 90.0) * .pi / 180.0,
                                    r: radius * 0.76))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(ringRotation))
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: value)
    }

    private var numeralSize: CGFloat {
        max(11, diameter * 0.043)
    }

    /// The reading well is a circle of its own, sized against the radius so it keeps the same
    /// proportion on a phone and on a small phone.
    private var wellSize: CGFloat {
        radius * 0.40
    }

    // MARK: - Read Well

    /// The reading ray: a hairline cut inward from the scale, and the value on a recessed well
    /// at its inner end. The ray replaces the usual fixed pointer notch because the disc itself
    /// is a window: the notch would be off screen with the rest of the near half.
    private var readWell: some View {
        let rad = wellAngleDegrees * .pi / 180.0
        return ZStack {
            Capsule()
                .fill(VibePalette.hairline.opacity(0.75))
                .frame(width: 1.1, height: radius * 0.26)
                .rotationEffect(.degrees(wellAngleDegrees + 90))
                .position(point(rad: rad, r: radius * 0.63))

            VStack(spacing: 0) {
                Text(String(format: "%02d", value))
                    .font(.system(size: wellSize * 0.46, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(VibePalette.ink)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.easeOut(duration: 0.12), value: value)
                Text(unitLabel.uppercased())
                    .vibeCaption()
                    .padding(.top, 1)
            }
            .frame(width: wellSize, height: wellSize)
            .recessedWell(corner: wellSize / 2)
            .position(point(rad: rad, r: radius * wellRadiusFraction))
        }
        .allowsHitTesting(false)
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
        CGPoint(x: diameter / 2 + CGFloat(cos(rad)) * r, y: diameter / 2 + CGFloat(sin(rad)) * r)
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

/// The two big discs of the wake time editor.
///
/// Each disc is anchored to a screen edge and is as wide as the display, so roughly half of it is
/// on screen and the rest runs under the bezel. There is no outline where it ends, only the rim's
/// shadow falling off the edge, which is what makes it read as one large volume set into the
/// phone rather than a circle drawn on it. The reading wells are turned inward so the hour and
/// the minute both sit where a thumb already is, and the numerals are printed on the visible half
/// of the rim, so turning a disc sweeps numbers past the well the way a real knob does.
public struct DiscPair: View {
    public let diameter: CGFloat
    /// Clear space left between the two rims at the middle of the screen.
    public let gap: CGFloat
    public let leadingValue: Int
    public let leadingCount: Int
    public let leadingStep: Int
    public let leadingLabel: String
    public let trailingValue: Int
    public let trailingCount: Int
    public let trailingStep: Int
    public let trailingLabel: String
    public let onLeadingChange: (Int) -> Void
    public let onTrailingChange: (Int) -> Void

    public init(
        diameter: CGFloat,
        gap: CGFloat = 22,
        leadingValue: Int,
        leadingCount: Int,
        leadingStep: Int = 1,
        leadingLabel: String,
        trailingValue: Int,
        trailingCount: Int,
        trailingStep: Int = 5,
        trailingLabel: String,
        onLeadingChange: @escaping (Int) -> Void,
        onTrailingChange: @escaping (Int) -> Void
    ) {
        self.diameter = diameter
        self.gap = gap
        self.leadingValue = leadingValue
        self.leadingCount = leadingCount
        self.leadingStep = leadingStep
        self.leadingLabel = leadingLabel
        self.trailingValue = trailingValue
        self.trailingCount = trailingCount
        self.trailingStep = trailingStep
        self.trailingLabel = trailingLabel
        self.onLeadingChange = onLeadingChange
        self.onTrailingChange = onTrailingChange
    }

    public var body: some View {
        GeometryReader { geo in
            // Half the display's spare width, after the gap, is how much of each disc is on
            // screen. The centre then sits that far in from outside the bezel.
            let cap = max(1, (geo.size.width - gap) / 2)
            let centreInset = cap - diameter / 2

            ZStack(alignment: .topLeading) {
                MachinedDisc(
                    value: leadingValue,
                    valueCount: leadingCount,
                    majorStep: leadingStep,
                    unitLabel: leadingLabel,
                    diameter: diameter,
                    wellAngleDegrees: -22,
                    wellRadiusFraction: 0.50,
                    onChange: onLeadingChange
                )
                .position(x: centreInset, y: diameter / 2)

                MachinedDisc(
                    value: trailingValue,
                    valueCount: trailingCount,
                    majorStep: trailingStep,
                    unitLabel: trailingLabel,
                    diameter: diameter,
                    wellAngleDegrees: -158,
                    wellRadiusFraction: 0.50,
                    onChange: onTrailingChange
                )
                .position(x: geo.size.width - centreInset, y: diameter / 2)
            }
            .frame(width: geo.size.width, height: diameter, alignment: .topLeading)
        }
        .frame(height: diameter)
    }
}
