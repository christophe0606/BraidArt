import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import BraidCore

// Render the same nine validated tiles as the Mac icon, without its transparent
// inset or rounded mask. iOS supplies the app-icon mask; its source must be opaque.
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let project=try BraidProject.load(from:root.appendingPathComponent("Resources/IconPattern.braidart"))
let nine=project.result.solution.prefix(3).map { Array($0.prefix(3)) }
let image=try TileRenderer.render(solution:nine,data:project.tileData,pixelSize:CGSize(width:1024,height:1024))
guard let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,
    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot render the iOS icon")
}
context.interpolationQuality = .low
context.draw(image,in:CGRect(x:0,y:0,width:1024,height:1024))
guard let opaque=context.makeImage() else { fatalError("Cannot create the iOS icon") }
for folder in ["AppIcon.appiconset","AppIconPreview.imageset"] {
    let url=root.appendingPathComponent("iOS/Assets.xcassets/\(folder)/AppIcon.png")
    guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { fatalError("Cannot write the iOS icon") }
    CGImageDestinationAddImage(destination,opaque,nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save the iOS icon") }
}
print("Generated opaque, full-bleed iOS icon from the existing nine-tile pattern")
