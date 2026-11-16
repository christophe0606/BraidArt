import Foundation
import AVFoundation
import CoreImage
import AudioToolbox
import BraidCore

/// Original synthetic frames and a generated tone; no external media assets.
public enum VideoFixture {
    public static let times:[Double]=[0,0.25,0.75,1.25]
    public static let duration=1.5
    public static func pixels(_ index:Int)->PixelImage {
        let colors:[RGB]=[.black,.white,RGB(1,0,0),RGB(0,0,1)]
        return PixelImage(width:64,height:48,pixels:(0..<(64*48)).map { i in
            colors[((i%64>=32 ? 1 : 0)+(i/64>=24 ? 2 : 0)+index)%4]
        })
    }
    public static func make(at url:URL,rotated:Bool=false,audio:Bool=false) async throws {
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:48])
        if rotated { input.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:48,ty:0) }
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:64,kCVPixelBufferHeightKey as String:48])
        writer.add(input)
        let audioInput=audio ? AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:2]) : nil
        if let audioInput { writer.add(audioInput) }
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime:.zero)
        let context=CIContext()
        for (index,time) in times.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for:.milliseconds(2)) }
            var buffer:CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)==kCVReturnSuccess,let buffer else { throw BraidError.invalid("Fixture buffer allocation failed") }
            context.render(CIImage(cgImage:try ImageProcessor.cgImage(pixels(index))),to:buffer)
            guard adaptor.append(buffer,withPresentationTime:CMTime(seconds:time,preferredTimescale:600)) else { throw writer.error! }
        }
        input.markAsFinished()
        if let audioInput {
            var description=AudioStreamBasicDescription(mSampleRate:48000,mFormatID:kAudioFormatLinearPCM,
                mFormatFlags:kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked,mBytesPerPacket:4,mFramesPerPacket:1,
                mBytesPerFrame:4,mChannelsPerFrame:2,mBitsPerChannel:16,mReserved:0)
            var format:CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&description,layoutSize:0,layout:nil,magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&format)==noErr else { throw BraidError.invalid("Fixture audio format failed") }
            let sampleCount=Int(duration*48000)
            for offset in stride(from:0,to:sampleCount,by:1024) {
                let count=min(1024,sampleCount-offset)
                var samples=[Int16]()
                for i in 0..<count {
                    let value=Int16(sin(Double(offset+i)*2*Double.pi*440/48000)*8000)
                    samples.append(value);samples.append(value)
                }
                let bytes=samples.withUnsafeBytes { Data($0) }
                var block:CMBlockBuffer?
                guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:bytes.count,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:bytes.count,flags:0,blockBufferOut:&block)==noErr else { throw BraidError.invalid("Fixture audio buffer failed") }
                _=bytes.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block!,offsetIntoDestination:0,dataLength:bytes.count) }
                var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:48000),presentationTimeStamp:CMTime(value:Int64(offset),timescale:48000),decodeTimeStamp:.invalid)
                var size=4,sample:CMSampleBuffer?
                guard CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:count,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample)==noErr else { throw BraidError.invalid("Fixture audio sample failed") }
                while !audioInput.isReadyForMoreMediaData { try await Task.sleep(for:.milliseconds(2)) }
                guard audioInput.append(sample!) else { throw writer.error! }
            }
            audioInput.markAsFinished()
        }
        writer.endSession(atSourceTime:CMTime(seconds:duration,preferredTimescale:600))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
    }
}
