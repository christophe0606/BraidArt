import XCTest
import BraidCore
@testable import BraidArt

final class SidebarTests: XCTestCase {
    @MainActor func testCropPresetScaleDeleteAndRedrawKeepTheSelectedFormat() throws {
        let model=AppModel()
        model.sourceImage=try XCTUnwrap(HelpIllustration.photograph.image)
        model.setCropAspectRatio(.instagramPortrait)
        XCTAssertTrue(model.hasCropSelection)
        let ratio=try XCTUnwrap(model.cropAspectRatio)
        XCTAssertEqual(model.settings.crop.width/model.settings.crop.height,ratio,accuracy:1e-12)
        model.scaleCrop(by:0.7)
        let smaller=model.settings.crop
        XCTAssertEqual(smaller.width/smaller.height,ratio,accuracy:1e-12)
        model.clearCrop()
        XCTAssertFalse(model.hasCropSelection)
        XCTAssertEqual(model.settings.crop,Crop())
        XCTAssertEqual(model.settings.cropAspectRatio,.instagramPortrait)
        model.settings.crop=try XCTUnwrap(CropGeometry.drawn(from:CGPoint(x:0.1,y:0.1),to:CGPoint(x:0.5,y:0.6),aspectRatio:model.cropAspectRatio))
        model.hasCropSelection=true
        XCTAssertEqual(model.settings.crop.width/model.settings.crop.height,ratio,accuracy:1e-12)
        let locked=model.settings.crop
        model.setCropAspectRatio(nil)
        XCTAssertEqual(model.settings.crop,locked)
        XCTAssertNil(model.cropAspectRatio)
    }

    @MainActor private func waitForWork(_ model:AppModel) async throws {
        let deadline=ContinuousClock.now.advanced(by:.seconds(10))
        while model.busy,ContinuousClock.now<deadline { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
    }

    @MainActor func testContrastCompletionLeavesSidebarUnchangedAndLatestEditWins() async throws {
        let model=AppModel()
        let url=try XCTUnwrap(HelpIllustration.photograph.url)
        model.open(url:url)
        try await waitForWork(model)
        let original=try XCTUnwrap(model.prepared)
        model.settings.contrast=1.4
        model.prepare()
        XCTAssertTrue(model.busy)
        XCTAssertFalse(model.blocksEditing)
        // A second edit arrives while the first preview is still being prepared.
        model.settings.contrast=1.8
        model.settingsChanged()
        let sidebar=SidebarState(model:model)
        try await waitForWork(model)
        XCTAssertTrue(model.preparedIsCurrent)
        XCTAssertNotEqual(model.prepared,original)
        XCTAssertEqual(model.prepared,try ImageProcessor.prepare(url:url,settings:model.settings))
        XCTAssertEqual(SidebarState(model:model),sidebar,
                       "Applying new pixels at the same dimensions must not invalidate the sidebar")
    }

    @MainActor func testExtractionKeepsControlsEnabledAndUnrelatedUpdatesOutOfSidebar() async throws {
        let model=AppModel()
        model.prepared=PixelImage(width:4,height:1,pixels:[.black,.white,RGB(1,0,0),RGB(0,0,1)])
        let before=SidebarState(model:model)
        model.extractPalette()
        XCTAssertTrue(model.busy)
        XCTAssertFalse(model.blocksEditing)
        XCTAssertEqual(SidebarState(model:model),before)
        try await waitForWork(model)
        XCTAssertEqual(model.settings.palette.count,4)
        let extracted=SidebarState(model:model)
        XCTAssertNotEqual(extracted,before)
        model.progress=0.7;model.status="Another workspace update"
        model.selectedTab=1;model.refreshTiles()
        XCTAssertEqual(SidebarState(model:model),extracted)
    }
}
