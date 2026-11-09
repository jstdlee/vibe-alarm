import SwiftUI
import UIKit

/// Bedside clock surfaces.
///
/// Daylight is warm paper. Night is a charcoal case. One brass index marks the active
/// choice. Depth is a shallow well or a single soft shadow plus a hairline, and the
/// palette raises contrast for the Increase Contrast setting.
public enum VibePalette {
    public static let paper = dynamic(
        light: rgb(0.953, 0.941, 0.918),
        dark: rgb(0.078, 0.075, 0.067),
        lightHigh: .white,
        darkHigh: .black
    )
    public static let paperRaised = dynamic(
        light: rgb(0.984, 0.976, 0.965),
        dark: rgb(0.118, 0.110, 0.102),
        lightHigh: .white,
        darkHigh: rgb(0.08, 0.08, 0.08)
    )
    public static let paperDeep = dynamic(
        light: rgb(0.910, 0.894, 0.863),
        dark: rgb(0.145, 0.137, 0.125),
        lightHigh: rgb(0.94, 0.94, 0.94),
        darkHigh: rgb(0.12, 0.12, 0.12)
    )
    public static let well = dynamic(
        light: rgb(0.902, 0.882, 0.847),
        dark: rgb(0.055, 0.051, 0.047),
        lightHigh: rgb(0.90, 0.90, 0.90),
        darkHigh: .black
    )

    public static let ink = dynamic(
        light: rgb(0.110, 0.098, 0.086),
        dark: rgb(0.965, 0.945, 0.910),
        lightHigh: .black,
        darkHigh: .white
    )
    public static let inkSoft = dynamic(
        light: rgb(0.306, 0.286, 0.259),
        dark: rgb(0.824, 0.796, 0.749),
        lightHigh: rgb(0.15, 0.15, 0.15),
        darkHigh: rgb(0.95, 0.95, 0.95)
    )
    public static let inkFaint = dynamic(
        light: rgb(0.369, 0.345, 0.310),
        dark: rgb(0.718, 0.686, 0.639),
        lightHigh: rgb(0.22, 0.22, 0.22),
        darkHigh: rgb(0.90, 0.90, 0.90)
    )

    public static let hairline = dynamic(
        light: rgb(0.110, 0.098, 0.086, 0.16),
        dark: rgb(0.965, 0.945, 0.910, 0.18),
        lightHigh: rgb(0, 0, 0, 0.35),
        darkHigh: rgb(1, 1, 1, 0.40)
    )

    /// Brass index. Dark enough for text on the daylight face, light enough on the night case.
    public static let amber = dynamic(
        light: rgb(0.478, 0.294, 0.086),
        dark: rgb(0.941, 0.761, 0.478),
        lightHigh: rgb(0.361, 0.220, 0.059),
        darkHigh: rgb(1.0, 0.906, 0.722)
    )
    public static let amberWash = dynamic(
        light: rgb(0.478, 0.294, 0.086, 0.12),
        dark: rgb(0.941, 0.761, 0.478, 0.16),
        lightHigh: rgb(0.361, 0.220, 0.059, 0.16),
        darkHigh: rgb(1.0, 0.906, 0.722, 0.20)
    )

    public static let shadow = dynamic(
        light: rgb(0.145, 0.118, 0.078),
        dark: .black,
        lightHigh: .black,
        darkHigh: .black
    )

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func dynamic(light: UIColor, dark: UIColor, lightHigh: UIColor, darkHigh: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return high ? darkHigh : dark
            }
            return high ? lightHigh : light
        })
    }
}

// MARK: - Typography

public extension Font {
    static func vibeNumber(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

public extension View {
    /// Secondary label. Sentence case, footnote size, no tracking.
    func vibeCaption(_ tone: Color = VibePalette.inkFaint) -> some View {
        self
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone)
    }

    func engravedDivider(_ inset: CGFloat = 0) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(VibePalette.hairline)
                .frame(height: 0.5)
                .padding(.leading, inset)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Volume Styles

/// A raised plate: one soft shadow and a hairline. No gloss.
public struct MachinedPlate: ViewModifier {
    let corner: CGFloat
    let raised: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(VibePalette.paperRaised)
                    .shadow(
                        color: VibePalette.shadow.opacity(raised ? 0.10 : 0.04),
                        radius: raised ? 6 : 2,
                        x: 0,
                        y: raised ? 3 : 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(VibePalette.hairline, lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
    }
}

/// A recessed well with a shallow inner shadow.
public struct RecessedWell: ViewModifier {
    let corner: CGFloat

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        VibePalette.well.shadow(
                            .inner(color: VibePalette.shadow.opacity(0.16), radius: 3, x: 0, y: 1)
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(VibePalette.hairline, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    )
            )
    }
}

public extension View {
    func machinedPlate(corner: CGFloat = 14, raised: Bool = true) -> some View {
        modifier(MachinedPlate(corner: corner, raised: raised))
    }

    func recessedWell(corner: CGFloat = 16) -> some View {
        modifier(RecessedWell(corner: corner))
    }
}

// MARK: - Key Button Style

public struct MachinedKeyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Legacy Aliases

public extension Color {
    static let vibeAccent = VibePalette.amber
}

// MARK: - Hairline

public struct Hairline: View {
    let inset: CGFloat

    public init(inset: CGFloat = 0) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(VibePalette.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .allowsHitTesting(false)
    }
}

// MARK: - Caption

public struct GroupCaption: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .vibeCaption()
    }
}

enum VibeMotion {
    static func settle(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }
}
