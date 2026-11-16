import XCTest
import AVFoundation
import VideoTestSupport
import BraidCore
import Combine
@testable import BraidArt

final class VideoWorkflowTests:XCTestCase {
    @MainActor private func wait(_ model:AppModel) async throws {
        let deadline=ContinuousClock.now.advanced(by:.seconds(30))
        while model.busy,ContinuousClock.now<deadline { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertFalse(model.busy);XCTAssertNil(model.error)
    }
    @MainActor func testFrameSelectionCropCheckedSettingsAndDirectVideoSave() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("BraidArtWorkflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov"),output=folder.appendingPathComponent("woven.mp4")
        try await VideoFixture.make(at:url,audio:true)
        let model=AppModel();model.settings.columns=8;model.settings.partitionSize=8;model.settings.secondsPerPartition=1
        model.settings.outputSize = .custom(try CustomPictureSize(name:"Video test",width:96,height:64))
        model.open(url:url);try await wait(model)
        XCTAssertNotNil(model.videoSource);XCTAssertTrue(model.hasCropSelection);XCTAssertFalse(model.canWeaveVideo)
        XCTAssertEqual(model.settings.crop,CropGeometry.fitted(Crop(),aspectRatio:model.cropAspectRatio))
        let crop=CropGeometry.scaled(model.settings.crop,by:0.7)
        model.settings.crop=crop
        model.selectVideoFrame(at:0.25)
        XCTAssertFalse(model.preparedIsCurrent)
        model.solve();XCTAssertNil(model.project,"Cannot weave the old frame while selection is loading")
        try await wait(model)
        XCTAssertEqual(model.settings.crop,crop);XCTAssertEqual(model.selectedFrameTime,0.25,accuracy:0.001)
        let expectedFrame=try await XCTUnwrap(model.videoSource).frame(at:0.25)
        let expected=try ImageProcessor.prepare(image:expectedFrame.image,settings:model.settings)
        XCTAssertEqual(model.prepared,expected);XCTAssertTrue(model.preparedIsCurrent)
        model.selectVideoFrame(at:0);model.selectVideoFrame(at:0.75);model.selectVideoFrame(at:1.25)
        try await wait(model)
        XCTAssertEqual(model.selectedFrameTime,1.25,accuracy:0.001)
        model.solve();try await wait(model)
        XCTAssertEqual(model.selectedTab,2);XCTAssertTrue(model.canWeaveVideo)
        XCTAssertEqual(model.project?.sampledImage,model.prepared,"The woven picture must use the selected video frame")
        let checked=model.settings
        model.settings.brightness=0.1
        XCTAssertFalse(model.canWeaveVideo,"Changed settings must be checked on another frame before a long video run")
        model.settings=checked
        XCTAssertTrue(model.canWeaveVideo)
        XCTAssertTrue(model.videoIncludeAudio)
        model.videoIncludeAudio=false
        model.startVideoExport(to:output)
        XCTAssertTrue(model.busy);XCTAssertNotNil(model.exportProgress)
        try await wait(model)
        XCTAssertNil(model.exportProgress);XCTAssertTrue(FileManager.default.fileExists(atPath:output.path))
        let video=try await VideoSource.open(url:output)
        XCTAssertEqual(video.size,CGSize(width:96,height:64));XCTAssertEqual(video.duration,1.5,accuracy:0.002)
        let audio=try await AVURLAsset(url:output).loadTracks(withMediaType:.audio)
        XCTAssertTrue(audio.isEmpty)
        let cancelled=folder.appendingPathComponent("cancelled.mp4")
        model.startVideoExport(to:cancelled);model.cancel();try await wait(model)
        XCTAssertNil(model.exportProgress);XCTAssertFalse(FileManager.default.fileExists(atPath:cancelled.path))
        let imageURL=folder.appendingPathComponent("still.png")
        try ImageProcessor.writePNG(ImageProcessor.cgImage(VideoFixture.pixels(0)),to:imageURL)
        model.open(url:imageURL);try await wait(model)
        XCTAssertNil(model.videoSource);XCTAssertFalse(model.canWeaveVideo)
    }
    @MainActor func testLoopingSegmentAllowsCropChangesAndWeavesTheCurrentFrame() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("BraidArtLoop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov")
        try await VideoFixture.make(at:url)
        let model=AppModel();model.videoIncludeAudio=false;model.settings.columns=8;model.settings.partitionSize=8;model.settings.secondsPerPartition=1
        model.settings.outputSize = .custom(try CustomPictureSize(name:"Video test",width:96,height:64))
        model.open(url:url);try await wait(model)
        model.setVideoSegment(start:0.25,end:0.75);try await wait(model)
        let playback=try XCTUnwrap(model.videoPlayback)
        var times=[Double]()
        let token=playback.$position.sink { times.append($0) }
        defer { token.cancel();playback.invalidate() }
        playback.play()
        XCTAssertTrue(model.isPlayingVideo);XCTAssertTrue(model.canWeavePicture)
        let crop=CropGeometry.scaled(model.settings.crop,by:0.65)
        model.settings.crop=crop;model.settingsChanged()
        XCTAssertFalse(model.blocksEditing);XCTAssertFalse(model.busy)
        let deadline=ContinuousClock.now.advanced(by:.seconds(6))
        var loops=0
        while ContinuousClock.now<deadline,loops<2 {
            try await Task.sleep(for:.milliseconds(50))
            loops=zip(times,times.dropFirst()).filter{$0.0-$0.1>0.2}.count
        }
        XCTAssertGreaterThanOrEqual(loops,2,"The selected segment must loop repeatedly until paused")
        XCTAssertTrue(playback.isPlaying);XCTAssertTrue(model.isPlayingVideo)
        XCTAssertEqual(model.settings.crop,crop)
        model.solve();try await wait(model)
        XCTAssertFalse(playback.isPlaying);XCTAssertFalse(model.isPlayingVideo)
        XCTAssertTrue(model.canWeaveVideo);XCTAssertEqual(model.project?.settings.crop,crop)
        XCTAssertGreaterThanOrEqual(model.videoFrameTime,0.25);XCTAssertLessThan(model.videoFrameTime,0.75)
        let output=folder.appendingPathComponent("trimmed.mp4")
        model.startVideoExport(to:output);try await wait(model)
        let clip=try await VideoSource.open(url:output)
        XCTAssertEqual(clip.duration,0.5,accuracy:0.003)
        model.setVideoSegment(start:0.8,end:1.4);try await wait(model)
        XCTAssertFalse(model.canWeaveVideo,"A new segment must contain the checked test frame")
        model.selectVideoFrame(at:0);try await wait(model)
        XCTAssertEqual(model.videoFrameTime,0.8,accuracy:0.001)
    }
}
