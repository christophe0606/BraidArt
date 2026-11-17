import Foundation
import AVFoundation
import CoreImage
import AudioToolbox
import VideoToolbox

public enum VideoOutputFormat:String,CaseIterable,Identifiable,Sendable {
    case mostCompatible,h264,h265
    public var id:Self { self }
    public var title:String {
        switch self {
        case .mostCompatible: return L("Most compatible (H.264 / MP4)")
        case .h264: return L("H.264 High Profile (MP4)")
        case .h265: return L("H.265 / HEVC (MP4)")
        }
    }
    public var codec:AVVideoCodecType { self == .h265 ? .hevc : .h264 }
    var profile:String {
        switch self {
        case .mostCompatible: return AVVideoProfileLevelH264BaselineAutoLevel
        case .h264: return AVVideoProfileLevelH264HighAutoLevel
        case .h265: return kVTProfileLevel_HEVC_Main_AutoLevel as String
        }
    }
}

public struct VideoWeaveReport:Sendable {
    public let frames:Int
    public let duration:Double
}

public enum VideoWeaver {
    public static func validate(settings:Settings) throws {
        try settings.validate()
        let size=settings.outputPixelSize
        guard (16...8192).contains(size.width),(16...8192).contains(size.height),
              Int(size.width)%2==0,Int(size.height)%2==0 else {
            throw BraidError.invalid(L("Video output width and height must be even numbers between 16 and 8192 pixels. Choose different output dimensions."))
        }
    }
    /// Decode and solve one frame at a time. Only the completed movie replaces
    /// the destination; a cancelled or failed run removes its temporary output.
    public static func write(source:VideoSource,settings:Settings,format:VideoOutputFormat,includeAudio:Bool=true,segment requestedSegment:VideoSegment?=nil,to destination:URL,
                             progress:@escaping @Sendable (Double,String) async -> Void = {_,_ in}) async throws -> VideoWeaveReport {
        try validate(settings:settings);try Task.checkCancellation()
        let segment=try requestedSegment ?? VideoSegment(start:0,end:source.duration)
        try segment.validate(sourceDuration:source.duration)
        guard source.url.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
            throw BraidError.invalid(L("Choose a different file from the source video."))
        }
        let asset=AVURLAsset(url:source.url)
        guard let track=try await asset.loadTracks(withMediaType:.video).first else {
            throw BraidError.invalid(L("This file does not contain a video track."))
        }
        let preferredTransform=try await track.load(.preferredTransform)
        // Track transforms use top-left video coordinates; Core Image uses a
        // bottom-left origin. Convert both sides so portrait crops match preview.
        let flip=CGAffineTransform(scaleX:1,y:-1)
        let transform=flip.concatenating(preferredTransform).concatenating(flip)
        let temporary=destination.deletingLastPathComponent().appendingPathComponent(".braidart-video-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at:temporary) }
        let writer=try AVAssetWriter(outputURL:temporary,fileType:.mp4)
        let size=settings.outputPixelSize
        let videoSettings:[String:Any]=[AVVideoCodecKey:format.codec,AVVideoWidthKey:Int(size.width),AVVideoHeightKey:Int(size.height),
            AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:Int(max(1_000_000,min(80_000_000,size.width*size.height*source.frameRate*0.12))),
                AVVideoProfileLevelKey:format.profile,AVVideoExpectedSourceFrameRateKey:source.frameRate]]
        guard writer.canApply(outputSettings:videoSettings,forMediaType:.video) else {
            throw BraidError.invalid(L("This video format is unavailable at the selected dimensions. Try another format or smaller dimensions."))
        }
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:videoSettings)
        input.expectsMediaDataInRealTime=false
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:Int(size.width),kCVPixelBufferHeightKey as String:Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        guard writer.canAdd(input) else { throw BraidError.invalid(L("Cannot create the video encoder.")) }
        writer.add(input)
        let reader=try AVAssetReader(asset:asset)
        reader.timeRange=CMTimeRange(start:CMTime(seconds:segment.start,preferredTimescale:600_000),duration:CMTime(seconds:segment.duration,preferredTimescale:600_000))
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData=false
        guard reader.canAdd(output) else { throw BraidError.invalid(L("Cannot decode the source video.")) }
        reader.add(output)
        let audio=includeAudio ? try await AudioStream.make(asset:asset,writer:writer,segment:segment) : nil
        defer {
            reader.cancelReading();audio?.reader.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
        }
        // Reader start/copy calls stay on their owning task. Cancelling a reader
        // concurrently with startReading can crash inside AVFoundation.
        func process() async throws -> VideoWeaveReport {
            guard writer.startWriting(),reader.startReading() else { throw writer.error ?? reader.error ?? BraidError.invalid(L("Cannot start video processing.")) }
            writer.startSession(atSourceTime:.zero)
            async let audioWriting:Void=appendAudio(audio,writer:writer,segment:segment)
            let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.sRGB)!, .cacheIntermediates:false])
            var count=0
            func appendFrame(_ image:CIImage,at time:Double,until frameEnd:Double) async throws {
                try Task.checkCancellation()
                let sampled=try autoreleasepool { try ImageProcessor.prepare(image:image,settings:settings) }
                let frameNumber=count+1
                let (data,result)=try await PartitionSolver.solve(image:sampled,settings:settings) { fraction,message in
                    let start=max(segment.start,time)
                    let fractionOfMovie=(start-segment.start+fraction*max(0,frameEnd-start))/segment.duration
                    await progress(min(0.95,fractionOfMovie*0.95),L("Frame %@ · %@",String(frameNumber),message))
                }
                try Task.checkCancellation()
                let rendered=try autoreleasepool { try TileRenderer.render(solution:result.solution,data:data,pixelSize:size) }
                try await ready(input,writer:writer)
                guard let pool=adaptor.pixelBufferPool else { throw BraidError.invalid(L("Cannot allocate a video frame.")) }
                var pixelBuffer:CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&pixelBuffer)==kCVReturnSuccess,let pixelBuffer else {
                    throw BraidError.invalid(L("Cannot allocate a video frame."))
                }
                context.render(CIImage(cgImage:rendered),to:pixelBuffer,bounds:CGRect(origin:.zero,size:size),colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
                let outputTime=CMTime(seconds:max(0,time-segment.start),preferredTimescale:600_000)
                guard adaptor.append(pixelBuffer,withPresentationTime:outputTime) else { throw writer.error ?? BraidError.invalid(L("Cannot encode a video frame.")) }
                count+=1
            }
            var current=output.copyNextSampleBuffer()
            // If trimming between frames, retain the frame visible at the start
            // without decoding every earlier frame in a long source movie.
            if current == nil || CMSampleBufferGetPresentationTimeStamp(current!).seconds>segment.start+0.000001 {
                let leading=try await source.frame(at:segment.start)
                let end=current.map { min(segment.end,CMSampleBufferGetPresentationTimeStamp($0).seconds) } ?? segment.end
                try await appendFrame(CIImage(cgImage:leading.image),at:segment.start,until:end)
            }
            while let sample=current {
                try Task.checkCancellation()
                let next=output.copyNextSampleBuffer()
                let time=CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if time<segment.end {
                    guard let buffer=CMSampleBufferGetImageBuffer(sample) else { throw BraidError.invalid(L("Cannot decode the source video.")) }
                    let end=next.map { min(segment.end,CMSampleBufferGetPresentationTimeStamp($0).seconds) } ?? segment.end
                    try await appendFrame(CIImage(cvPixelBuffer:buffer).transformed(by:transform),at:max(segment.start,time),until:end)
                }
                current=next
            }
            try Task.checkCancellation()
            guard reader.status == .completed,count>0 else { throw reader.error ?? BraidError.invalid(L("Cannot decode the source video.")) }
            input.markAsFinished()
            try await audioWriting
            await progress(0.98,L("Finishing video…"))
            try Task.checkCancellation()
            writer.endSession(atSourceTime:CMTime(seconds:segment.duration,preferredTimescale:600_000))
            // Finish the small buffered tail on its owning task, then honor any
            // cancellation before replacing the destination.
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? BraidError.invalid(L("Cannot finish the video file.")) }
            if FileManager.default.fileExists(atPath:destination.path) {
                _=try FileManager.default.replaceItemAt(destination,withItemAt:temporary)
            } else { try FileManager.default.moveItem(at:temporary,to:destination) }
            await progress(1,L("Video saved."))
            return VideoWeaveReport(frames:count,duration:segment.duration)
        }
        return try await process()
    }

    private static func ready(_ input:AVAssetWriterInput,writer:AVAssetWriter) async throws {
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else { throw writer.error ?? BraidError.invalid(L("The video encoder stopped.")) }
            try await Task.sleep(for:.milliseconds(10))
        }
        try Task.checkCancellation()
    }
    private struct AudioStream {
        let reader:AVAssetReader
        let output:AVAssetReaderTrackOutput
        let input:AVAssetWriterInput
        static func make(asset:AVAsset,writer:AVAssetWriter,segment:VideoSegment) async throws -> Self? {
            let tracks=try await asset.loadTracks(withMediaType:.audio)
            guard let track=tracks.first else { return nil }
            let reader=try AVAssetReader(asset:asset)
            reader.timeRange=CMTimeRange(start:CMTime(seconds:segment.start,preferredTimescale:600_000),duration:CMTime(seconds:segment.duration,preferredTimescale:600_000))
            let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,
                AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:16,
                AVLinearPCMIsFloatKey:false,AVLinearPCMIsNonInterleaved:false])
            let input=AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,
                AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVEncoderBitRateKey:192000])
            input.expectsMediaDataInRealTime=false
            guard reader.canAdd(output),writer.canAdd(input) else { throw BraidError.invalid(L("Cannot preserve the source audio.")) }
            reader.add(output);writer.add(input)
            return Self(reader:reader,output:output,input:input)
        }
    }
    private static func appendAudio(_ stream:AudioStream?,writer:AVAssetWriter,segment:VideoSegment) async throws {
        guard let stream else { return }
        guard stream.reader.startReading() else { throw stream.reader.error ?? BraidError.invalid(L("Cannot preserve the source audio.")) }
        while let sample=stream.output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            if CMSampleBufferGetPresentationTimeStamp(sample).seconds>=segment.end { break }
            try await ready(stream.input,writer:writer)
            let shifted=try shiftedAudio(sample,by:CMTime(seconds:segment.start,preferredTimescale:600_000))
            guard stream.input.append(shifted) else { throw writer.error ?? BraidError.invalid(L("Cannot preserve the source audio.")) }
        }
        if stream.reader.status == .failed { throw stream.reader.error ?? BraidError.invalid(L("Cannot preserve the source audio.")) }
        stream.input.markAsFinished()
    }
    private static func shiftedAudio(_ sample:CMSampleBuffer,by offset:CMTime) throws -> CMSampleBuffer {
        var count=0
        CMSampleBufferGetSampleTimingInfoArray(sample,entryCount:0,arrayToFill:nil,entriesNeededOut:&count)
        var timing=Array(repeating:CMSampleTimingInfo(),count:count)
        CMSampleBufferGetSampleTimingInfoArray(sample,entryCount:count,arrayToFill:&timing,entriesNeededOut:&count)
        for i in timing.indices {
            timing[i].presentationTimeStamp=CMTimeSubtract(timing[i].presentationTimeStamp,offset)
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp=CMTimeSubtract(timing[i].decodeTimeStamp,offset) }
        }
        var shifted:CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:sample,sampleTimingEntryCount:count,sampleTimingArray:&timing,sampleBufferOut:&shifted)==noErr,let shifted else {
            throw BraidError.invalid(L("Cannot preserve the source audio."))
        }
        return shifted
    }
}
