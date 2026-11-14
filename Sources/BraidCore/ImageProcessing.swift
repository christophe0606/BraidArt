import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

public enum ImageProcessor {
    private static let colorSpace=CGColorSpace(name:CGColorSpace.sRGB)!
    public static func thumbnail(url: URL, maxSize: Int = 1600) throws -> CGImage {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
            kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxSize,
            kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary)
        else { throw BraidError.invalid("This file could not be opened as an image.") }
        return image
    }
    public static func prepare(url: URL, settings: Settings) throws -> PixelImage {
        try prepare(url:url,settings:settings,forPalette:false)
    }
    /// A detailed sample of the same crop and adjustments, independent of tile
    /// resolution, so small colored features remain available to palette extraction.
    public static func preparePalette(url: URL, settings: Settings) throws -> PixelImage {
        try prepare(url:url,settings:settings,forPalette:true)
    }
    private static func prepare(url: URL, settings: Settings, forPalette: Bool) throws -> PixelImage {
        try settings.validate()
        guard var image=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]) else { throw BraidError.invalid("Cannot decode the selected image.") }
        let e=image.extent,c=settings.crop
        let rect=CGRect(x:e.minX+c.x*e.width,y:e.minY+(1-c.y-c.height)*e.height,width:c.width*e.width,height:c.height*e.height).integral.intersection(e)
        guard !rect.isEmpty else { throw BraidError.invalid("The crop is empty.") }
        image=image.cropped(to:rect).transformed(by:CGAffineTransform(translationX:-rect.minX,y:-rect.minY))
        let width:Int,height:Int
        if forPalette {
            let scale=min(1,512/max(rect.width,rect.height))
            width=max(1,Int((rect.width*scale).rounded()));height=max(1,Int((rect.height*scale).rounded()))
        } else {
            width=settings.columns;height=max(1,Int((Double(width)*rect.height/rect.width).rounded()))
            guard height<=256 else { throw BraidError.invalid("This crop would be taller than 256 tiles. Reduce the width or use a wider crop.") }
        }
        let bg=settings.alphaBackground
        image=image.composited(over:CIImage(color:CIColor(red:bg.r,green:bg.g,blue:bg.b)).cropped(to:image.extent))
        let controls=CIFilter.colorControls(); controls.inputImage=image; controls.contrast=Float(settings.contrast); controls.brightness=Float(settings.brightness)
        controls.saturation=settings.grayscale ? 0 : 1
        image=controls.outputImage ?? image
        let scale=CIFilter.lanczosScaleTransform(); scale.inputImage=image; scale.scale=Float(Double(height)/rect.height); scale.aspectRatio=Float((Double(width)/rect.width)/(Double(height)/rect.height))
        image=scale.outputImage ?? image
        let context=CIContext(options:[.workingColorSpace:colorSpace,.outputColorSpace:colorSpace,.useSoftwareRenderer:false])
        guard let cg=context.createCGImage(image,from:CGRect(x:0,y:0,width:width,height:height),format:.RGBA8,colorSpace:colorSpace) else { throw BraidError.invalid("Image preparation failed.") }
        return try pixels(from:cg)
    }
    public static func pixels(from cg: CGImage) throws -> PixelImage {
        let w=cg.width,h=cg.height
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let ok=bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        guard ok else { throw BraidError.invalid("Unable to sample image pixels.") }
        return PixelImage(width:w,height:h,pixels:stride(from:0,to:bytes.count,by:4).map{RGB(Double(bytes[$0])/255,Double(bytes[$0+1])/255,Double(bytes[$0+2])/255)})
    }
    public static func cgImage(_ image: PixelImage) throws -> CGImage {
        var bytes=[UInt8](); bytes.reserveCapacity(image.width*image.height*4)
        for p in image.pixels { bytes += [UInt8((min(1,max(0,p.r))*255).rounded()),UInt8((min(1,max(0,p.g))*255).rounded()),UInt8((min(1,max(0,p.b))*255).rounded()),255] }
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let cg=CGImage(width:image.width,height:image.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:image.width*4,space:colorSpace,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { throw BraidError.invalid("Unable to create preview.") }
        return cg
    }
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { throw BraidError.invalid("Cannot create PNG file.") }
        CGImageDestinationAddImage(dest,image,nil)
        guard CGImageDestinationFinalize(dest) else { throw BraidError.invalid("Cannot save PNG file.") }
    }
}
