import Foundation
import AVFoundation
import CoreGraphics
import UniformTypeIdentifiers

public struct VideoFrame: @unchecked Sendable {
    public let image:CGImage
    public let time:Double
}

public struct VideoSource:Sendable,Equatable {
    public let url:URL
    public let duration:Double
    public let frameRate:Double
    public let size:CGSize
    public var lastPreviewTime:Double { max(0,duration-min(0.001,duration/2)) }

    public static func isVideo(_ url:URL)->Bool {
        let type=(try? url.resourceValues(forKeys:[.contentTypeKey]))?.contentType ?? UTType(filenameExtension:url.pathExtension)
        return type?.conforms(to:.movie) == true || type?.conforms(to:.video) == true
    }
    public static func open(url:URL) async throws -> Self {
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.video).first else {
            throw BraidError.invalid(L("This file does not contain a video track."))
        }
        let duration=try await asset.load(.duration).seconds
        let (natural,transform,rate)=try await track.load(.naturalSize,.preferredTransform,.nominalFrameRate)
        let size=natural.applying(transform)
        guard duration.isFinite,duration>0,abs(size.width)>0,abs(size.height)>0 else {
            throw BraidError.invalid(L("This video has invalid dimensions or duration."))
        }
        return Self(url:url,duration:duration,frameRate:rate>0 ? Double(rate) : 30,
                    size:CGSize(width:abs(size.width),height:abs(size.height)))
    }
    public func frame(at seconds:Double) async throws -> VideoFrame {
        try Task.checkCancellation()
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url))
        generator.appliesPreferredTrackTransform=true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time=CMTime(seconds:min(lastPreviewTime,max(0,seconds)),preferredTimescale:600_000)
        return try await withTaskCancellationHandler {
            let result=try await generator.image(at:time)
            try Task.checkCancellation()
            return VideoFrame(image:result.image,time:result.actualTime.seconds)
        } onCancel: { generator.cancelAllCGImageGeneration() }
    }
}
