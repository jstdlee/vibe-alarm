import SwiftUI
import UIKit

/// Hour or minute drum for the Bedside Clock theme.
struct BedsideDrum: View {
    let title: String
    @Binding var value: Int
    let upperBound: Int

    @Environment(\.vibeTokens) private var tokens
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tokens.inkSoft)

            stepButton(systemName: "chevron.up", label: "Increase \(title)") { step(1) }

            Text(String(format: "%02d", value))
                .font(.system(size: digitSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tokens.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(alignment: .leading) {
                    Capsule()
                        .fill(tokens.accent)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 10)
                        .accessibilityHidden(true)
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tokens.well)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(tokens.hairline, lineWidth: 0.5)
                        )
                }
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
                .foregroundStyle(tokens.inkSoft)
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
