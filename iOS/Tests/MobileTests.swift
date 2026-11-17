import XCTest
import UIKit
import AVFoundation
import BraidCore
@testable import BraidArt

@MainActor
final class MobileTests:XCTestCase {
    func testSharedHelpImagesAreBundledAndReadable() throws {
        for illustration in HelpIllustration.allCases {
            let url=try XCTUnwrap(illustration.url,"Missing \(illustration.rawValue)")
            XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
            let image=try XCTUnwrap(illustration.image)
            XCTAssertGreaterThan(image.size.width,0);XCTAssertGreaterThan(image.size.height,0)
        }
        XCTAssertEqual(HelpBookReference.url.absoluteString,"https://press.princeton.edu/books/hardcover/9780691164069/opt-art")
    }
    private func wovenModel() async throws -> AppModel {
        let model=AppModel(defaults:UserDefaults(suiteName:UUID().uuidString)!)
        model.settings.columns=8;model.settings.partitionSize=2;model.settings.threads=1
        model.settings.outputSize = .custom(try CustomPictureSize(name:"Test",width:128,height:128))
        let image=PixelImage(width:8,height:8,pixels:(0..<64).map { RGB(Double($0%8)/7,Double($0/8)/7,0.3) })
        let (tiles,result)=try await PartitionSolver.solve(image:image,settings:model.settings)
        let curves=try CurveGenerator.generate(solution:result.solution,data:tiles)
        model.project=BraidProject(sourceName:"fixture.png",settings:model.settings,sampledImage:image,tileData:tiles,result:result)
        model.curves=curves;model.meshes=try TubeMesher.build(curves)
        return model
    }
    private func completedFile(_ model:AppModel) async throws -> URL {
        for _ in 0..<200 {
            if let error=model.error { XCTFail(error);break }
            if let file=model.exportedFile { return file.url }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw BraidError.invalid("Export did not complete")
    }
    func testNativeSolverAndPictureDestinationChoice() async throws {
        let model=try await wovenModel()
        try model.project!.result.validate(tileData:model.project!.tileData)
        model.exportPNG()
        let request=try XCTUnwrap(model.mobileExport)
        XCTAssertTrue(request.allowsPhotos)
        XCTAssertNil(model.exportedFile)
        request.start(.files)
        let url=try await completedFile(model)
        let image=try XCTUnwrap(UIImage(contentsOfFile:url.path)?.cgImage)
        XCTAssertEqual(image.width,128);XCTAssertEqual(image.height,128)
        model.finishFileExport(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    }
    func testPDFAndObjectsGoDirectlyToFiles() async throws {
        let model=try await wovenModel()
        for kind in ["pdf","glb","usdz"] {
            switch kind { case "pdf": model.exportPDF();case "glb": model.exportGLB();default: model.exportUSDZ() }
            XCTAssertNil(model.mobileExport,"\(kind) must not offer Photos")
            let url=try await completedFile(model)
            XCTAssertEqual(url.pathExtension,kind)
            XCTAssertGreaterThan(try Data(contentsOf:url).count,100)
            model.finishFileExport(false)
        }
    }
    func testVideoWorkflowAndDestinationChoice() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let source=folder.appendingPathComponent("fixture.mov")
        try await VideoFixture.make(at:source,audio:true)
        let model=AppModel()
        model.settings.columns=8;model.settings.partitionSize=2;model.settings.threads=1
        model.settings.outputSize = .custom(try CustomPictureSize(name:"Test",width:128,height:128))
        model.open(url:source)
        for _ in 0..<200 {
            if model.canWeavePicture { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertTrue(model.canWeavePicture)
        model.solve()
        for _ in 0..<200 {
            if model.canWeaveVideo { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertTrue(model.canWeaveVideo)
        model.weaveVideo()
        let request=try XCTUnwrap(model.mobileExport)
        XCTAssertTrue(request.allowsPhotos)
        request.start(.files)
        let url=try await completedFile(model)
        let asset=AVURLAsset(url:url)
        let video=try await asset.loadTracks(withMediaType:.video)
        let audio=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(video.count,1);XCTAssertEqual(audio.count,1)
        let size=try await video.first!.load(.naturalSize)
        XCTAssertEqual(size.width,128);XCTAssertEqual(size.height,128)
        model.finishFileExport(false)
    }
    func testTouchConfigurationCameraAndPictureCapture() async throws {
        let model=try await wovenModel()
        let view=BraidMetalView(frame:CGRect(x:0,y:0,width:800,height:500))
        view.display(model.curves!,meshes:model.meshes,settings:model.sceneSettings)
        let pans=(view.gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer }
        XCTAssertTrue(pans.contains { $0.minimumNumberOfTouches==1 && $0.maximumNumberOfTouches==1 })
        XCTAssertTrue(pans.contains { $0.minimumNumberOfTouches==2 && $0.maximumNumberOfTouches==2 })
        XCTAssertEqual(view.gestureRecognizers?.filter { $0 is UIPinchGestureRecognizer && $0.isEnabled }.count,1)
        let initial=view.cameraState
        view.orbit(dx:0.2,dy:0.1)
        XCTAssertNotEqual(view.cameraState.orbitYaw,initial.orbitYaw)
        view.pan(dx:80,dy:30)
        XCTAssertNotEqual(view.cameraState.target,initial.target)
        XCTAssertEqual(view.cameraState.orbitYaw,0.2,accuracy:0.001)
        view.zoom(factor:0.5)
        XCTAssertEqual(view.cameraState.cameraDistance,initial.cameraDistance/2,accuracy:0.01)
        let before=view.cameraState
        let capture=try view.makePictureCapture()
        let picture=try await Task.detached { try capture.render(size:CGSize(width:320,height:180)) }.value
        XCTAssertEqual(picture.width,320);XCTAssertEqual(picture.height,180)
        XCTAssertEqual(view.cameraState,before)
    }
}
