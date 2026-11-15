import XCTest
@testable import BraidCore
@testable import BraidArt

final class ProjectTests:XCTestCase {
    @MainActor func testProjectSnapshotAndReopeningRestoreCameraAndFrame() async throws {
        let model=AppModel()
        var settings=Settings();settings.columns=8
        let data=TileData(settings:settings)
        let image=PixelImage(width:8,height:2,pixels:Array(repeating:.gray,count:16))
        let result=SolveResult(solution:Array(repeating:Array(repeating:1,count:8),count:2),reports:[],costBackend:"Test",elapsedSeconds:0)
        model.project=BraidProject(sourceName:"Saved camera",settings:settings,sampledImage:image,tileData:data,result:result)
        model.settings=settings
        model.settings.backgroundMinimumDistance=27
        XCTAssertFalse(model.resultNeedsWeaving)
        let camera=CameraState(target:CurvePoint(3,-2,0.5),orbitYaw:0.4,orbitPitch:-0.3,cameraDistance:12,fitDistance:15)
        model.cameraChanged(camera);model.pictureExportSize = .instagramPortrait
        model.sceneSettings=SceneSettings(planeColor:RGB(0.1,0.2,0.3),planeDistance:0.7)
        let saved=try XCTUnwrap(model.projectForSaving)
        XCTAssertEqual(saved.settings.backgroundMinimumDistance,27)
        XCTAssertEqual(saved.cameraState,camera);XCTAssertEqual(saved.pictureExportSize,.instagramPortrait)
        XCTAssertEqual(saved.sceneSettings,model.sceneSettings)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("saved.braidart")
        try saved.save(to:url)
        func waitForOpen() async {
            let deadline=ContinuousClock.now.advanced(by:.seconds(10))
            while model.busy,ContinuousClock.now<deadline { try? await Task.sleep(for:.milliseconds(10)) }
            XCTAssertFalse(model.busy);XCTAssertNil(model.error)
        }
        model.open(url:url);await waitForOpen()
        XCTAssertEqual(model.settings.backgroundMinimumDistance,27)
        XCTAssertEqual(model.cameraState,camera);XCTAssertEqual(model.pictureExportSize,.instagramPortrait)
        XCTAssertEqual(model.selectedTab,3)
        XCTAssertEqual(model.projectForSaving?.cameraState,camera)
        // Opening a legacy project must clear the previous project's view settings.
        var legacy=saved;legacy.cameraState=nil;legacy.pictureExportSize=nil
        try legacy.save(to:url)
        model.open(url:url);await waitForOpen()
        XCTAssertNil(model.cameraState);XCTAssertEqual(model.pictureExportSize,.viewport)
        XCTAssertEqual(model.selectedTab,2)
    }
}
