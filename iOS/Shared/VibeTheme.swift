import SwiftUI

/// The app's single art direction: "machined matte volumes".
///
/// Surfaces read as matte plaster and anodised aluminium under one light source in the
/// top-left corner. Depth comes from a raised volume casting a soft shadow, or from a
/// recessed well with an inset shadow, never from borders or glossy gradients.
/// There is exactly one accent: a warm amber used for the active index and the single
/// primary action. Everything else is a warm grey drawn from the paper tone.
public enum VibePalette {
    /// The page. A warm plaster paper, deliberately not pure white.
    public static let paper = Color(red: 0.949, green: 0.937, blue: 0.914)
    /// A raised volume catching the light.
    public static let paperRaised = Color(red: 0.980, green: 0.973, blue: 0.957)
    /// A volume turned slightly away from the light.
    public static let paperDeep = Color(red: 0.902, green: 0.886, blue: 0.855)
    /// The floor of a recessed well.
    public static let well = Color(red: 0.871, green: 0.851, blue: 0.812)

    /// Primary text and engraved numerals.
    public static let ink = Color(red: 0.153, green: 0.141, blue: 0.125)
    /// Secondary text.
    public static let inkSoft = Color(red: 0.420, green: 0.396, blue: 0.353)
    /// Captions, unit labels, inactive neighbours.
    public static let inkFaint = Color(red: 0.596, green: 0.565, blue: 0.506)

    /// An engraved hairline.
    public static let hairline = Color(red: 0.478, green: 0.439, blue: 0.376).opacity(0.30)

    /// The one accent.
    public static let amber = Color(red: 0.729, green: 0.443, blue: 0.149)
    /// A wash of the accent, used only behind a selected disc.
    public static let amberWash = Color(red: 0.729, green: 0.443, blue: 0.149).opacity(0.14)

    /// Shadow colour. Warm, never neutral black.
    public static let shadow = Color(red: 0.235, green: 0.196, blue: 0.129)
}

// MARK: - Typography

public extension Font {
    /// Numerals: light weight, monospaced digits, generous tracking handled per use.
    static func vibeNumber(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight)
    }
}

public extension View {
    /// Small-caps section and unit labels: 10 pt, wide tracking, faint ink.
    func vibeCaption(_ tone: Color = VibePalette.inkFaint) -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.9)
            .foregroundStyle(tone)
    }

    /// A hairline that reads as an engraved groove rather than a border.
    func engravedDivider(_ inset: CGFloat = 0) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(VibePalette.hairline)
                .frame(height: 0.6)
                .padding(.leading, inset)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Volume Styles

/// A raised machined plate: soft shadow below-right, a one-pixel light catch above-left,
/// a barely visible machined edge. No gloss, no glass.
public struct MachinedPlate: ViewModifier {
    let corner: CGFloat
    let raised: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [VibePalette.paperRaised, VibePalette.paperDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(
                        color: VibePalette.shadow.opacity(raised ? 0.18 : 0.08),
                        radius: raised ? 9 : 4,
                        x: -1.5,
                        y: raised ? 6 : 2
                    )
                    .shadow(color: Color.white.opacity(0.75), radius: 1.2, x: -1, y: -1.2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(VibePalette.hairline.opacity(0.55), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
    }
}

/// A recessed well: the floor sits below the page and the top edge falls into shadow.
public struct RecessedWell: ViewModifier {
    let corner: CGFloat

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        VibePalette.paperDeep.shadow(
                            .inner(color: VibePalette.shadow.opacity(0.22), radius: 6, x: 0, y: 3)
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.clear, Color.white.opacity(0.75)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .allowsHitTesting(false)
                    )
            )
    }
}

public extension View {
    func machinedPlate(corner: CGFloat = 15, raised: Bool = true) -> some View {
        modifier(MachinedPlate(corner: corner, raised: raised))
    }

    func recessedWell(corner: CGFloat = 20) -> some View {
        modifier(RecessedWell(corner: corner))
    }
}

// MARK: - Machined Key Button Style

/// The quick-action keys on the home screen and the widget: three milled keys that
/// travel a fraction of a millimetre and lose their shadow when pressed.
public struct MachinedKeyButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [VibePalette.paperRaised, VibePalette.paperDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(
                        color: VibePalette.shadow.opacity(configuration.isPressed ? 0.10 : 0.20),
                        radius: configuration.isPressed ? 3 : 8,
                        x: -1,
                        y: configuration.isPressed ? 2 : 5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(VibePalette.hairline.opacity(0.55), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Legacy Aliases

public extension Color {
    /// Historic name for the single accent, kept so every call site reads the same.
    static let vibeAccent = VibePalette.amber
}

// MARK: - Hairline

/// A single engraved groove used to separate rows. Never a box.
public struct Hairline: View {
    let inset: CGFloat

    public init(inset: CGFloat = 0) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(VibePalette.hairline.opacity(0.80))
            .frame(height: 0.6)
            .padding(.leading, inset)
            .allowsHitTesting(false)
    }
}

// MARK: - Caption

/// Small-caps group caption used instead of a boxed card header.
public struct GroupCaption: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .vibeCaption()
    }
}
