// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BraidArt",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BraidArt", targets: ["BraidArt"]), .library(name: "BraidCore", targets: ["BraidCore"])],
    targets: [
        .target(name: "BraidCore", resources: [.copy("Resources/ColorCost.metal")]),
        .executableTarget(name: "BraidArt", dependencies: ["BraidCore"], resources: [.copy("Resources/AppIcon.icns")]),
        .testTarget(name: "BraidCoreTests", dependencies: ["BraidCore"])
    ],
    swiftLanguageModes: [.v5]
)
