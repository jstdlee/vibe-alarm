import SwiftUI
import UIKit

/// A short horizontal roller for choosing one of a handful of named values.
///
/// This is the option control on the Wake Time editor. It deliberately has no title above it:
/// the value is centred, the caption sits at the bottom middle *inside* the same well, and the
/// neighbouring values fade off both edges of the well. Nothing is boxed and nothing is labelled
/// twice, so three of these stack as a single calm block of machined dials.
///
/// The surface is a shallow milled channel: the well is recessed, the selected value sits on a
/// small raised boss inside it, and the whole row of values travels on a heavy spring when it
/// changes, so a two-item list and a five-item list feel identically weighted.
public struct CompactRoller: View {
    public let caption: String
    public let options: [String]
    public let selectedIndex: Int
    /// Distance in points between adjacent option centres.
    public let spacing: CGFloat
    /// Height of the milled channel. The caption always sits at its bottom middle.
    public let height: CGFloat
    public let onSelect: (Int) -> Void

    @State private var dragStartX: CGFloat?
    @State private var dragStartIndex: Int

    public init(
        caption: String,
        options: [String],
        selectedIndex: Int,
        spacing: CGFloat = 84,
        height: CGFloat = 84,
        onSelect: @escaping (Int) -> Void
    ) {
        self.caption = caption
        self.options = options
        self.selectedIndex = max(0, min(max(0, options.count - 1), selectedIndex))
        self.spacing = spacing
        self.height = height
        self.onSelect = onSelect
        _dragStartIndex = State(initialValue: max(0, min(max(0, options.count - 1), selectedIndex)))
    }

    private var wellHeight: CGFloat { height }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                well
                bosses(width: width)
                labels(width: width)
                captionLine
            }
            .frame(width: width, height: wellHeight)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: wellHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(options.indices.contains(selectedIndex) ? options[selectedIndex] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(clamped(selectedIndex + 1))
            case .decrement: commit(clamped(selectedIndex - 1))
            default: break
            }
        }
    }

    private var bossSize: CGFloat { min(44, wellHeight * 0.52) }
    private var corner: CGFloat { wellHeight * 0.26 }

    // MARK: - Surface

    private var well: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(VibePalette.paperDeep)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(VibePalette.hairline.opacity(0.55), lineWidth: 0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.10), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            )
    }

    /// A small raised boss under each visible option. The selected one is amber; the
    /// neighbours are bare plaster, which is the only difference between them.
    private func bosses(width: CGFloat) -> some View {
        ForEach(-2...2, id: \.self) { slot in
            let index = selectedIndex + slot
            if options.indices.contains(index) {
                Circle()
                    .fill(slot == 0 ? VibePalette.amberWash : Color.white.opacity(0.42))
                    .frame(width: bossSize, height: bossSize)
                    .shadow(
                        color: VibePalette.shadow.opacity(slot == 0 ? 0.10 : 0.05),
                        radius: 3,
                        x: 0,
                        y: 1.5
                    )
                    .position(x: width / 2 + CGFloat(slot) * spacing, y: wellHeight * 0.46)
                    .allowsHitTesting(false)
            }
        }
    }

    private func labels(width: CGFloat) -> some View {
        ForEach(-2...2, id: \.self) { slot in
            let index = selectedIndex + slot
            if options.indices.contains(index) {
                Text(options[index])
                    .font(.system(size: slot == 0 ? 15 : 12.5, weight: slot == 0 ? .semibold : .regular))
                    .foregroundStyle(slot == 0 ? VibePalette.amber : VibePalette.inkFaint)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(slot == 0 ? 1 : max(0, 0.72 - Double(abs(slot)) * 0.24))
                    .position(x: width / 2 + CGFloat(slot) * spacing, y: wellHeight * 0.46)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The caption, at the bottom middle of the control, inside the well.
    private var captionLine: some View {
        VStack {
            Spacer(minLength: 0)
            Text(caption.uppercased())
                .vibeCaption(VibePalette.inkFaint.opacity(0.9))
                .padding(.bottom, 11)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Dragging

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                if dragStartX == nil {
                    dragStartX = gesture.translation.width
                    dragStartIndex = selectedIndex
                }
                guard let startX = dragStartX else { return }
                let travel = gesture.translation.width - startX
                let steps = Int((-travel / spacing).rounded())
                let candidate = clamped(dragStartIndex + steps)
                if candidate != selectedIndex {
                    commit(candidate)
                }
            }
            .onEnded { _ in
                dragStartX = nil
                dragStartIndex = selectedIndex
            }
    }

    private func clamped(_ raw: Int) -> Int {
        guard !options.isEmpty else { return 0 }
        return max(0, min(options.count - 1, raw))
    }

    private func commit(_ index: Int) {
        guard options.indices.contains(index), index != selectedIndex else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onSelect(index)
    }
}
