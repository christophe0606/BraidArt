import XCTest
import AVFoundation
import CoreImage
import VideoTestSupport
@testable import BraidCore

final class VideoTests:XCTestCase {
    private func folder() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("BraidArtVideoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    private func settings(for source:VideoSource) throws -> Settings {
        var settings=Settings();settings.columns=8;settings.partitionSize=8;settings.secondsPerPartition=1;settings.threads=1
        settings.outputSize = .custom(try CustomPictureSize(name:"Test video",width:96,height:64))
        settings.crop=CropGeometry.fitted(Crop(),aspectRatio:CropGeometry.normalizedAspectRatio(for:settings.outputSize,imageSize:source.size))
        return settings
    }
    private func timestamps(_ url:URL) async throws -> [Double] {
        let asset=AVURLAsset(url:url)
        let reader=try AVAssetReader(asset:asset)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        let track=try XCTUnwrap(tracks.first)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output);XCTAssertTrue(reader.startReading())
        var result=[Double]()
        while let sample=output.copyNextSampleBuffer() { result.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
        XCTAssertEqual(reader.status,.completed)
        return result
    }
    func testPreviewSelectsFramesAndPreservesPortraitOrientation() async throws {
        let folder=try folder();defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov")
        try await VideoFixture.make(at:url,rotated:true)
        let source=try await VideoSource.open(url:url)
        XCTAssertTrue(VideoSource.isVideo(url));XCTAssertFalse(VideoSource.isVideo(folder.appendingPathComponent("image.png")))
        XCTAssertEqual(source.size,CGSize(width:48,height:64));XCTAssertEqual(source.duration,1.5,accuracy:0.001)
        let first=try await source.frame(at:0),second=try await source.frame(at:0.25),last=try await source.frame(at:source.lastPreviewTime)
        XCTAssertEqual(first.image.width,48);XCTAssertEqual(first.image.height,64)
        XCTAssertEqual(second.time,0.25,accuracy:0.001);XCTAssertEqual(last.time,1.25,accuracy:0.001)
        XCTAssertNotEqual(try ImageProcessor.pixels(from:first.image),try ImageProcessor.pixels(from:second.image))
    }
    func testEveryFormatEncodesAllFramesWithOriginalTimingAndExactDimensions() async throws {
        let folder=try folder();defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov")
        try await VideoFixture.make(at:url)
        let source=try await VideoSource.open(url:url),settings=try settings(for:source)
        let expectedTimes=try await timestamps(url)
        for format in VideoOutputFormat.allCases {
            let destination=folder.appendingPathComponent("\(format.rawValue).mp4")
            try Data("Old destination".utf8).write(to:destination)
            let report=try await VideoWeaver.write(source:source,settings:settings,format:format,to:destination)
            XCTAssertEqual(report.frames,4)
            let output=try await VideoSource.open(url:destination)
            XCTAssertEqual(output.size,CGSize(width:96,height:64));XCTAssertEqual(output.duration,source.duration,accuracy:0.002)
            let actualTimes=try await timestamps(destination)
            XCTAssertEqual(actualTimes.count,expectedTimes.count)
            for (actual,expected) in zip(actualTimes,expectedTimes) { XCTAssertEqual(actual,expected,accuracy:0.001) }
            let tracks=try await AVURLAsset(url:destination).loadTracks(withMediaType:.video)
            let track=try XCTUnwrap(tracks.first)
            let descriptions=try await track.load(.formatDescriptions)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(descriptions.first)),format == .h265 ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains{$0.hasPrefix(".braidart-video-")})
    }
    func testPortraitFrameProcessingMatchesPictureWeaveAndPreservesAudio() async throws {
        let folder=try folder();defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("portrait.mov"),destination=folder.appendingPathComponent("woven.mp4")
        try await VideoFixture.make(at:url,rotated:true,audio:true)
        let source=try await VideoSource.open(url:url),settings=try settings(for:source)
        let frame=try await source.frame(at:0)
        let prepared=try ImageProcessor.prepare(image:frame.image,settings:settings)
        let (data,result)=try await PartitionSolver.solve(image:prepared,settings:settings)
        let expected=try ImageProcessor.pixels(from:TileRenderer.render(solution:result.solution,data:data,pixelSize:settings.outputPixelSize))
        _=try await VideoWeaver.write(source:source,settings:settings,format:.mostCompatible,to:destination)
        let output=try await VideoSource.open(url:destination),actualFrame=try await output.frame(at:0)
        let actual=try ImageProcessor.pixels(from:actualFrame.image)
        let error=zip(expected.pixels,actual.pixels).reduce(0.0) { $0+abs($1.0.r-$1.1.r)+abs($1.0.g-$1.1.g)+abs($1.0.b-$1.1.b) }/Double(expected.pixels.count*3)
        XCTAssertLessThan(error,0.05,"A portrait video frame must use the same oriented crop and processing as a picture")
        let asset=AVURLAsset(url:destination),audio=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(audio.count,1)
        let reader=try AVAssetReader(asset:asset),audioOutput=AVAssetReaderTrackOutput(track:try XCTUnwrap(audio.first),outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM])
        reader.add(audioOutput);XCTAssertTrue(reader.startReading())
        XCTAssertNotNil(audioOutput.copyNextSampleBuffer());reader.cancelReading()
        let silent=folder.appendingPathComponent("silent.mp4")
        _=try await VideoWeaver.write(source:source,settings:settings,format:.mostCompatible,includeAudio:false,to:silent)
        let silentTracks=try await AVURLAsset(url:silent).loadTracks(withMediaType:.audio)
        XCTAssertTrue(silentTracks.isEmpty,"Disabling audio must produce a movie with no audio track")
    }
    func testCancellationPreservesExistingDestinationAndRemovesPartialVideo() async throws {
        let folder=try folder();defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov"),destination=folder.appendingPathComponent("cancelled.mp4")
        try await VideoFixture.make(at:url,audio:true)
        let source=try await VideoSource.open(url:url),settings=try settings(for:source),sentinel=Data("Keep existing file".utf8)
        try sentinel.write(to:destination)
        for threshold in [0.12,0.97] {
            let task=Task {
                try await VideoWeaver.write(source:source,settings:settings,format:.mostCompatible,to:destination) { value,_ in
                    if value>threshold { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
            XCTAssertEqual(try Data(contentsOf:destination),sentinel)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains{$0.hasPrefix(".braidart-video-")})
        }
    }
    func testRejectsInvalidVideoDimensionsAndSourceOverwrite() async throws {
        let folder=try folder();defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov")
        try await VideoFixture.make(at:url)
        let source=try await VideoSource.open(url:url),before=try Data(contentsOf:url)
        var settings=try settings(for:source)
        do {
            _=try await VideoWeaver.write(source:source,settings:settings,format:.mostCompatible,to:url)
            XCTFail("Must not overwrite source")
        } catch {}
        XCTAssertEqual(try Data(contentsOf:url),before)
        settings.outputSize = .custom(try CustomPictureSize(name:"Odd pixels",width:97,height:65))
        XCTAssertThrowsError(try VideoWeaver.validate(settings:settings))
        for (start,end) in [(0.0,0.0),(-1.0,1.0),(1.0,0.0),(Double.nan,1.0)] {
            XCTAssertThrowsError(try VideoSegment(start:start,end:end))
        }
        XCTAssertThrowsError(try VideoSegment(start:0,end:2).validate(sourceDuration:source.duration))
    }
    func testTrimmedSegmentKeepsItsLeadingFrameTimingAndAudio() async throws {
        let folder=try folder();defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("source.mov")
        try await VideoFixture.make(at:url,audio:true)
        let source=try await VideoSource.open(url:url),settings=try settings(for:source)
        for (index,range) in [(0,(0.1,1.1)),(1,(0.3,0.4)),(2,(0.75,1.5))] {
            let segment=try VideoSegment(start:range.0,end:range.1),destination=folder.appendingPathComponent("clip-\(index).mp4")
            let report=try await VideoWeaver.write(source:source,settings:settings,format:.mostCompatible,segment:segment,to:destination)
            let actual=try await timestamps(destination)
            let expected = index==0 ? [0,0.15,0.65] : index==1 ? [0] : [0,0.5]
            XCTAssertEqual(report.frames,expected.count);XCTAssertEqual(actual.count,expected.count)
            for (a,e) in zip(actual,expected) { XCTAssertEqual(a,e,accuracy:0.001) }
            let output=try await VideoSource.open(url:destination)
            XCTAssertEqual(output.duration,segment.duration,accuracy:0.003)
            let track=try await AVURLAsset(url:destination).loadTracks(withMediaType:.audio)
            XCTAssertEqual(track.count,1)
            let sourceFrame=try await source.frame(at:segment.start),outputFrame=try await output.frame(at:0)
            let prepared=try ImageProcessor.prepare(image:sourceFrame.image,settings:settings)
            let (data,result)=try await PartitionSolver.solve(image:prepared,settings:settings)
            let rendered=try ImageProcessor.pixels(from:TileRenderer.render(solution:result.solution,data:data,pixelSize:settings.outputPixelSize))
            let pixels=try ImageProcessor.pixels(from:outputFrame.image)
            let error=zip(rendered.pixels,pixels.pixels).reduce(0.0) { $0+abs($1.0.r-$1.1.r)+abs($1.0.g-$1.1.g)+abs($1.0.b-$1.1.b) }/Double(rendered.pixels.count*3)
            XCTAssertLessThan(error,0.05)
        }
    }
}
