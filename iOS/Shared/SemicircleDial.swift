import SwiftUI
import UIKit

/// Which screen edge a `SemicircleDial` is attached to.
public enum SemicircleDialEdge: Sendable {
    case left
    case right
}

/// A half-disc rotary dial anchored to a screen edge, used for picking the hour (0...23)
/// or the minute (0...59) of the alarm time. The dial is rotated by dragging a finger
/// along its curved edge; a fixed orange notch near the center always marks the active value.
public struct SemicircleDial: View {
    public let edge: SemicircleDialEdge
    public let value: Int
    /// Number of discrete values on the dial (24 for hours, 60 for minutes).
    public let valueCount: Int
    /// Spacing, in value units, between numerals shown on the dial face (1 for hours, 5 for minutes).
    public let majorStep: Int
    public let unitLabel: String
    public let onChange: (Int) -> Void

    @State private var dragStartAngle: Double?
    @State private var dragStartValue: Int?

    public init(
        edge: SemicircleDialEdge,
        value: Int,
        valueCount: Int,
        majorStep: Int,
        unitLabel: String,
        onChange: @escaping (Int) -> Void
    ) {
        self.edge = edge
        self.value = value
        self.valueCount = valueCount
        self.majorStep = majorStep
        self.unitLabel = unitLabel
        self.onChange = onChange
    }

    /// The fixed angle, in degrees, where the index notch points toward the screen center.
    private var notchAngleDegrees: Double {
        edge == .left ? 0.0 : 180.0
    }

    private var stepAngleDegrees: Double {
        360.0 / Double(valueCount)
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = DialMetrics(size: geo.size, edge: edge)
            ZStack {
                DialFacePlate(metrics: metrics)
                DialTickMarks(metrics: metrics, valueCount: valueCount, majorStep: majorStep)
                DialIndexNotch(metrics: metrics, angleDegrees: notchAngleDegrees)
                DialNumerals(
                    metrics: metrics,
                    value: value,
                    valueCount: valueCount,
                    majorStep: majorStep,
                    notchAngleDegrees: notchAngleDegrees,
                    stepAngleDegrees: stepAngleDegrees
                ) { tappedValue in
                    emitChange(to: tappedValue)
                }
                DialUnitLabel(metrics: metrics, unitLabel: unitLabel)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture(center: metrics.center))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unitLabel)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                emitChange(to: wrapped(value + 1))
            case .decrement:
                emitChange(to: wrapped(value - 1))
            default:
                break
            }
        }
    }

    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                let angle = angleDegrees(from: center, to: gesture.location)
                if dragStartAngle == nil {
                    dragStartAngle = angle
                    dragStartValue = value
                }
                guard let startAngle = dragStartAngle, let startValue = dragStartValue else { return }
                let delta = normalizedAngleDelta(angle - startAngle)
                let steps = Int((delta / stepAngleDegrees).rounded())
                let candidate = wrapped(startValue + steps)
                if candidate != value {
                    emitChange(to: candidate)
                }
            }
            .onEnded { _ in
                dragStartAngle = nil
                dragStartValue = nil
            }
    }

    private func angleDegrees(from center: CGPoint, to point: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        return atan2(dy, dx) * 180.0 / .pi
    }

    /// Normalizes an angle difference into the range `-180...180` so rotation direction stays stable across the wraparound boundary.
    private func normalizedAngleDelta(_ raw: Double) -> Double {
        let radians = raw * .pi / 180.0
        return atan2(sin(radians), cos(radians)) * 180.0 / .pi
    }

    private func wrapped(_ raw: Int) -> Int {
        ((raw % valueCount) + valueCount) % valueCount
    }

    private func emitChange(to newValue: Int) {
        guard newValue != value else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        onChange(newValue)
    }
}

// MARK: - Shared Geometry

private struct DialMetrics {
    let center: CGPoint
    let radius: CGFloat
    let edge: SemicircleDialEdge

    init(size: CGSize, edge: SemicircleDialEdge) {
        self.edge = edge
        let radius = min(size.width * 1.05, size.height * 0.52)
        self.radius = radius
        self.center = CGPoint(
            x: edge == .left ? 0 : size.width,
            y: size.height / 2
        )
    }

