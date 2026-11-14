import Foundation
import Metal

public struct CostTable: Sendable {
    public var values: [Float]
    public var tileCount: Int
    public var backend: String
    public subscript(pixel: Int, tile: Int) -> Double { Double(values[pixel*tileCount+tile]) }
}
public enum CostEngine {
    public static func compute(image: PixelImage, tiles: TileData, useGPU: Bool = true) throws -> CostTable {
        try image.validate()
        let total=image.pixels.count*tiles.allTiles.count
        guard total<=32_000_000 else { throw BraidError.invalid("Too many tile candidates. Reduce image size or palette size.") }
        let options=MTLCompileOptions();options.fastMathEnabled=false
        if useGPU, let device=MTLCreateSystemDefaultDevice(),
           let url=Bundle.module.url(forResource: "ColorCost",withExtension: "metal"),
           let source=try? String(contentsOf: url,encoding: .utf8),
           let library=try? device.makeLibrary(source: source,options: options),
           let function=library.makeFunction(name: "colorCosts"),
           let pipeline=try? device.makeComputePipelineState(function: function),let queue=device.makeCommandQueue() {
            let p=image.pixels.map{SIMD4<Float>(Float($0.r),Float($0.g),Float($0.b),1)}
            let t=tiles.allTiles.map{SIMD4<Float>(Float($0.average.r),Float($0.average.g),Float($0.average.b),1)}
            if let pb=device.makeBuffer(bytes:p,length:p.count*MemoryLayout<SIMD4<Float>>.stride,options:.storageModeShared),
               let tb=device.makeBuffer(bytes:t,length:t.count*MemoryLayout<SIMD4<Float>>.stride,options:.storageModeShared),
               let output=device.makeBuffer(length:total*MemoryLayout<Float>.stride,options:.storageModeShared),
               let command=queue.makeCommandBuffer(),let encoder=command.makeComputeCommandEncoder() {
                var counts=SIMD2<UInt32>(UInt32(p.count),UInt32(t.count))
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(pb,offset:0,index:0); encoder.setBuffer(tb,offset:0,index:1); encoder.setBuffer(output,offset:0,index:2)
                encoder.setBytes(&counts,length:MemoryLayout<SIMD2<UInt32>>.stride,index:3)
                encoder.dispatchThreads(MTLSize(width:total,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:min(256,pipeline.maxTotalThreadsPerThreadgroup),height:1,depth:1))
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                if command.status == .completed {
                    let values=Array(UnsafeBufferPointer(start: output.contents().bindMemory(to:Float.self,capacity:total),count:total))
                    if values.allSatisfy({$0.isFinite && $0>=0}) { return CostTable(values:values,tileCount:t.count,backend:"Metal · \(device.name)") }
                }
            }
        }
        let labs=tiles.allTiles.map{Lab(sRGB:$0.average)}
        var values=[Float](); values.reserveCapacity(total)
        for pixel in image.pixels {
            try Task.checkCancellation()
            let lab=Lab(sRGB:pixel); values.append(contentsOf:labs.map{Float(lab.distance(to:$0))})
        }
        return CostTable(values:values,tileCount:labs.count,backend:"CPU · CIEDE2000")
    }
}
