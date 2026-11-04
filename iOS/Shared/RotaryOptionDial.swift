import SwiftUI
import UIKit

/// A compact skeuomorphic rotary selector for a short, discrete list of labeled options
/// (for example Repeat, Holiday Rule or Snooze). It shares the visual language of
/// `SemicircleDial`: a brushed-metal face, engraved tick marks, a fixed accent index notch
/// at top center, and engraved option labels that rotate along a shallow arc so the active
/// option sits directly under the notch.
///
/// Interactions: drag the face to rotate it (with detents and `UISelectionFeedbackGenerator`
/// haptics on every step), or tap any visible neighbor label to jump to it. The selection is
/// clamped to the valid range (it does not wrap), which matches how these option lists read.
public struct RotaryOptionDial: View {
    public let options: [String]
    public let selectedIndex: Int
    public let accessibilityLabelText: String
    public let onSelect: (Int) -> Void

    @State private var dragStartAngle: Double?
    @State private var dragStartIndex: Int?

    /// Fixed angular spacing between adjacent options. Independent of the option count so that
    /// two-item lists (Holiday Rule) and five-item lists (Repeat) read with the same spacing and
    /// neighbor labels stay comfortably separated on a 6.1-inch screen.
    private let stepAngleDegrees: Double = 26

    public init(
        options: [String],
        selectedIndex: Int,
        accessibilityLabelText: String,
        onSelect: @escaping (Int) -> Void
    ) {
        self.options = options
        self.selectedIndex = options.isEmpty ? 0 : max(0, min(options.count - 1, selectedIndex))
        self.accessibilityLabelText = accessibilityLabelText
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = RotaryDialMetrics(size: geo.size)
            ZStack {
                facePlate
                tickMarks(metrics: metrics)
                indexNotch(metrics: metrics)
                optionLabels(metrics: metrics)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(dragGesture(center: metrics.center))
        }
        .frame(height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(options.indices.contains(selectedIndex) ? options[selectedIndex] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                commit(clamped(selectedIndex + 1))
            case .decrement:
                commit(clamped(selectedIndex - 1))
            default:
                break
            }
        }
    }

    // MARK: - Face

    private var facePlate: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.dialMetalLight, Color.dialMetalDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    // MARK: - Tick Marks

    private func tickMarks(metrics: RotaryDialMetrics) -> some View {
        Canvas { context, _ in
            // Half-step ticks across a fixed span give an engraved ruler texture; the full-step
            // ticks (major) line up with the option positions.
            for k in -8...8 {
                let angle = -90.0 + Double(k) * (stepAngleDegrees / 2.0)
                let isMajor = k % 2 == 0
                let outer = metrics.point(angleDegrees: angle, radius: metrics.tickRadius)
                let inner = metrics.point(
                    angleDegrees: angle,
                    radius: metrics.tickRadius + (isMajor ? 14 : 8)
                )
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                context.stroke(
                    tick,
                    with: .color(isMajor ? Color.dialInk.opacity(0.5) : Color.dialInk.opacity(0.2)),
                    lineWidth: isMajor ? 1.4 : 0.8
                )
            }
        }
    }

    // MARK: - Fixed Index Notch

    private func indexNotch(metrics: RotaryDialMetrics) -> some View {
        Canvas { context, _ in
            let top = metrics.point(angleDegrees: -90, radius: metrics.tickRadius + 20)
            let bottom = metrics.point(angleDegrees: -90, radius: metrics.labelRadius + 16)
            var needle = Path()
            needle.move(to: top)
            needle.addLine(to: bottom)
            context.stroke(needle, with: .color(.vibeAccent), lineWidth: 2.5)

            let tipRect = CGRect(x: bottom.x - 3, y: bottom.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: tipRect), with: .color(.vibeAccent))
        }
    }

    // MARK: - Rotating Option Labels

    private func optionLabels(metrics: RotaryDialMetrics) -> some View {
        ForEach(visibleIndices, id: \.self) { idx in
            let delta = Double(idx - selectedIndex)
            let angle = -90.0 + delta * stepAngleDegrees
            let position = metrics.point(angleDegrees: angle, radius: metrics.labelRadius)
            let distance = abs(delta)
            let isSelected = idx == selectedIndex

            Text(options[idx])
                .font(.system(size: isSelected ? 17 : 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.vibeAccent : Color.dialInk.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
                .scaleEffect(max(0.82, 1 - distance * 0.1))
                .opacity(max(0.0, 1 - distance * 0.34))
                .position(position)
                .onTapGesture {
                    commit(idx)
                }
        }
    }

    /// Indices rendered around the notch. Clamped to the valid range so the list does not wrap.
    private var visibleIndices: [Int] {
        guard !options.isEmpty else { return [] }
        let lower = max(0, selectedIndex - 3)
        let upper = min(options.count - 1, selectedIndex + 3)
        return Array(lower...upper)
    }

    // MARK: - Drag

    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                let angle = angleDegrees(from: center, to: gesture.location)
                if dragStartAngle == nil {
                    dragStartAngle = angle
                    dragStartIndex = selectedIndex
                }
                guard let startAngle = dragStartAngle, let startIndex = dragStartIndex else { return }
                let delta = normalizedAngleDelta(angle - startAngle)
                let steps = Int((delta / stepAngleDegrees).rounded())
                // Dragging a label toward the notch (finger angle decreasing) advances the index,
                // so it feels like grabbing the face and pulling it.
                let candidate = clamped(startIndex - steps)
                if candidate != selectedIndex {
                    commit(candidate)
                }
            }
            .onEnded { _ in
                dragStartAngle = nil
                dragStartIndex = nil
            }
    }

    private func angleDegrees(from center: CGPoint, to point: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        return atan2(dy, dx) * 180.0 / .pi
    }

    private func normalizedAngleDelta(_ raw: Double) -> Double {
        let radians = raw * .pi / 180.0
        return atan2(sin(radians), cos(radians)) * 180.0 / .pi
    }

    private func clamped(_ raw: Int) -> Int {
        guard !options.isEmpty else { return 0 }
        return max(0, min(options.count - 1, raw))
    }

    private func commit(_ newIndex: Int) {
        guard options.indices.contains(newIndex), newIndex != selectedIndex else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        onSelect(newIndex)
    }
}

// MARK: - Geometry

/// Places the dial's circle center well below the frame so the visible arc is a wide, shallow
/// curve. The large label radius keeps adjacent option labels far enough apart to stay legible
/// without overlapping on a 393 x 852 pt screen.
private struct RotaryDialMetrics {
    let center: CGPoint
    let labelRadius: CGFloat
    let tickRadius: CGFloat

    init(size: CGSize) {
        let width = max(size.width, 1)
        let labelRadius = max(180, width * 0.62)
        self.labelRadius = labelRadius
        // The top (selected) label sits `topInset` from the top edge; everything else follows.
        let topInset: CGFloat = 36
        self.center = CGPoint(x: width / 2, y: topInset + labelRadius)
        self.tickRadius = labelRadius + 22
    }

    func point(angleDegrees: Double, radius: CGFloat) -> CGPoint {
        let rad = angleDegrees * .pi / 180.0
        return CGPoint(
            x: center.x + CGFloat(cos(rad)) * radius,
            y: center.y + CGFloat(sin(rad)) * radius
        )
    }
}
