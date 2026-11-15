import XCTest
import AppKit
import UniformTypeIdentifiers
import BraidCore
@testable import BraidArt

final class IdentityTests:XCTestCase {
    private var root:URL {
        URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    func testIconPatternHasMatchingEdgesAndConstantColorStrands() throws {
        let project=try BraidProject.load(from:root.appendingPathComponent("Resources/IconPattern.braidart"))
        try project.validate()
        let curves=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        XCTAssertFalse(curves.curves.isEmpty)
        XCTAssertEqual(project.settings.palette,[.black,.white])
        XCTAssertEqual(project.settings.background,.gray)
        let nine=project.result.solution.prefix(3).map { Array($0.prefix(3)) }
        XCTAssertEqual(nine.count,3);XCTAssertTrue(nine.allSatisfy { $0.count==3 })
        let iconCurves=try CurveGenerator.generate(solution:nine,data:project.tileData)
        XCTAssertEqual(Set(iconCurves.curves.map(\.colorIndex)),Set([0,1]))
        for id in nine[1] {
            let tile=project.tileData.allTiles[id-1]
            XCTAssertEqual(tile.kind,.hCross);XCTAssertEqual(tile.firstColor,0)
        }
    }
    @MainActor func testIconHasTransparentMarginsAndBundledMacResolutions() throws {
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:Data(contentsOf:root.appendingPathComponent("Resources/AppIcon.png"))))
        XCTAssertEqual(bitmap.pixelsWide,1024);XCTAssertEqual(bitmap.pixelsHigh,1024)
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertEqual(bitmap.colorAt(x:0,y:0)?.alphaComponent,0)
        XCTAssertEqual(bitmap.colorAt(x:512,y:512)?.alphaComponent,1)
        for y in stride(from:96,to:928,by:64) { for x in stride(from:96,to:928,by:64) {
            let color=try XCTUnwrap(bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB))
            // NSColor's profile conversion introduces tiny floating-point noise.
            XCTAssertEqual(color.redComponent,color.greenComponent,accuracy:1e-5)
            XCTAssertEqual(color.greenComponent,color.blueComponent,accuracy:1e-5)
        } }
        let sizes=Set(AppIcon.image.representations.map(\.pixelsWide))
        XCTAssertTrue(sizes.contains(16));XCTAssertTrue(sizes.contains(1024))
    }
    func testBlackCurvesHaveNoBrightResamplingFringe() throws {
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:Data(contentsOf:root.appendingPathComponent("Resources/AppIcon.png"))))
        // Gray immediately below the upper black arc must be no brighter than
        // the uninterrupted gray farther away. A sharp filter previously
        // introduced an extra light band here, visible at small icon sizes.
        let gray=try XCTUnwrap(bitmap.colorAt(x:658,y:300))
        for x in 648...668 {
            let edge=try XCTUnwrap(bitmap.colorAt(x:x,y:280))
            XCTAssertLessThanOrEqual(edge.redComponent,gray.redComponent+1e-5)
            XCTAssertLessThanOrEqual(edge.greenComponent,gray.greenComponent+1e-5)
            XCTAssertLessThanOrEqual(edge.blueComponent,gray.blueComponent+1e-5)
        }
    }
    func testProjectDocumentDeclaresItsIconWithoutTextConformance() throws {
        let data=try Data(contentsOf:root.appendingPathComponent("Resources/Info.plist"))
        let plist=try XCTUnwrap(PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any])
        let exported=try XCTUnwrap((plist["UTExportedTypeDeclarations"] as? [[String:Any]])?.first)
        let conformance=try XCTUnwrap(exported["UTTypeConformsTo"] as? [String])
        XCTAssertTrue(conformance.contains("public.data"))
        XCTAssertFalse(conformance.contains("public.json"));XCTAssertFalse(conformance.contains("public.text"))
        let document=try XCTUnwrap((plist["CFBundleDocumentTypes"] as? [[String:Any]])?.first)
        XCTAssertEqual(document["CFBundleTypeIconFile"] as? String,"BraidArtIcon.icns")
    }
    func testRuntimeProjectTypeDoesNotAdvertiseText() {
        XCTAssertTrue(UTType.braidArtProject.conforms(to:.data))
        XCTAssertFalse(UTType.braidArtProject.conforms(to:.text))
        XCTAssertFalse(UTType.braidArtProject.conforms(to:.json))
    }
}
