// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BraidArt",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BraidArt", targets: ["BraidArt"]), .library(name: "BraidCore", targets: ["BraidCore"])],
    targets: [
        .target(name: "BraidCore", resources: [.copy("Resources/ColorCost.metal"), .process("Resources/en.lproj"), .process("Resources/fr.lproj")]),
        .executableTarget(name: "BraidArt", dependencies: ["BraidCore"], resources: [.copy("Resources/AppIcon.icns"), .copy("Resources/Help")]),
        .testTarget(name: "BraidCoreTests", dependencies: ["BraidCore"]),
        .testTarget(name: "BraidArtTests", dependencies: ["BraidArt", "BraidCore"])
    ],
    swiftLanguageModes: [.v5]
)
