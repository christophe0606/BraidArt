import Foundation
import CoreGraphics
import BraidCore

/// Render a 3 × 3 crop of real, connected BraidArt tiles, matching the user's
/// flat black/white reference. No synthesized strand geometry is used.
@main
struct GenerateIcon {
    static func main() throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath,isDirectory:true)
        let resources=root.appendingPathComponent("Resources",isDirectory:true)
        let output=root.appendingPathComponent(".build/icon-generation",isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var settings=Settings();settings.columns=8;settings.partitionSize=2
        settings.secondsPerPartition=5;settings.relativeGap=0;settings.threads=1;settings.grayscale=false
        settings.palette=[.black,.white];settings.background = .gray
        settings.strandWidth=0.414;settings.gap=0.4;settings.grayscale=true
        let data=TileData(settings:settings),width=8,height=8
        var reference=Array(repeating:Array(repeating:1,count:width),count:height)
        func tile(_ kind:TileKind,_ a:Int,_ b:Int)->Int {
            data.allTiles.first { $0.kind==kind && $0.firstColor==a && $0.secondColor==b }!.id
        }
        // Alternate quarter circles into white arches above/below a continuous
        // black horizontal strand. The next band swaps black and white, making
        // the surrounding source pattern continuous as well as the icon's crop.
        for y in 0..<height { for x in 0..<width {
            switch y%4 {
            case 0: reference[y][x]=x%2==0 ? tile(.circLeft,0,1) : tile(.circRight,1,0)
            case 1: reference[y][x]=tile(.hCross,0,1)
            case 2: reference[y][x]=x%2==0 ? tile(.circRight,0,1) : tile(.circLeft,1,0)
            default: reference[y][x]=tile(.hCross,1,0)
            }
        } }
        let pixels=reference.flatMap { $0.map { data.allTiles[$0-1].average } }
        let source=PixelImage(width:width,height:height,pixels:pixels)
        let sourceURL=resources.appendingPathComponent("IconSource.png")
        try ImageProcessor.writePNG(ImageProcessor.cgImage(source),to:sourceURL)
        let sampled=try ImageProcessor.prepare(url:sourceURL,settings:settings)
        let result=SolveResult(solution:reference,reports:[],costBackend:"Validated icon tile layout",elapsedSeconds:0)
        // This checks every horizontal and vertical tile boundary. CurveGenerator
        // additionally rejects any traced curve that changes strand color.
        try result.validate(tileData:data)
        _=try CurveGenerator.generate(solution:result.solution,data:data)
        let full=try TileRenderer.render(solution:reference,data:data,tileSize:128)
        try ImageProcessor.writePNG(full,to:output.appendingPathComponent("full-pattern.png"))
        let nine=reference.prefix(3).map { Array($0.prefix(3)) }
        let braid=try CurveGenerator.generate(solution:nine,data:data)
        // Render precisely these nine tiles at high resolution before applying
        // the icon mask; there are no extra partial rows or columns in the icon.
        let tileSize=384,side=3*tileSize
        guard let tileContext=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BraidError.invalid("Cannot render the nine icon tiles.")
        }
        for y in 0..<3 { for x in 0..<3 {
            let image=try TileRenderer.tile(data.allTiles[nine[y][x]-1],data:data,size:tileSize)
            tileContext.draw(image,in:CGRect(x:x*tileSize,y:(2-y)*tileSize,width:tileSize,height:tileSize))
        } }
        guard let detail=tileContext.makeImage(),let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BraidError.invalid("Cannot crop the generated icon.")
        }
        let bounds=CGRect(x:72,y:72,width:880,height:880)
        context.addPath(CGPath(roundedRect:bounds,cornerWidth:185,cornerHeight:185,transform:nil))
        // Bilinear resampling avoids the bright ringing that a sharper filter
        // can introduce outside black curves against the gray background.
        context.clip();context.interpolationQuality = .low
        context.draw(detail,in:bounds)
        guard let icon=context.makeImage() else { throw BraidError.invalid("Cannot render the icon mask.") }
        try ImageProcessor.writePNG(icon,to:resources.appendingPathComponent("AppIcon.png"))
        var project=BraidProject(sourceName:"IconSource.png",settings:settings,sampledImage:sampled,tileData:data,result:result)
        project.sceneSettings=SceneSettings(planeColor:.gray);project.pictureExportSize = .instagramSquare
        try project.save(to:resources.appendingPathComponent("IconPattern.braidart"))
        let provenance="""
        BraidArt icon — generated by BraidArt, not image synthesis.
        Source picture: Resources/IconSource.png (8 × 8 pixels).
        Construction: black and white quarter-circle tiles around a continuous black horizontal strand, on gray.
        Layout: arranged to match the user's supplied flat black/white reference.
        Project: Resources/IconPattern.braidart, a validated 8 × 8 repeating source pattern.
        Validation: every tile boundary matches; CurveGenerator verifies constant color along every strand.
        Artwork: BraidArt's flat TileRenderer, 384 pixels per tile.
        Crop: exactly 3 columns × 3 rows, source columns 0...2 and rows 0...2 (nine tiles total).
        Tile IDs: \(nine).
        Only cropping, bilinear resampling and the rounded-square alpha mask are applied to the rendered picture.
        Bilinear resampling avoids light fringes along black curves.
        Master: Resources/AppIcon.png (1024 × 1024, transparent margins).
        Regenerate: Scripts/generate-icon.sh
        """
        try provenance.write(to:resources.appendingPathComponent("AppIcon.source.txt"),atomically:true,encoding:.utf8)
        print("Generated icon from exactly 9 tiles and \(braid.curves.count) validated, constant-color strands.")
    }
}
