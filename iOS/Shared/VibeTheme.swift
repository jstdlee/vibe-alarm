import SwiftUI

/// Minimal shared theme constants used by the App and Widget targets.
/// The app uses system semantic colors everywhere except for the single
/// accent color and the neutral metallic tones used by the two
/// skeuomorphic controls (`SemicircleDial`, `ThumbwheelRoller`).
public extension Color {
    /// The app's single accent color.
    static let vibeAccent = Color.orange

    /// Light edge of the brushed-metal surface behind the dials and rollers.
    static let dialMetalLight = Color(white: 0.94)
    /// Dark edge of the brushed-metal surface behind the dials and rollers.
    static let dialMetalDark = Color(white: 0.84)
    /// Fine tick marks and numerals on the dials and rollers.
    static let dialInk = Color(white: 0.30)
}
