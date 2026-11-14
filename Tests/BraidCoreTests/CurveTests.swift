import XCTest
import AppKit
import SceneKit
import Metal
import ImageIO
@testable import BraidCore

final class CurveTests:XCTestCase {
    func fixture(_ width:Int=12,_ height:Int=10) throws -> BraidProject {
        var settings=Settings();settings.columns=max(8,width)
        settings.palette=[RGB(0.035,0.025,0.03),RGB(0.9,0.035,0.025),RGB(0.15,0.8,0.65),RGB(0.9,0.87,0.79)]
        let data=TileData(settings:settings)
        var solution=Array(repeating:Array(repeating:1,count:width),count:height)
        var seed:UInt64=1234567
        for y in 0..<height { for x in 0..<width {
            let candidates=data.allTiles.filter { t in
                (x==0 || data.allTiles[solution[y][max(0,x-1)]-1].right==t.left) &&
                (y==0 || data.allTiles[solution[max(0,y-1)][x]-1].bottom==t.top)
            }
            seed=seed &* 6364136223846793005 &+ 1
            solution[y][x]=candidates[Int((seed>>32)%UInt64(candidates.count))].id
        }}
        let result=SolveResult(solution:solution,reports:[],costBackend:"Curve validation fixture",elapsedSeconds:0)
        let pixels=solution.flatMap{$0.map{data.allTiles[$0-1].average}}
        var project=BraidProject(sourceName:"Curve validation",settings:settings,sampledImage:PixelImage(width:width,height:height,pixels:pixels),tileData:data,result:result)
        project.sceneSettings=SceneSettings(planeColor:RGB(0.28,0.32,0.19),planeDistance:0.2)
        try project.validate();return project
    }
    func testAllTileKindsAndNotebookControls() throws {
        let data=TileData(settings:Settings())
        for id in [1,5,9,13] {
            let braid=try CurveGenerator.generate(solution:[[id]],data:data)
            XCTAssertEqual(braid.curves.count,2);XCTAssertTrue(braid.curves.allSatisfy{!$0.closed})
            let segments=braid.curves.flatMap(\.segments)
            if id==1 || id==5 {
                XCTAssertEqual(segments.count,3)
                let raised=segments.filter(\.raised)
                XCTAssertEqual(raised.count,2)
                XCTAssertEqual(raised[0].end.z,data.strandWidth*1.1,accuracy:1e-10)
                XCTAssertEqual(raised[0].points[1].z,0.013371188651563308*(data.strandWidth*1.1)/0.3353863185193847,accuracy:1e-12)
            } else { XCTAssertTrue(segments.allSatisfy{$0.points.count==4 && !$0.raised}) }
        }
    }
    func testClosedLoopAndEveryPieceExactlyOnce() throws {
        let data=TileData(settings:Settings())
        let braid=try CurveGenerator.generate(solution:[[9,13],[13,9]],data:data)
        XCTAssertEqual(braid.curves.count,5)
        let loop=try XCTUnwrap(braid.curves.first(where:{$0.closed}))
        XCTAssertEqual(loop.segments.count,4)
        XCTAssertEqual(loop.segments.first!.start,loop.segments.last!.end)
        XCTAssertEqual(braid.curves.flatMap(\.segments).count,8)
        // Central loop has radius 1/2 and stays in the source image's orientation.
        for s in loop.segments {
            let p=s.point(at:0.5)
            XCTAssertEqual(hypot(p.x-1.5,p.y+1.5),0.5,accuracy:0.00001)
        }
    }
    func testMixedColorContinuityAndMeshTopology() throws {
        let project=try fixture(23,19),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        var pieces=Set<String>()
        for curve in braid.curves {
            for (a,b) in zip(curve.segments,curve.segments.dropFirst()) { XCTAssertEqual(a.end,b.start) }
            if curve.closed { XCTAssertEqual(curve.segments.first!.start,curve.segments.last!.end) }
            for s in curve.segments { pieces.insert("\(s.tileRow),\(s.tileColumn),\(s.raised),\(s.start.x),\(s.start.y)") }
        }
        XCTAssertFalse(pieces.isEmpty)
        let crossingCount=project.result.solution.joined().filter { id in
            let kind=project.tileData.allTiles[id-1].kind
            return kind == .vCross || kind == .hCross
        }.count
        XCTAssertEqual(braid.curves.flatMap(\.segments).count,23*19*2+crossingCount)
        let meshes=try TubeMesher.build(braid)
        for mesh in meshes {
            XCTAssertEqual(mesh.positions.count,mesh.normals.count)
            XCTAssertTrue(mesh.indices.allSatisfy{Int($0)<mesh.positions.count})
            XCTAssertTrue(mesh.normals.allSatisfy{abs(simd_length($0)-1)<0.0001})
            // Every tube, including closed loops and flat end caps, is watertight by position.
            struct P:Hashable { var x:Int;var y:Int;var z:Int;init(_ p:SIMD3<Float>){x=Int((p.x*100000).rounded());y=Int((p.y*100000).rounded());z=Int((p.z*100000).rounded())} }
            struct E:Hashable { var a:P;var b:P }
            var edges=[E:Int]()
            for i in stride(from:0,to:mesh.indices.count,by:3) {
                let ps=(0..<3).map{P(mesh.positions[Int(mesh.indices[i+$0])])}
                for j in 0..<3 { edges[E(a:ps[j],b:ps[(j+1)%3]),default:0]+=1 }
            }
            for (e,count) in edges { XCTAssertEqual(count,edges[E(a:e.b,b:e.a)],"Unpaired mesh edge") }
        }
        let plane=TubeMesher.plane(braid,settings:project.sceneSettings!)
        XCTAssertEqual(plane.positions[0].z,Float(-braid.strandWidth/2-0.2),accuracy:0.00001)
    }
    func testVectorPDFAndPortableGLB() throws {
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let folder=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/curve-validation")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try project.save(to:folder.appendingPathComponent("fixture.braidart"))
        let pdf=folder.appendingPathComponent("braid.pdf")
        try CurveExporter.writePDF(braid,to:pdf)
        let document=try XCTUnwrap(CGPDFDocument(pdf as CFURL));XCTAssertEqual(document.numberOfPages,1)
        let page=try XCTUnwrap(document.page(at:1));XCTAssertEqual(page.getBoxRect(.mediaBox).width,Double(braid.columns)*24)
        var resources:CGPDFDictionaryRef?,xObjects:CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(page.dictionary!,"Resources",&resources),let resources {
            if CGPDFDictionaryGetDictionary(resources,"XObject",&xObjects),let xObjects { XCTAssertEqual(CGPDFDictionaryGetCount(xObjects),0,"PDF must contain no raster XObjects") }
        }
        let meshes=try TubeMesher.build(braid)+[TubeMesher.plane(braid,settings:project.sceneSettings!)]
        let glb=folder.appendingPathComponent("braid.glb");try GLBExporter.write(meshes:meshes,to:glb)
        let bytes=try Data(contentsOf:glb)
        func u32(_ i:Int)->UInt32 { bytes[i..<i+4].enumerated().reduce(0){$0 | UInt32($1.element)<<($1.offset*8)} }
        XCTAssertEqual(u32(0),0x46546C67);XCTAssertEqual(u32(4),2);XCTAssertEqual(Int(u32(8)),bytes.count)
        let jsonLength=Int(u32(12));XCTAssertEqual(u32(16),0x4E4F534A)
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes[20..<20+jsonLength]) as? [String:Any])
        XCTAssertEqual((json["materials"] as? [Any])?.count,5)
        XCTAssertEqual(u32(24+jsonLength),0x004E4942)
        XCTAssertEqual(Int(u32(20+jsonLength)),bytes.count-28-jsonLength)
        let loaded=try BraidProject.load(from:folder.appendingPathComponent("fixture.braidart"));XCTAssertEqual(loaded.sceneSettings,project.sceneSettings)
        var legacy=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("fixture.braidart"))) as! [String:Any]
        legacy.removeValue(forKey:"sceneSettings")
        try JSONSerialization.data(withJSONObject:legacy).write(to:folder.appendingPathComponent("legacy.braidart"))
        XCTAssertNil(try BraidProject.load(from:folder.appendingPathComponent("legacy.braidart")).sceneSettings)
    }
    @MainActor func testMetalVisualizationAndCameraControls() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal device unavailable") }
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let meshes=try TubeMesher.build(braid)
        let view=BraidMetalView(frame:CGRect(x:0,y:0,width:1000,height:800))
        view.display(braid,meshes:meshes,settings:project.sceneSettings!)
        XCTAssertEqual(view.renderingAPI,.metal);XCTAssertNotNil(view.device)
        let initial=view.cameraNode.position
        view.orbit(dx:0.3,dy:-0.35);XCTAssertNotEqual(view.cameraNode.position.x,initial.x)
        let distance=view.cameraDistance;view.zoom(factor:0.8);XCTAssertLessThan(view.cameraDistance,distance)
        let target=view.target;view.pan(dx:30,dy:20);XCTAssertNotEqual(view.target.x,target.x)
        view.fit(columns:braid.columns,rows:braid.rows,oblique:true)
        let settings=SceneSettings(planeColor:RGB(0.3,0.25,0.15),planeDistance:0.8)
        view.updatePlane(braid,settings:settings)
        let node=try XCTUnwrap(view.scene?.rootNode.childNode(withName:"Backing plane",recursively:false))
        XCTAssertNotNil(node.geometry)
        view.updatePlane(braid,settings:project.sceneSettings!)
        view.zoom(factor:0.9);view.pan(dx:15,dy:-10)
        let position=view.cameraNode.position,orientation=view.cameraNode.orientation
        let cg=try view.captureImage()
        XCTAssertEqual(Double(cg.width)/Double(cg.height),1.25,accuracy:0.001)
        XCTAssertEqual(view.cameraNode.position.x,position.x);XCTAssertEqual(view.cameraNode.position.y,position.y);XCTAssertEqual(view.cameraNode.position.z,position.z)
        XCTAssertEqual(view.cameraNode.orientation.x,orientation.x);XCTAssertEqual(view.cameraNode.orientation.y,orientation.y);XCTAssertEqual(view.cameraNode.orientation.z,orientation.z);XCTAssertEqual(view.cameraNode.orientation.w,orientation.w)
        let folder=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/curve-validation")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let destination=folder.appendingPathComponent("metal-perspective.png")
        try ImageProcessor.writePNG(cg,to:destination)
        let source=try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL,nil))
        let saved=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(saved.width,cg.width);XCTAssertEqual(saved.height,cg.height)
        let pixels=try ImageProcessor.pixels(from:cg)
        XCTAssertGreaterThan(Set(pixels.pixels).count,20,"Metal snapshot should contain lit colored geometry")
    }
}
