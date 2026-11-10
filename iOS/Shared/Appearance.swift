import SwiftUI
import UIKit
import WidgetKit

/// The two shipped looks. Standard is the default.
public enum AppearanceStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case bedside

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .bedside: return "Bedside Clock"
        }
    }

    public static let storageKey = "vibeAlarm.appearanceStyle"

    public static func load(from defaults: UserDefaults?) -> AppearanceStyle {
        guard let raw = defaults?.string(forKey: storageKey),
              let style = AppearanceStyle(rawValue: raw) else {
            return .standard
        }
        return style
    }
}

/// Local appearance choice, shared with the widget through the App Group.
@MainActor
public final class AppearanceStore: ObservableObject {
    @Published public private(set) var style: AppearanceStyle
    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupID)) {
        let resolved = defaults ?? .standard
        self.defaults = resolved
        self.style = AppearanceStyle.load(from: resolved)
    }

    public func select(_ style: AppearanceStyle) {
        guard style != self.style else { return }
        self.style = style
        defaults.set(style.rawValue, forKey: AppearanceStyle.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Colors and type for the active theme and the current system appearance.
public struct VibeTokens: Equatable {
    public var paper: Color
    public var raised: Color
    public var well: Color
    public var ink: Color
    public var inkSoft: Color
    public var inkFaint: Color
    public var accent: Color
    public var hairline: Color
    public var timeDesign: Font.Design
    public var timeWeight: Font.Weight

    public static let standard = VibeTokens(
        paper: Color(.systemGroupedBackground),
        raised: Color(.secondarySystemGroupedBackground),
        well: Color(.tertiarySystemFill),
        ink: .primary,
        inkSoft: .secondary,
        inkFaint: Color(.tertiaryLabel),
        accent: .accentColor,
        hairline: Color(.separator),
        timeDesign: .default,
        timeWeight: .regular
    )

    public static func resolve(
        style: AppearanceStyle,
        scheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> VibeTokens {
        switch style {
        case .standard:
            return .standard
        case .bedside:
            return bedside(scheme: scheme, contrast: contrast)
        }
    }

    private static func bedside(scheme: ColorScheme, contrast: ColorSchemeContrast) -> VibeTokens {
        let high = contrast == .increased
        func paint(light: UIColor, dark: UIColor, lightHigh: UIColor, darkHigh: UIColor) -> Color {
            if scheme == .dark {
                return Color(uiColor: high ? darkHigh : dark)
            }
            return Color(uiColor: high ? lightHigh : light)
        }
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
            UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return VibeTokens(
            paper: paint(
                light: rgb(0.953, 0.941, 0.918),
                dark: rgb(0.078, 0.075, 0.067),
                lightHigh: .white,
                darkHigh: .black
            ),
            raised: paint(
                light: rgb(0.984, 0.976, 0.965),
                dark: rgb(0.118, 0.110, 0.102),
                lightHigh: .white,
                darkHigh: rgb(0.08, 0.08, 0.08)
            ),
            well: paint(
                light: rgb(0.902, 0.882, 0.847),
                dark: rgb(0.055, 0.051, 0.047),
                lightHigh: rgb(0.90, 0.90, 0.90),
                darkHigh: .black
            ),
            ink: paint(
                light: rgb(0.110, 0.098, 0.086),
                dark: rgb(0.965, 0.945, 0.910),
                lightHigh: .black,
                darkHigh: .white
            ),
            inkSoft: paint(
                light: rgb(0.306, 0.286, 0.259),
                dark: rgb(0.824, 0.796, 0.749),
                lightHigh: rgb(0.15, 0.15, 0.15),
                darkHigh: rgb(0.95, 0.95, 0.95)
            ),
            inkFaint: paint(
                light: rgb(0.369, 0.345, 0.310),
                dark: rgb(0.718, 0.686, 0.639),
                lightHigh: rgb(0.22, 0.22, 0.22),
                darkHigh: rgb(0.90, 0.90, 0.90)
            ),
            accent: paint(
                light: rgb(0.478, 0.294, 0.086),
                dark: rgb(0.941, 0.761, 0.478),
                lightHigh: rgb(0.361, 0.220, 0.059),
                darkHigh: rgb(1.0, 0.906, 0.722)
            ),
            hairline: paint(
                light: rgb(0.110, 0.098, 0.086, 0.16),
                dark: rgb(0.965, 0.945, 0.910, 0.18),
                lightHigh: rgb(0, 0, 0, 0.35),
                darkHigh: rgb(1, 1, 1, 0.40)
            ),
            timeDesign: .rounded,
            timeWeight: .medium
        )
    }
}

private struct AppearanceStyleKey: EnvironmentKey {
    static let defaultValue: AppearanceStyle = .standard
}

private struct VibeTokensKey: EnvironmentKey {
    static let defaultValue: VibeTokens = .standard
}

public extension EnvironmentValues {
    var appearanceStyle: AppearanceStyle {
        get { self[AppearanceStyleKey.self] }
        set { self[AppearanceStyleKey.self] = newValue }
    }

    var vibeTokens: VibeTokens {
        get { self[VibeTokensKey.self] }
        set { self[VibeTokensKey.self] = newValue }
    }
}

/// Recomputes tokens when the theme or the system appearance changes.
struct RefreshVibeTokens: ViewModifier {
    @Environment(\.appearanceStyle) private var style
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.environment(\.vibeTokens, .resolve(style: style, scheme: scheme, contrast: contrast))
    }
}

/// Bedside screens sit on warm paper and use the brass accent. Standard keeps system surfaces.
struct VibeChrome: ViewModifier {
    @Environment(\.appearanceStyle) private var style
    @Environment(\.vibeTokens) private var tokens

    func body(content: Content) -> some View {
        if style == .bedside {
            content
                .scrollContentBackground(.hidden)
                .background(tokens.paper.ignoresSafeArea())
                .tint(tokens.accent)
        } else {
            content
        }
    }
}

extension View {
    func vibeChrome() -> some View {
        modifier(VibeChrome())
    }
}
