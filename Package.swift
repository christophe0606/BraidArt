// swift-tools-version: 6.0
import PackageDescription
import Foundation

let solverLibraryPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".build/solver-native/lib").path

let package = Package(
    name: "BraidArt",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BraidArt", targets: ["BraidArt"]), .library(name: "BraidCore", targets: ["BraidCore"])],
    targets: [
        .systemLibrary(name: "CBCLibrary"),
        .target(name: "BraidCore", dependencies: ["CBCLibrary"], resources: [.copy("Resources/ColorCost.metal"), .process("Resources/en.lproj"), .process("Resources/fr.lproj")], linkerSettings: [
            .unsafeFlags(["-L", solverLibraryPath, "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", solverLibraryPath], .when(configuration: .debug))
        ]),
        .executableTarget(name: "BraidArt", dependencies: ["BraidCore"], resources: [.copy("Resources/AppIcon.icns"), .copy("Resources/Help")]),
        .target(name: "VideoTestSupport", dependencies: ["BraidCore"], path: "Tests/VideoSupport"),
        .testTarget(name: "BraidCoreTests", dependencies: ["BraidCore", "CBCLibrary", "VideoTestSupport"]),
        .testTarget(name: "BraidArtTests", dependencies: ["BraidArt", "BraidCore", "VideoTestSupport"])
    ],
    swiftLanguageModes: [.v5]
)
