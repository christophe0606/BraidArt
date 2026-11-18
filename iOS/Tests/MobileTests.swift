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
    private func completedFile(_ model:AppModel) async throws -> MobileExportFile {
        for _ in 0..<200 {
            if let error=model.error { XCTFail(error);break }
            if let file=model.exportedFile { return file }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw BraidError.invalid("Export did not complete")
    }
    func testNativeSolverAndShareablePicture() async throws {
        let model=try await wovenModel()
        try model.project!.result.validate(tileData:model.project!.tileData)
        model.sourceImage=try ImageProcessor.cgImage(model.project!.sampledImage).platformImage
        let nextSize = PictureExportSize.custom(try CustomPictureSize(name:"Next",width:192,height:96))
        model.setOutputSize(nextSize)
        XCTAssertEqual(model.settings.outputSize,nextSize)
        model.exportPNG()
        let file=try await completedFile(model)
        let image=try XCTUnwrap(UIImage(contentsOfFile:file.url.path)?.cgImage)
        XCTAssertEqual(image.width,128);XCTAssertEqual(image.height,128)
        model.finishFileExport(file, completed:false, error:nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.url.path))
    }
    func testShareablePDFObjectsAndDataArchive() async throws {
        let model=try await wovenModel()
        let exports = [("pdf", model.exportPDF), ("glb", model.exportGLB), ("usdz", model.exportUSDZ), ("zip", model.exportData)]
        for (suffix, export) in exports {
            export()
            let file=try await completedFile(model)
            XCTAssertEqual(file.url.pathExtension,suffix)
            let data = try Data(contentsOf:file.url)
            XCTAssertGreaterThan(data.count,100)
            if suffix == "zip" {
                XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
                XCTAssertNotNil(data.range(of: Data("solution.json".utf8)))
                XCTAssertNotNil(data.range(of: Data("project.braidart".utf8)))
            }
            model.finishFileExport(file, completed:true, error:nil)
            XCTAssertFalse(FileManager.default.fileExists(atPath:file.url.path))
        }
    }
    func testVideoWorkflowAndShareableMP4() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let model=try await videoModel(in:folder)
        model.weaveVideo()
        let file=try await completedFile(model)
        let asset=AVURLAsset(url:file.url)
        let video=try await asset.loadTracks(withMediaType:.video)
        let audio=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(video.count,1);XCTAssertEqual(audio.count,1)
        let size=try await video.first!.load(.naturalSize)
        XCTAssertEqual(size.width,128);XCTAssertEqual(size.height,128)
        model.finishFileExport(file, completed:false, error:nil)
    }

    func testSharedPhotoAndVideoOpenInPrepare() async throws {
        let fm = FileManager.default
        let folder = try SharedMediaInbox().root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:folder) }
        let inbox = SharedMediaInbox(root: folder.appendingPathComponent("TestInbox"))
        let picture = folder.appendingPathComponent("shared-picture.png")
        let movie = folder.appendingPathComponent("shared-video.mov")
        try ImageProcessor.writePNG(ImageProcessor.cgImage(PixelImage(width: 8, height: 8, pixels: Array(repeating: .gray, count: 64))), to: picture)
        try await VideoFixture.make(at: movie, audio: false)
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model.settings.columns = 8
        for source in [picture, movie] {
            let staged = try inbox.stage(source, filename: source.lastPathComponent)
            XCTAssertNil(try inbox.takeNext(), "Wait until the extension publishes the complete file")
            try inbox.enqueue(staged)
            model.selectedTab = 1
            model.openNextSharedMedia(from: inbox)
            for _ in 0..<100 {
                if !model.busy { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertNil(model.error)
            XCTAssertEqual(model.sourceName, source.lastPathComponent)
            XCTAssertEqual(model.selectedTab, 0)
            XCTAssertTrue(model.canWeavePicture)
            XCTAssertEqual(model.videoSource != nil, source == movie)
            XCTAssertNil(try inbox.takeNext())
        }
    }
    private func videoModel(in folder:URL) async throws -> AppModel {
        let source=folder.appendingPathComponent("fixture.mov")
        try await VideoFixture.make(at:source,audio:true)
        let model=AppModel(defaults:UserDefaults(suiteName:UUID().uuidString)!)
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
        return model
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
        view.pan(dx: 80, dy: 30)
        XCTAssertLessThan(view.cameraState.target.x, initial.target.x)
        XCTAssertLessThan(view.cameraState.target.y, initial.target.y)
        view.pan(dx: -80, dy: -30)
        XCTAssertEqual(view.cameraState.target.x, initial.target.x, accuracy: 0.0001)
        XCTAssertEqual(view.cameraState.target.y, initial.target.y, accuracy: 0.0001)
        view.orbit(dx:0.2,dy:0.1)
        XCTAssertNotEqual(view.cameraState.orbitYaw,initial.orbitYaw)
        view.pan(dx:80,dy:30)
        XCTAssertNotEqual(view.cameraState.target,initial.target)
        XCTAssertEqual(view.cameraState.orbitYaw,0.2,accuracy:0.001)
        view.zoom(factor:0.5)
        XCTAssertEqual(view.cameraState.cameraDistance,initial.cameraDistance/2,accuracy:0.01)
        let before=view.cameraState
        XCTAssertEqual(model.pictureExportSize,model.settings.outputSize)
        model.pictureExportSize = .custom(try CustomPictureSize(name:"Capture",width:320,height:180))
        model.selectedTab=3
        model.register3DView(view)
        model.export3DPicture()
        let file=try await completedFile(model)
        let picture=try XCTUnwrap(UIImage(contentsOfFile:file.url.path)?.cgImage)
        XCTAssertEqual(picture.width,320);XCTAssertEqual(picture.height,180)
        model.finishFileExport(file, completed:false, error:nil)
        XCTAssertEqual(view.cameraState,before)
        var adjusted=before
        adjusted.fieldOfView=60
        try view.restoreCamera(adjusted)
        view.orbit(dx:0,dy:0.9)
        view.orbit(dx:1.3,dy:0)
        model.cameraChanged(view.cameraState)
        model.resetCamera()
        XCTAssertNil(model.cameraState)
        let braid=try XCTUnwrap(model.curves)
        view.fit(columns:braid.columns,rows:braid.rows)
        XCTAssertEqual(view.cameraState,initial)
        XCTAssertEqual(view.cameraNode.simdWorldUp.x,0,accuracy:0.00001)
        XCTAssertEqual(view.cameraNode.simdWorldUp.y,1,accuracy:0.00001)
        XCTAssertEqual(view.cameraNode.simdWorldRight.y,0,accuracy:0.00001)
    }
}
