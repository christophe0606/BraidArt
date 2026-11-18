import XCTest
@testable import BraidCore
@testable import BraidArt

final class ProjectTests:XCTestCase {
    @MainActor func testProjectSnapshotAndReopeningRestoreCameraAndFrame() async throws {
        let model=AppModel()
        XCTAssertTrue(model.settings.grayscale,"New sessions start in luminance mode")
        XCTAssertTrue(model.canChangeOutputDimensions)
        var settings=Settings();settings.columns=8
        let wovenSize = PictureExportSize.custom(try CustomPictureSize(name: "Woven", width: 128, height: 32))
        let nextSize = PictureExportSize.custom(try CustomPictureSize(name: "Next", width: 96, height: 24))
        settings.outputSize=wovenSize
        let data=TileData(settings:settings)
        let image=PixelImage(width:8,height:2,pixels:Array(repeating:.gray,count:16))
        let result=SolveResult(solution:Array(repeating:Array(repeating:1,count:8),count:2),reports:[],costBackend:"Test",elapsedSeconds:0)
        model.project=BraidProject(sourceName:"Saved camera",settings:settings,sampledImage:image,tileData:data,result:result)
        model.sourceImage=try ImageProcessor.cgImage(image).platformImage
        model.settings=settings
        model.settings.backgroundMinimumDistance=27
        model.setOutputSize(nextSize)
        XCTAssertTrue(model.resultNeedsWeaving)
        XCTAssertFalse(model.sculptureNeedsWeaving)
        XCTAssertEqual(model.pictureExportSize,nextSize)
        XCTAssertNil(model.projectForSaving?.pictureExportSize)
        let camera=CameraState(target:CurvePoint(3,-2,0.5),orbitYaw:0.4,orbitPitch:-0.3,cameraDistance:12,fitDistance:15)
        model.cameraChanged(camera);model.pictureExportSize = .instagramPortrait
        model.sceneSettings=SceneSettings(planeColor:RGB(0.1,0.2,0.3),planeDistance:0.7)
        let saved=try XCTUnwrap(model.projectForSaving)
        XCTAssertEqual(saved.settings.backgroundMinimumDistance,27)
        XCTAssertEqual(saved.settings.outputSize,wovenSize)
        XCTAssertEqual(saved.nextOutputSize,nextSize)
        XCTAssertEqual(saved.cameraState,camera);XCTAssertEqual(saved.pictureExportSize,.instagramPortrait)
        XCTAssertEqual(saved.sceneSettings,model.sceneSettings)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("saved.braidart")
        try saved.save(to:url)
        let exported=folder.appendingPathComponent("data")
        try ProjectExporter.export(saved,to:exported)
        let exportedImage=try ImageProcessor.thumbnail(url:exported.appendingPathComponent("result.png"))
        XCTAssertEqual(exportedImage.width,128)
        XCTAssertEqual(exportedImage.height,32)
        func waitForWork() async {
            let deadline=ContinuousClock.now.advanced(by:.seconds(10))
            while model.busy,ContinuousClock.now<deadline { try? await Task.sleep(for:.milliseconds(10)) }
            XCTAssertFalse(model.busy);XCTAssertNil(model.error)
        }
        model.open(url:url);await waitForWork()
        XCTAssertFalse(model.settings.grayscale,"Opening a saved color project restores its mode")
        XCTAssertEqual(model.settings.backgroundMinimumDistance,27)
        XCTAssertEqual(model.settings.outputSize,nextSize)
        XCTAssertEqual(model.resultImage?.size,CGSize(width:128,height:32))
        XCTAssertEqual(model.cameraState,camera);XCTAssertEqual(model.pictureExportSize,.instagramPortrait)
        XCTAssertEqual(model.selectedTab,3)
        XCTAssertEqual(model.projectForSaving?.cameraState,camera)
        XCTAssertFalse(model.canChangeOutputDimensions)
        XCTAssertFalse(SidebarState(model:model).canChangeOutputDimensions)
        model.setOutputSize(wovenSize)
        XCTAssertEqual(model.settings.outputSize,nextSize)
        XCTAssertTrue(model.canWeavePicture)
        XCTAssertEqual(model.resultImage?.size,CGSize(width:128,height:32))
        model.solve()
        await waitForWork()
        XCTAssertEqual(model.project?.settings.outputSize,nextSize)
        XCTAssertEqual(model.resultImage?.size,CGSize(width:96,height:24))
        XCTAssertFalse(model.resultNeedsWeaving)
        XCTAssertNil(model.projectForSaving?.nextOutputSize)
        // Legacy viewport exports inherit the image dimensions when reopened.
        var legacy=saved;legacy.cameraState=nil;legacy.pictureExportSize = .viewport;legacy.nextOutputSize=nil
        try legacy.save(to:url)
        model.open(url:url);await waitForWork()
        XCTAssertEqual(model.settings.outputSize,wovenSize)
        XCTAssertNil(model.cameraState);XCTAssertEqual(model.pictureExportSize,wovenSize)
        XCTAssertNil(model.projectForSaving?.pictureExportSize)
        XCTAssertEqual(model.selectedTab,2)
    }
}