    func point(angleDegrees: Double, radiusFraction: CGFloat) -> CGPoint {
        let rad = angleDegrees * .pi / 180.0
        let r = radius * radiusFraction
        return CGPoint(
            x: center.x + CGFloat(cos(rad)) * r,
            y: center.y + CGFloat(sin(rad)) * r
        )
    }
}

// MARK: - Face Plate

private struct DialFacePlate: View {
    let metrics: DialMetrics

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.dialMetalLight, Color.dialMetalDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: metrics.radius * 2, height: metrics.radius * 2)
            .overlay(
                Circle().stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 7, x: metrics.edge == .left ? 2 : -2, y: 2)
            .position(metrics.center)
    }
}

// MARK: - Tick Marks

private struct DialTickMarks: View {
    let metrics: DialMetrics
    let valueCount: Int
    let majorStep: Int

    var body: some View {
        Canvas { context, _ in
            for i in 0..<valueCount {
                let angle = Double(i) * (360.0 / Double(valueCount))
                let isMajor = i % majorStep == 0
                let innerFraction: CGFloat = isMajor ? 0.80 : 0.86
                let p1 = metrics.point(angleDegrees: angle, radiusFraction: innerFraction)
                let p2 = metrics.point(angleDegrees: angle, radiusFraction: 0.92)
                var tick = Path()
                tick.move(to: p1)
                tick.addLine(to: p2)
                context.stroke(
                    tick,
                    with: .color(isMajor ? Color.dialInk.opacity(0.55) : Color.dialInk.opacity(0.22)),
                    lineWidth: isMajor ? 1.4 : 0.8
                )
            }
        }
    }
}

// MARK: - Fixed Index Notch

private struct DialIndexNotch: View {
    let metrics: DialMetrics
    let angleDegrees: Double

    var body: some View {
        Canvas { context, _ in
            let inner = metrics.point(angleDegrees: angleDegrees, radiusFraction: 0.30)
            let outer = metrics.point(angleDegrees: angleDegrees, radiusFraction: 0.78)
            var needle = Path()
            needle.move(to: inner)
            needle.addLine(to: outer)
            context.stroke(needle, with: .color(.vibeAccent), lineWidth: 2.5)

            let tipCenter = metrics.point(angleDegrees: angleDegrees, radiusFraction: 0.78)
            let tipRect = CGRect(x: tipCenter.x - 3, y: tipCenter.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: tipRect), with: .color(.vibeAccent))
        }
    }
}

// MARK: - Rotating Numerals

private struct DialNumerals: View {
    let metrics: DialMetrics
    let value: Int
    let valueCount: Int
    let majorStep: Int
    let notchAngleDegrees: Double
    let stepAngleDegrees: Double
    let onTapValue: (Int) -> Void

    private var nearestMajorValue: Int {
        (value / majorStep) * majorStep
    }

    var body: some View {
        ForEach(-3...3, id: \.self) { slot in
            let slotValue = wrapped(nearestMajorValue + slot * majorStep)
            let isSelected = slotValue == value
            let angle = notchAngleDegrees + Double(slotValue - value) * stepAngleDegrees
            let position = metrics.point(angleDegrees: angle, radiusFraction: 0.62)

            Text(String(format: "%02d", slotValue))
                .font(.system(size: isSelected ? 20 : 14, weight: isSelected ? .semibold : .regular, design: .default))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.vibeAccent : Color.dialInk.opacity(0.7))
                .position(position)
                .onTapGesture {
                    onTapValue(slotValue)
                }
        }
    }

    private func wrapped(_ raw: Int) -> Int {
        ((raw % valueCount) + valueCount) % valueCount
    }
}

// MARK: - Unit Label Near The Screen Edge

private struct DialUnitLabel: View {
    let metrics: DialMetrics
    let unitLabel: String

    var body: some View {
        Text(unitLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .position(metrics.point(angleDegrees: metrics.edge == .left ? 0 : 180, radiusFraction: 0.18))
    }
}
