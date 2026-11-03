import SwiftUI
import UIKit

/// A horizontal skeuomorphic thumbwheel: a row of text options that slides left and right
/// like a physical cylinder. The center option is bold and full size; neighbors fade and
/// shrink toward the edges. Replaces dropdown menus for short option lists (repeat, holiday rule).
public struct ThumbwheelRoller: View {
    public let options: [String]
    public let selectedIndex: Int
    public let accessibilityLabelText: String
    public let onSelect: (Int) -> Void

    @State private var dragTranslation: CGFloat = 0

    private let slotWidth: CGFloat = 76

    public init(
        options: [String],
        selectedIndex: Int,
        accessibilityLabelText: String,
        onSelect: @escaping (Int) -> Void
    ) {
        self.options = options
        self.selectedIndex = max(0, min(max(0, options.count - 1), selectedIndex))
        self.accessibilityLabelText = accessibilityLabelText
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { geo in
            let centerIndex = effectiveCenterIndex
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.dialMetalDark, .dialMetalLight, .dialMetalLight, .dialMetalDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, label in
                        slotLabel(text: label, idx: idx, centerIndex: centerIndex)
                            .frame(width: slotWidth)
                    }
                }
                .offset(x: baseOffsetX(containerWidth: geo.size.width) + dragTranslation)

                centerHairline

                edgeButtons
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(options.indices.contains(selectedIndex) ? options[selectedIndex] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                commit(wrappedIndex(selectedIndex + 1))
            case .decrement:
                commit(wrappedIndex(selectedIndex - 1))
            default:
                break
            }
        }
    }

    // MARK: - Layout Math

    private var effectiveCenterIndex: CGFloat {
        CGFloat(selectedIndex) - dragTranslation / slotWidth
    }

    private func baseOffsetX(containerWidth: CGFloat) -> CGFloat {
        containerWidth / 2 - (CGFloat(selectedIndex) + 0.5) * slotWidth
    }

    private func slotLabel(text: String, idx: Int, centerIndex: CGFloat) -> some View {
        let delta = abs(CGFloat(idx) - centerIndex)
        let scale = max(0.72, 1 - delta * 0.20)
        let opacity = max(0.22, 1 - delta * 0.38)
        let isCentered = delta < 0.5
        return Text(text)
            .font(.system(size: 15, weight: isCentered ? .bold : .medium))
            .foregroundStyle(isCentered ? Color.vibeAccent : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private var centerHairline: some View {
        Rectangle()
            .fill(Color.vibeAccent.opacity(0.35))
            .frame(width: 1, height: 26)
    }

    private var edgeButtons: some View {
        HStack {
            Button {
                commit(wrappedIndex(selectedIndex - 1))
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                commit(wrappedIndex(selectedIndex + 1))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { gesture in
                dragTranslation = gesture.translation.width
            }
            .onEnded { gesture in
                let steps = Int((gesture.translation.width / slotWidth).rounded())
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    dragTranslation = 0
                }
                commit(wrappedIndex(selectedIndex - steps))
            }
    }

    private func wrappedIndex(_ raw: Int) -> Int {
        guard !options.isEmpty else { return 0 }
        return ((raw % options.count) + options.count) % options.count
    }

    private func commit(_ newIndex: Int) {
        guard newIndex != selectedIndex else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        onSelect(newIndex)
    }
}
