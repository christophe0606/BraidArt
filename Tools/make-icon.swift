import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root:
// swift Tools/make-icon.swift Resources/AppIcon.png .build/AppIcon.iconset
// iconutil -c icns .build/AppIcon.iconset -o Sources/BraidArt/Resources/AppIcon.icns
let input=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "Resources/AppIcon.png")
let output=URL(fileURLWithPath:CommandLine.arguments.count>2 ? CommandLine.arguments[2] : ".build/AppIcon.iconset",isDirectory:true)
guard let source=CGImageSourceCreateWithURL(input as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil),
      image.width==image.height else { fatalError("Provide a square PNG icon master.") }
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let colorSpace=CGColorSpace(name:CGColorSpace.sRGB)!
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        guard let context=CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,
                                    space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Cannot create icon bitmap.")
        }
        // Preserve clean black/gray boundaries without bright resampling halos.
        context.interpolationQuality = .low
        context.draw(image,in:CGRect(x:0,y:0,width:pixels,height:pixels))
        let suffix=scale==2 ? "@2x" : ""
        let url=output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        guard let resized=context.makeImage(),let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else {
            fatalError("Cannot write icon bitmap.")
        }
        CGImageDestinationAddImage(destination,resized,nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not save \(url.lastPathComponent).") }
    }
}
print("Created \(output.path)")
