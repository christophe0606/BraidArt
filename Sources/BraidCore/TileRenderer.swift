import Foundation
import CoreGraphics

public enum TileRenderer {
    /// Notebook drawing geometry, in top-left coordinates. The small drawing offsets
    /// match drawVCross/drawHCross/drawCircLeft/drawCircRight, independently of analytic area weights.
    private static func colorAt(x: Double, y: Double, tile: Tile, data: TileData) -> RGB {
        let w=data.strandWidth, gap=data.gap, bg=data.background
        let a=data.palette[tile.firstColor],b=data.palette[tile.secondColor]
        let d=0.04, start=(0.5-w/2)+d/2, thickness=w-d/2, end=(1-w-gap)/2
        switch tile.kind {
        case .vCross:
            if x>=start && x<=start+thickness { return b }
            if y>=start && y<=start+thickness && (x<=end || x>=(1+w+gap)/2) { return a }
        case .hCross:
            if y>=start && y<=start+thickness { return a }
            if x>=start && x<=start+thickness && (y<=end || y>=(1+w+gap)/2) { return b }
        case .circLeft, .circRight:
            // arc uses d=1/50; radius=(diameter/2)-1/100.
            let outer=(1+w+0.04)/2-0.01, inner=(1-w+0.02)/2-0.01
            let cy1=tile.kind == .circLeft ? -0.01 : 1.0
            let cy2=tile.kind == .circLeft ? 1.0 : -0.01
            let r1=hypot(x+0.01,y-cy1),r2=hypot(x-1,y-cy2)
            if r2>=inner && r2<=outer { return b }
            if r1>=inner && r1<=outer { return a }
        }
        return bg
    }
    private static func raster(tile: Tile, data: TileData, size: Int) -> [UInt8] {
        var bytes=[UInt8](repeating:255,count:size*size*4)
        for y in 0..<size { for x in 0..<size {
            var color=RGB.black
            for dy in [0.25,0.75] { for dx in [0.25,0.75] {
                color=color+colorAt(x:(Double(x)+dx)/Double(size),y:(Double(y)+dy)/Double(size),tile:tile,data:data)*0.25
            }}
            let i=(y*size+x)*4
            bytes[i]=UInt8((min(1,max(0,color.r))*255).rounded());bytes[i+1]=UInt8((min(1,max(0,color.g))*255).rounded());bytes[i+2]=UInt8((min(1,max(0,color.b))*255).rounded())
        }}
        return bytes
    }
    public static func tile(_ tile: Tile, data: TileData, size: Int = 64) throws -> CGImage {
        try makeImage(bytes:raster(tile:tile,data:data,size:size),width:size,height:size)
    }
    public static func render(solution: [[Int]], data: TileData, tileSize: Int = 40) throws -> CGImage {
        guard let columns=solution.first?.count, columns>0, !solution.isEmpty,
              solution.allSatisfy({$0.count==columns}), (4...128).contains(tileSize),
              solution.joined().allSatisfy({ (1...data.allTiles.count).contains($0) }) else { throw BraidError.invalid("Invalid render dimensions or tile IDs.") }
        let width=columns*tileSize,height=solution.count*tileSize
        guard width*height<=80_000_000 else { throw BraidError.invalid("Export exceeds 80 megapixels. Choose a smaller tile size.") }
        let atlas=data.allTiles.map{raster(tile:$0,data:data,size:tileSize)}
        var bytes=[UInt8](repeating:255,count:width*height*4)
        bytes.withUnsafeMutableBytes { dst in
            for y in solution.indices { for x in 0..<columns {
                let tile=atlas[solution[y][x]-1]
                tile.withUnsafeBytes { src in
                    for r in 0..<tileSize {
                        dst.baseAddress!.advanced(by:((y*tileSize+r)*width+x*tileSize)*4).copyMemory(from:src.baseAddress!.advanced(by:r*tileSize*4),byteCount:tileSize*4)
                    }
                }
            }}
        }
        return try makeImage(bytes:bytes,width:width,height:height)
    }
    private static func makeImage(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let space=CGColorSpace(name:CGColorSpace.sRGB),
              let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { throw BraidError.invalid("Cannot render tiles.") }
        return image
    }
}
