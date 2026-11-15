import Foundation
import simd

/// Shared geometry for the Metal-backed viewport and portable glTF export.
public struct TubeMesh: Sendable {
    public var positions=[SIMD3<Float>]()
    public var normals=[SIMD3<Float>]()
    public var indices=[UInt32]()
    public var color: RGB
    public var name: String
    public init(color: RGB, name: String) { self.color=color;self.name=name }
}
public enum TubeMesher {
    public static func build(_ braid: BraidCurves, radialSegments requestedRadial: Int = 0, curveSteps requestedSteps: Int = 0) throws -> [TubeMesh] {
        // Bound tessellation cost for the largest supported grids; internal curves remain exact.
        let tiles=braid.columns*braid.rows
        let radialSegments=requestedRadial==0 ? (tiles>16384 ? 8 : tiles>4096 ? 10 : 16) : requestedRadial
        let curveSteps=requestedSteps==0 ? (tiles>16384 ? 4 : tiles>4096 ? 8 : 16) : requestedSteps
        guard (6...32).contains(radialSegments),(4...64).contains(curveSteps) else { throw BraidError.invalid(L("Invalid mesh quality.")) }
        var meshes=braid.palette.enumerated().map{TubeMesh(color:$0.element,name:"Strand \($0.offset+1)")}
        for curve in braid.curves {
            var pts=[SIMD3<Double>]()
            for s in curve.segments {
                let steps=s.points.count==2 ? 1 : curveSteps
                for i in 0..<steps { pts.append(s.point(at:Double(i)/Double(steps)).vector) }
            }
            if !curve.closed,let end=curve.segments.last?.end { pts.append(end.vector) }
            guard pts.count>=2 else { continue }
            let c=curve.colorIndex,base=meshes[c].positions.count,n=pts.count
            for i in pts.indices {
                let prev=i==0 ? (curve.closed ? pts[n-1] : pts[0]) : pts[i-1]
                let next=i==n-1 ? (curve.closed ? pts[0] : pts[n-1]) : pts[i+1]
                let tangent=simd_normalize(next-prev)
                let normal=simd_normalize(simd_cross(tangent,SIMD3(0,0,1)))
                let binormal=simd_cross(tangent,normal)
                for j in 0..<radialSegments {
                    let a=Double(j)*2*Double.pi/Double(radialSegments)
                    let norm=normal*cos(a)+binormal*sin(a)
                    meshes[c].positions.append(SIMD3<Float>(pts[i]+norm*(braid.strandWidth/2)))
                    meshes[c].normals.append(SIMD3<Float>(norm))
                }
            }
            let links=curve.closed ? n : n-1
            for i in 0..<links { for j in 0..<radialSegments {
                let a=UInt32(base+i*radialSegments+j),b=UInt32(base+i*radialSegments+(j+1)%radialSegments)
                let c1=UInt32(base+((i+1)%n)*radialSegments+j),d=UInt32(base+((i+1)%n)*radialSegments+(j+1)%radialSegments)
                meshes[c].indices += [a,b,c1,b,d,c1]
            }}
            if !curve.closed {
                for end in [0,n-1] {
                    let capNormal=simd_normalize(end==0 ? pts[0]-pts[1] : pts[n-1]-pts[n-2])
                    let capBase=UInt32(meshes[c].positions.count)
                    meshes[c].positions.append(SIMD3<Float>(pts[end]));meshes[c].normals.append(SIMD3<Float>(capNormal))
                    for j in 0..<radialSegments {
                        meshes[c].positions.append(meshes[c].positions[base+end*radialSegments+j]);meshes[c].normals.append(SIMD3<Float>(capNormal))
                    }
                    for j in 0..<radialSegments {
                        let a=capBase+1+UInt32(j),b=capBase+1+UInt32((j+1)%radialSegments)
                        meshes[c].indices += end==0 ? [capBase,b,a] : [capBase,a,b]
                    }
                }
            }
        }
        return meshes.filter{!$0.indices.isEmpty}
    }
    public static func plane(_ braid:BraidCurves, settings:SceneSettings) -> TubeMesh {
        var m=TubeMesh(color:settings.planeColor,name:"Backing plane")
        let x:Float=0.5,y = -Float(braid.rows)-0.5,w=Float(braid.columns),h=Float(braid.rows)
        let z = -Float(braid.strandWidth/2+settings.planeDistance)
        m.positions=[SIMD3(x,y,z),SIMD3(x+w,y,z),SIMD3(x+w,y+h,z),SIMD3(x,y+h,z)]
        m.normals=Array(repeating:SIMD3(0,0,1),count:4);m.indices=[0,1,2,0,2,3]
        return m
    }
}
