import Foundation
import simd
import zlib

public enum USDZExporter {
    /// Indexed triangles with vertex normals and USD Preview Surface colors, without external assets.
    public static func write(meshes:[TubeMesh],to url:URL,
                             progress:(Double,String)->Void = { _,_ in }) throws {
        try Task.checkCancellation()
        progress(0,L("Preparing USDZ geometry…"))
        let meshes=meshes.filter { !$0.indices.isEmpty }
        guard !meshes.isEmpty else { throw BraidError.invalid(L("There is no 3D geometry to export.")) }
        var minimum=SIMD3<Float>(repeating:.infinity),maximum=SIMD3<Float>(repeating: -.infinity)
        for mesh in meshes {
            try Task.checkCancellation()
            guard !mesh.positions.isEmpty,mesh.positions.count==mesh.normals.count,mesh.indices.count%3==0,
                  mesh.indices.allSatisfy({Int($0)<mesh.positions.count}),mesh.color.valid,
                  mesh.normals.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}) else {
                throw BraidError.invalid(L("Invalid 3D mesh."))
            }
            for (index,p) in mesh.positions.enumerated() {
                if index%4096==0 { try Task.checkCancellation() }
                guard p.x.isFinite,p.y.isFinite,p.z.isFinite else { throw BraidError.invalid(L("Invalid 3D mesh.")) }
                minimum=simd_min(minimum,p);maximum=simd_max(maximum,p)
            }
        }
        let center=minimum/2+maximum/2
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("BraidArt-USDZ-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let layer=folder.appendingPathComponent("BraidArt.usda"),writer=try USDTextWriter(url:layer)
        let total=meshes.reduce(0) { $0+$1.positions.count+$1.normals.count+$1.indices.count+$1.indices.count/3 }
        var completed=0,lastReport=ProcessInfo.processInfo.systemUptime
        func checkpoint() throws {
            completed+=1
            if completed%1024==0 {
                try Task.checkCancellation()
                let now=ProcessInfo.processInfo.systemUptime
                if now-lastReport>=0.1 {
                    progress(0.85*Double(completed)/Double(total),L("Writing colored USDZ meshes…"));lastReport=now
                }
            }
        }
        func vector(_ p:SIMD3<Float>)->String { "(\(p.x), \(p.y), \(p.z))" }
        func quote(_ text:String)->String {
            "\""+text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
                .replacingOccurrences(of:"\n",with:"\\n").replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\t",with:"\\t")+"\""
        }
        func linear(_ c:Double)->Double { c<=0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
        try writer.append("""
        #usda 1.0
        (
            defaultPrim = "BraidArt"
            metersPerUnit = 1
            upAxis = "Y"
        )
        def Xform "BraidArt" (kind = "component") {
            double3 xformOp:translate = \(vector(-center))
            uniform token[] xformOpOrder = ["xformOp:translate"]
            def Scope "Materials" {
        
        """)
        for (index,mesh) in meshes.enumerated() {
            let c=mesh.color,roughness=mesh.name=="Backing plane" ? 0.65 : 0.23
            try writer.append("""
                def Material "Material_\(index)" {
                    token outputs:surface.connect = </BraidArt/Materials/Material_\(index)/Surface.outputs:surface>
                    def Shader "Surface" {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (\(linear(c.r)), \(linear(c.g)), \(linear(c.b))) (colorSpace = "lin_rec709_scene")
                        float inputs:metallic = 0
                        float inputs:roughness = \(roughness)
                        token outputs:surface
                    }
                }
            
            """)
        }
        try writer.append("    }\n")
        for (index,mesh) in meshes.enumerated() {
            try Task.checkCancellation()
            try writer.append("""
                def Mesh "Mesh_\(index)" (
                    prepend apiSchemas = ["MaterialBindingAPI"]
                    displayName = \(quote(mesh.name))
                ) {
                    bool doubleSided = true
                    uniform token subdivisionScheme = "none"
                    rel material:binding = </BraidArt/Materials/Material_\(index)>
                    point3f[] points = [
            """)
            for (i,p) in mesh.positions.enumerated() {
                try writer.append((i==0 ? "" : ",")+vector(p));try checkpoint()
            }
            try writer.append("]\n        normal3f[] normals = [")
            for (i,n) in mesh.normals.enumerated() {
                try writer.append((i==0 ? "" : ",")+vector(n));try checkpoint()
            }
            try writer.append("] (interpolation = \"vertex\")\n        int[] faceVertexCounts = [")
            for i in 0..<mesh.indices.count/3 { try writer.append(i==0 ? "3" : ",3");try checkpoint() }
            try writer.append("]\n        int[] faceVertexIndices = [")
            for (i,value) in mesh.indices.enumerated() {
                try writer.append((i==0 ? "" : ",")+String(value));try checkpoint()
            }
            try writer.append("]\n    }\n")
        }
        try writer.append("}\n");try writer.finish()
        try Task.checkCancellation()
        progress(0.85,L("Packaging USDZ…"))
        let package=folder.appendingPathComponent("BraidArt.usdz")
        try packageLayer(layer,to:package,size:writer.size,checksum:writer.checksum)
        progress(0.97,L("Saving USDZ…"))
        let data=try Data(contentsOf:package,options:.mappedIfSafe)
        try Task.checkCancellation()
        try data.write(to:url,options:.atomic)
        progress(1,L("USDZ saved."))
    }

    /// USDZ stores uncompressed ZIP entries with each payload aligned to 64 bytes.
    private static func packageLayer(_ layer:URL,to url:URL,size:UInt64,checksum:UInt32) throws {
        guard size<UInt32.max-1024 else { throw BraidError.invalid(L("This USDZ object exceeds the supported 4 GB package size.")) }
        let name=Data("BraidArt.usda".utf8)
        let padding=(64-(30+name.count)%64)%64
        var local=Data(),central=Data(),end=Data()
        func u16(_ value:UInt16,_ data:inout Data) { var v=value.littleEndian;withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        func u32(_ value:UInt32,_ data:inout Data) { var v=value.littleEndian;withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        u32(0x04034b50,&local);u16(20,&local);u16(0,&local);u16(0,&local)
        u16(0,&local);u16(33,&local);u32(checksum,&local);u32(UInt32(size),&local);u32(UInt32(size),&local)
        u16(UInt16(name.count),&local);u16(UInt16(padding),&local);local.append(name)
        // A valid extra field holds the alignment padding (the fixed name leaves 21 bytes).
        u16(0xffff,&local);u16(UInt16(padding-4),&local);local.append(Data(repeating:0,count:padding-4))
        u32(0x02014b50,&central);u16(20,&central);u16(20,&central);u16(0,&central);u16(0,&central)
        u16(0,&central);u16(33,&central);u32(checksum,&central);u32(UInt32(size),&central);u32(UInt32(size),&central)
        u16(UInt16(name.count),&central);u16(0,&central);u16(0,&central);u16(0,&central);u16(0,&central)
        u32(0,&central);u32(0,&central);central.append(name)
        u32(0x06054b50,&end);u16(0,&end);u16(0,&end);u16(1,&end);u16(1,&end)
        u32(UInt32(central.count),&end);u32(UInt32(local.count)+UInt32(size),&end);u16(0,&end)
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else { throw BraidError.invalid(L("Cannot create the USDZ package.")) }
        let output=try FileHandle(forWritingTo:url),input=try FileHandle(forReadingFrom:layer)
        defer { try? output.close();try? input.close() }
        try output.write(contentsOf:local)
        while let data=try input.read(upToCount:1024*1024),!data.isEmpty {
            try Task.checkCancellation();try output.write(contentsOf:data)
        }
        try output.write(contentsOf:central);try output.write(contentsOf:end)
    }
}

/// Buffer text and compute the ZIP checksum while streaming, avoiding a second geometry-sized copy.
private final class USDTextWriter {
    private let handle:FileHandle
    private var buffer=Data()
    private(set) var checksum:UInt32=0
    private(set) var size:UInt64=0
    init(url:URL) throws {
        guard FileManager.default.createFile(atPath:url.path,contents:nil) else { throw BraidError.invalid(L("Cannot create the USD geometry file.")) }
        handle=try FileHandle(forWritingTo:url)
    }
    deinit { try? handle.close() }
    func append(_ text:String) throws {
        buffer.append(contentsOf:text.utf8)
        if buffer.count>=64*1024 { try flush() }
    }
    private func flush() throws {
        guard !buffer.isEmpty else { return }
        checksum=buffer.withUnsafeBytes { UInt32(crc32(uLong(checksum),$0.bindMemory(to:Bytef.self).baseAddress,uInt(buffer.count))) }
        try handle.write(contentsOf:buffer);size+=UInt64(buffer.count);buffer.removeAll(keepingCapacity:true)
    }
    func finish() throws { try flush();try handle.close() }
}
