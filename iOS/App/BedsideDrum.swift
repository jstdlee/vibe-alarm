import SwiftUI
import UIKit

/// A vertical drum for one number. Chevron buttons and a vertical drag both step the value.
/// The brass mark is the index; the numeral is the reading.
struct BedsideDrum: View {
    let title: String
    @Binding var value: Int
    let upperBound: Int

    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VibePalette.inkSoft)

            stepButton(systemName: "chevron.up", label: "Increase \(title)") { step(1) }

            Text(String(format: "%02d", value))
                .font(.system(size: digitSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(VibePalette.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(alignment: .leading) {
                    Capsule()
                        .fill(VibePalette.amber)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 10)
                        .accessibilityHidden(true)
                }
                .recessedWell(corner: 16)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%02d", value))
                .accessibilityAdjustableAction { direction in
                    step(direction == .increment ? 1 : -1)
                }

            stepButton(systemName: "chevron.down", label: "Decrease \(title)") { step(-1) }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { gesture in
                    if gesture.translation.height <= -12 {
                        step(1)
                    } else if gesture.translation.height >= 12 {
                        step(-1)
                    }
                }
        )
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(VibePalette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int) {
        let count = max(upperBound, 1)
        value = (value + delta + count) % count
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
