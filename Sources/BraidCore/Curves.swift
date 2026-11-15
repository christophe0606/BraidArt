import Foundation
import simd

/// Notebook coordinates: tile centers (1,-1), (2,-1), …; +Z faces the viewer.
public struct CurvePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double = 0) { self.x=x; self.y=y; self.z=z }
    var vector: SIMD3<Double> { SIMD3(x,y,z) }
    init(_ v: SIMD3<Double>) { self.init(v.x,v.y,v.z) }
}
public struct CurveSegment: Codable, Equatable, Sendable {
    /// Two points for a line, four for a cubic Bézier.
    public var points: [CurvePoint]
    public var raised: Bool
    public var tileColumn: Int
    public var tileRow: Int
    public var start: CurvePoint { points[0] }
    public var end: CurvePoint { points[points.count-1] }
    public func point(at t: Double) -> CurvePoint {
        let p=points.map(\.vector),u=1-t
        if p.count==2 { return CurvePoint(p[0]*u+p[1]*t) }
        return CurvePoint(p[0]*(u*u*u)+p[1]*(3*u*u*t)+p[2]*(3*u*t*t)+p[3]*(t*t*t))
    }
    var reversed: CurveSegment { CurveSegment(points:points.reversed(),raised:raised,tileColumn:tileColumn,tileRow:tileRow) }
}
public struct BraidCurve: Codable, Equatable, Sendable {
    public var colorIndex: Int
    public var closed: Bool
    public var segments: [CurveSegment]
}
public struct BraidCurves: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var palette: [RGB]
    public var background: RGB
    public var strandWidth: Double
    public var gap: Double
    public var curves: [BraidCurve]
}
public struct SceneSettings: Codable, Equatable, Sendable {
    public var planeColor: RGB = .gray
    /// Clearance between the back of the lowest tube and the plane, in tile units.
    public var planeDistance: Double = 0.15
    public init(planeColor: RGB = .gray, planeDistance: Double = 0.15) { self.planeColor=planeColor; self.planeDistance=planeDistance }
    public func validate() throws {
        guard planeColor.valid, planeDistance.isFinite, (0...10).contains(planeDistance) else { throw BraidError.invalid(L("Invalid backing plane color or distance.")) }
    }
}

public enum CurveGenerator {
    private enum Edge: Int { case left, right, top, bottom }
    private struct Key: Hashable { var x: Int; var y: Int }
    private struct Piece { var a: Key; var b: Key; var color: Int; var segments: [CurveSegment] }
    public static func generate(solution: [[Int]], data: TileData) throws -> BraidCurves {
        try SolveResult(solution:solution,reports:[],costBackend:"",elapsedSeconds:0).validate(tileData:data)
        guard data.palette.allSatisfy(\.valid), (0.1...0.6).contains(data.strandWidth),
              data.allTiles.allSatisfy({data.palette.indices.contains($0.firstColor) && data.palette.indices.contains($0.secondColor)})
        else { throw BraidError.invalid(L("Invalid curve palette or width.")) }
        let width=solution[0].count,height=solution.count
        var pieces=[Piece](), ends=[Key:[Int]]()
        for y in solution.indices { for x in 0..<width {
            let tile=data.allTiles[solution[y][x]-1]
            let pairs: [(Edge,Edge,Int,Bool)]
            switch tile.kind {
            case .vCross: pairs=[(.left,.right,tile.firstColor,false),(.top,.bottom,tile.secondColor,true)]
            case .hCross: pairs=[(.left,.right,tile.firstColor,true),(.top,.bottom,tile.secondColor,false)]
            case .circLeft: pairs=[(.left,.top,tile.firstColor,false),(.bottom,.right,tile.secondColor,false)]
            case .circRight: pairs=[(.left,.bottom,tile.firstColor,false),(.top,.right,tile.secondColor,false)]
            }
            func key(_ e: Edge)->Key {
                switch e {
                case .left: return Key(x:2*x,y:2*y+1)
                case .right: return Key(x:2*x+2,y:2*y+1)
                case .top: return Key(x:2*x+1,y:2*y)
                case .bottom: return Key(x:2*x+1,y:2*y+2)
                }
            }
            func point(_ e: Edge)->SIMD3<Double> { let k=key(e);return SIMD3(Double(k.x)/2+0.5,-Double(k.y)/2-0.5,0) }
            for (a,b,color,raised) in pairs {
                let p=point(a),q=point(b),segments: [CurveSegment]
                func segment(_ pts:[SIMD3<Double>])->CurveSegment { CurveSegment(points:pts.map(CurvePoint.init),raised:raised,tileColumn:x,tileRow:y) }
                if raised {
                    // curve[] in 3DBraids.nb, scaled in Z to keep adjustable-width tubes apart.
                    let lift=max(0.3353863185193847,data.strandWidth*1.1)
                    let xs=[0.0,0.25056810168374166,0.22417225112371134,0.5,0.5,0.7758277488762887,0.7494318983162581,1.0]
                    let zs=[0.0,0.013371188651563308,0.33538631851938494,0.3353863185193847,0.3353863185193847,0.3353863185193845,0.013371188651563497,0.0]
                    let pts=zip(xs,zs).map { t,z in p+(q-p)*t+SIMD3(0,0,z*lift/0.3353863185193847) }
                    segments=[segment(Array(pts[0..<4])),segment(Array(pts[4..<8]))]
                } else if a == .left && b == .right || a == .top && b == .bottom {
                    segments=[segment([p,q])]
                } else {
                    // Quarter circle of radius 1/2, tangent to both tile edges.
                    let center=SIMD3<Double>(a == .left || b == .left ? Double(x)+0.5 : Double(x)+1.5,
                                            a == .top || b == .top ? -Double(y)-0.5 : -Double(y)-1.5,0)
                    let k=4*(sqrt(2.0)-1)/3
                    segments=[segment([p,p+(q-center)*k,q+(p-center)*k,q])]
                }
                let id=pieces.count,ka=key(a),kb=key(b)
                pieces.append(Piece(a:ka,b:kb,color:color,segments:segments));ends[ka,default:[]].append(id);ends[kb,default:[]].append(id)
            }
        }}
        var used=Array(repeating:false,count:pieces.count),curves=[BraidCurve]()
        func trace(_ id: Int, from start: Key) throws {
            var current=id,at=start,segments=[CurveSegment](),closed=false
            let color=pieces[id].color
            while !used[current] {
                let p=pieces[current]
                guard p.color==color else { throw BraidError.invalid(L("Curve changes color at a tile edge.")) }
                used[current]=true
                if p.a==at { segments += p.segments;at=p.b }
                else { segments += p.segments.reversed().map(\.reversed);at=p.a }
                if at==start { closed=true;break }
                guard let next=ends[at]?.first(where:{!used[$0]}) else { break }
                current=next
            }
            curves.append(BraidCurve(colorIndex:color,closed:closed,segments:segments))
        }
        // Open paths start at the outer boundary; remaining pieces necessarily form loops.
        for i in pieces.indices where !used[i] {
            if ends[pieces[i].a]?.count==1 { try trace(i,from:pieces[i].a) }
            else if ends[pieces[i].b]?.count==1 { try trace(i,from:pieces[i].b) }
        }
        for i in pieces.indices where !used[i] { try trace(i,from:pieces[i].a) }
        return BraidCurves(columns:width,rows:height,palette:data.palette,background:data.background,strandWidth:data.strandWidth,gap:data.gap,curves:curves)
    }
}
