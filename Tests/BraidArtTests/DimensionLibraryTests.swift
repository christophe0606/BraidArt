import XCTest
import AppKit
import SwiftUI
import BraidCore
@testable import BraidArt

final class DimensionLibraryTests:XCTestCase {
    @MainActor func testCustomLibraryPersistsEditsAndDeletionWithoutChangingBuiltIns() throws {
        let suite="BraidArt.DimensionTests.\(UUID().uuidString)",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let model=AppModel(defaults:defaults),builtins=PictureExportSize.outputSizes
        XCTAssertTrue(model.customDimensions.isEmpty)
        let preset=try model.addCustomDimensions(name:"Print",width:1200,height:1600)
        let another=try model.addCustomDimensions(name:"Banner",width:2048,height:512)
        XCTAssertEqual(AppModel(defaults:defaults).customDimensions,[preset,another])
        model.setOutputSize(preset);model.pictureExportSize=preset
        let edited=try model.editCustomDimensions(preset,name:"Print large",width:2400,height:3200)
        XCTAssertEqual(edited.id,preset.id)
        XCTAssertEqual(model.settings.outputSize,edited);XCTAssertEqual(model.pictureExportSize,edited)
        XCTAssertEqual(AppModel(defaults:defaults).customDimensions,[edited,another])
        for size in PictureExportSize.allCases {
            XCTAssertFalse(model.deleteCustomDimensions(size))
            XCTAssertThrowsError(try model.editCustomDimensions(size,name:"Changed",width:1,height:1))
        }
        XCTAssertEqual(PictureExportSize.outputSizes,builtins)
        XCTAssertTrue(model.deleteCustomDimensions(edited))
        XCTAssertEqual(model.settings.outputSize,.fullHD);XCTAssertEqual(model.pictureExportSize,.fullHD)
        XCTAssertEqual(AppModel(defaults:defaults).customDimensions,[another])
        XCTAssertTrue(model.deleteCustomDimensions(another))
        XCTAssertTrue(AppModel(defaults:defaults).customDimensions.isEmpty)
    }

    @MainActor func testEditingSelectedCustomDimensionsUpdatesCropRatio() async throws {
        let suite="BraidArt.DimensionTests.\(UUID().uuidString)",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let model=AppModel(defaults:defaults)
        model.open(url:try XCTUnwrap(HelpIllustration.photograph.url))
        let deadline=ContinuousClock.now.advanced(by:.seconds(10))
        while model.busy,ContinuousClock.now<deadline { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertFalse(model.busy);XCTAssertNil(model.error)
        let preset=try model.addCustomDimensions(name:"Square",width:1000,height:1000)
        model.setOutputSize(preset)
        let edited=try model.editCustomDimensions(preset,name:"Portrait",width:1200,height:1800)
        let crop=model.settings.crop,image=try XCTUnwrap(model.sourceImage)
        XCTAssertEqual(crop.width*image.size.width/(crop.height*image.size.height),2.0/3,accuracy:1e-10)
        XCTAssertEqual(model.settings.outputSize,edited)
        XCTAssertTrue(model.hasCropSelection)
        XCTAssertFalse(model.preparedIsCurrent)
    }

    @MainActor func testCustomProjectReopensWithoutTheLocalLibrary() async throws {
        let suite="BraidArt.DimensionTests.\(UUID().uuidString)",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let model=AppModel(defaults:defaults),preset=try PictureExportSize.custom(CustomPictureSize(name:"Portable",width:321,height:517))
        var project=try CurveTestsFixture.project()
        project.settings.outputSize=preset;project.pictureExportSize=preset
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".braidart")
        defer { try? FileManager.default.removeItem(at:url) }
        try project.save(to:url)
        model.open(url:url)
        let deadline=ContinuousClock.now.advanced(by:.seconds(10))
        while model.busy,ContinuousClock.now<deadline { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertFalse(model.busy);XCTAssertNil(model.error)
        XCTAssertEqual(model.settings.outputSize,preset);XCTAssertEqual(model.pictureExportSize,preset)
        XCTAssertEqual(model.resultImage?.size,CGSize(width:321,height:517))
        XCTAssertTrue(model.customDimensions.isEmpty,"Opening a project must not recreate a deleted local preset")
        XCTAssertEqual(model.pictureExportSize.pixelSize(viewport:.zero),CGSize(width:321,height:517))
    }
}

private enum CurveTestsFixture {
    static func project() throws -> BraidProject {
        let settings=Settings(),data=TileData(settings:Settings())
        return BraidProject(sourceName:"Fixture",settings:settings,sampledImage:PixelImage(width:1,height:1,pixels:[.gray]),
                            tileData:data,result:SolveResult(solution:[[1]],reports:[],costBackend:"Test",elapsedSeconds:0))
    }
}
