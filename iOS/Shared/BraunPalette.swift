import SwiftUI

/// Braun / Dieter Rams-inspired Apple Light Theme palette shared by the App and Widget targets.
public extension Color {
    /// Warm Alabaster canvas background (#F5F5F7).
    static let vibeCanvas = Color(red: 0.961, green: 0.961, blue: 0.969)
    /// Pure Matte White card surface (#FFFFFF).
    static let vibeCard = Color.white
    /// Hairline card border (#E5E5EA).
    static let vibeCardBorder = Color(red: 0.898, green: 0.898, blue: 0.918)
    /// Machined anodized aluminum, light edge (#ECECEF).
    static let vibeAluminumLight = Color(red: 0.925, green: 0.925, blue: 0.937)
    /// Machined anodized aluminum, dark edge (#E2E2E7).
    static let vibeAluminumDark = Color(red: 0.886, green: 0.886, blue: 0.906)
    /// Dark charcoal tick marks & primary ink (#1C1C1E).
    static let vibeInk = Color(red: 0.110, green: 0.110, blue: 0.118)
    /// Secondary tick marks & muted text (#8E8E93).
    static let vibeInkMuted = Color(red: 0.557, green: 0.557, blue: 0.576)
    /// Signature Braun International Orange accent (#FF5500).
    static let vibeAccent = Color(red: 1.0, green: 0.333, blue: 0.0)
    /// Makeup Workday / Delayed semantic color (#007AFF).
    static let vibeWork = Color(red: 0.0, green: 0.478, blue: 1.0)
    /// Personal Leave / Holiday Skipped semantic color (#34C759).
    static let vibePTO = Color(red: 0.204, green: 0.780, blue: 0.349)
}

/// Pure Matte White card with 18pt continuous corner radius, hairline border, and soft shadow.
public struct VibeCardBackground: ViewModifier {
    public func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.vibeCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.vibeCardBorder, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }
}

public extension View {
    func vibeCard() -> some View { modifier(VibeCardBackground()) }
}
