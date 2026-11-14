import Foundation

public enum GLBExporter {
    /// glTF 2.0 binary: indexed triangles, normals, PBR materials; no external textures.
    public static func write(meshes:[TubeMesh], to url:URL) throws {
        var binary=Data(),views=[[String:Any]](),accessors=[[String:Any]](),gMeshes=[[String:Any]](),materials=[[String:Any]](),nodes=[[String:Any]]()
        func append32(_ x:UInt32, to data:inout Data) { var value=x.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)} }
        func floats(_ values:[SIMD3<Float>], bounds:Bool) -> Int {
            let start=binary.count
            for v in values { append32(v.x.bitPattern,to:&binary);append32(v.y.bitPattern,to:&binary);append32(v.z.bitPattern,to:&binary) }
            views.append(["buffer":0,"byteOffset":start,"byteLength":binary.count-start,"target":34962])
            var a:[String:Any]=["bufferView":views.count-1,"componentType":5126,"count":values.count,"type":"VEC3"]
            if bounds {
                a["min"]=(0..<3).map{ axis in values.map{$0[axis]}.min()! }
                a["max"]=(0..<3).map{ axis in values.map{$0[axis]}.max()! }
            }
            accessors.append(a);return accessors.count-1
        }
        func linear(_ c:Double)->Double { c<=0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
        for mesh in meshes where !mesh.indices.isEmpty {
            guard mesh.positions.count==mesh.normals.count,mesh.indices.allSatisfy({Int($0)<mesh.positions.count}),mesh.color.valid,
                  mesh.positions.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}) else { throw BraidError.invalid("Invalid 3D mesh.") }
            let pos=floats(mesh.positions,bounds:true),norm=floats(mesh.normals,bounds:false),offset=binary.count
            for i in mesh.indices { append32(i,to:&binary) }
            views.append(["buffer":0,"byteOffset":offset,"byteLength":binary.count-offset,"target":34963])
            accessors.append(["bufferView":views.count-1,"componentType":5125,"count":mesh.indices.count,"type":"SCALAR"])
            let material=materials.count
            materials.append(["name":mesh.name,"doubleSided":true,"pbrMetallicRoughness":["baseColorFactor":[linear(mesh.color.r),linear(mesh.color.g),linear(mesh.color.b),1],"metallicFactor":0,"roughnessFactor":mesh.name=="Backing plane" ? 0.65 : 0.23]])
            nodes.append(["name":mesh.name,"mesh":gMeshes.count])
            gMeshes.append(["name":mesh.name,"primitives":[["attributes":["POSITION":pos,"NORMAL":norm],"indices":accessors.count-1,"material":material,"mode":4]]])
        }
        // Keep the picture in XY with +Z facing forward, as allowed by glTF's right-handed coordinates.
        let root:[String:Any]=["asset":["version":"2.0","generator":"BraidArt"],"scene":0,"scenes":[["nodes":Array(nodes.indices)]],"nodes":nodes,"meshes":gMeshes,"materials":materials,"buffers":[["byteLength":binary.count]],"bufferViews":views,"accessors":accessors]
        var json=try JSONSerialization.data(withJSONObject:root,options:[.sortedKeys])
        while json.count%4 != 0 { json.append(0x20) }
        while binary.count%4 != 0 { binary.append(0) }
        var out=Data();append32(0x46546C67,to:&out);append32(2,to:&out);append32(UInt32(12+8+json.count+8+binary.count),to:&out)
        append32(UInt32(json.count),to:&out);append32(0x4E4F534A,to:&out);out.append(json)
        append32(UInt32(binary.count),to:&out);append32(0x004E4942,to:&out);out.append(binary)
        try out.write(to:url,options:.atomic)
    }
}
