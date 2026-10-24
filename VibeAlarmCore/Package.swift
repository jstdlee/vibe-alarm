// swift-tools-version:6.0
import PackageDescription

// VibeAlarmCore holds the 100% local, privacy-first domain models, holiday & makeup
// workday resolution engine, RFC 5545 ICS parser, BYOK LLM holiday extractor, and
// App Group atomic state store shared between the iOS App and WidgetKit extension.
let package = Package(
    name: "VibeAlarmCore",
    platforms: [.iOS("17.0"), .macOS("14.0")],
    products: [
        .library(name: "VibeAlarmCore", targets: ["VibeAlarmCore"]),
    ],
    targets: [
        .target(name: "VibeAlarmCore"),
        .testTarget(name: "VibeAlarmCoreTests", dependencies: ["VibeAlarmCore"]),
    ],
    swiftLanguageModes: [.v5]
)
