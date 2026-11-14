import XCTest
import AppKit
import SceneKit
import Metal
import ImageIO
import ModelIO
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
        var pdfProgress=[Double]()
        try CurveExporter.writePDF(braid,to:pdf) { value,_ in pdfProgress.append(value) }
        XCTAssertEqual(pdfProgress.first,0);XCTAssertEqual(pdfProgress.last,1)
        XCTAssertEqual(pdfProgress,pdfProgress.sorted())
        XCTAssertTrue(pdfProgress.allSatisfy { $0.isFinite && (0...1).contains($0) })
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
    func testPDFCancellationPreservesDestination() async throws {
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let pdf=folder.appendingPathComponent("cancelled.pdf"),original=Data("existing file".utf8)
        // Cancel at preparation, finalization and immediately before the atomic write.
        for milestone in [0.0,0.9,0.97] {
            for existing in [false,true] {
                if existing { try original.write(to:pdf) }
                let task=Task.detached {
                    try CurveExporter.writePDF(braid,to:pdf) { value,_ in
                        if value == milestone { withUnsafeCurrentTask { $0?.cancel() } }
                    }
                }
                do { try await task.value;XCTFail("Expected cancellation at \(milestone)") }
                catch is CancellationError {}
                catch { XCTFail("Unexpected error: \(error)") }
                if existing {
                    XCTAssertEqual(try Data(contentsOf:pdf),original)
                    try FileManager.default.removeItem(at:pdf)
                } else { XCTAssertFalse(FileManager.default.fileExists(atPath:pdf.path)) }
            }
        }
        // A later export still succeeds after a cancelled attempt.
        try CurveExporter.writePDF(braid,to:pdf)
        XCTAssertEqual(CGPDFDocument(pdf as CFURL)?.numberOfPages,1)
    }
    func testUSDZExportRoundTrip() throws {
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let meshes=try TubeMesher.build(braid)+[TubeMesher.plane(braid,settings:project.sceneSettings!)]
        let folder=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".build/curve-validation")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let url=folder.appendingPathComponent("braid.usdz")
        var updates=[Double]()
        try USDZExporter.write(meshes:meshes,to:url) { value,_ in updates.append(value) }
        XCTAssertEqual(updates.first,0);XCTAssertEqual(updates.last,1)
        XCTAssertEqual(updates,updates.sorted())
        XCTAssertEqual(Array(try Data(contentsOf:url).prefix(4)),[0x50,0x4b,0x03,0x04],"USDZ must be a package")
        let imported=try SCNScene(url:url,options:nil)
        var geometries=[SCNGeometry]()
        imported.rootNode.enumerateChildNodes { node,_ in if let geometry=node.geometry { geometries.append(geometry) } }
        XCTAssertEqual(geometries.count,meshes.count)
        XCTAssertEqual(geometries.reduce(0) { $0+$1.elements.reduce(0) { $0+$1.primitiveCount } },meshes.reduce(0) { $0+$1.indices.count/3 })
        XCTAssertTrue(geometries.allSatisfy { !$0.sources(for:.normal).isEmpty })
        XCTAssertEqual(MDLAsset(url:url).childObjects(of:MDLMesh.self).count,meshes.count)
        let bounds=imported.rootNode.boundingBox
        XCTAssertEqual(bounds.min.x+bounds.max.x,0,accuracy:0.0001)
        XCTAssertEqual(bounds.min.y+bounds.max.y,0,accuracy:0.0001)
        XCTAssertEqual(bounds.min.z+bounds.max.z,0,accuracy:0.0001)
        let linearSpace=try XCTUnwrap(CGColorSpace(name:CGColorSpace.extendedLinearSRGB))
        let materials:[SCNMaterial]=geometries.compactMap { $0.firstMaterial }
        for mesh in meshes {
            let expected=try XCTUnwrap(CGColor(srgbRed:mesh.color.r,green:mesh.color.g,blue:mesh.color.b,alpha:1).converted(to:linearSpace,intent:.defaultIntent,options:nil)?.components)
            let material=try XCTUnwrap(materials.first { material in
                // Check the linear USD shader values; the native importer tags these colors with its display profile.
                guard let color=material.diffuse.contents as? NSColor else { return false }
                return abs(color.redComponent-expected[0])<0.001 && abs(color.greenComponent-expected[1])<0.001 && abs(color.blueComponent-expected[2])<0.001
            },"Missing material color for \(mesh.name)")
            XCTAssertEqual((material.roughness.contents as? NSNumber)?.doubleValue ?? -1,mesh.name=="Backing plane" ? 0.65 : 0.23,accuracy:0.001)
        }
        let bytes=try Data(contentsOf:url)
        func u16(_ offset:Int)->Int { Int(bytes[offset]) | Int(bytes[offset+1])<<8 }
        let offset=30+u16(26)+u16(28)
        XCTAssertEqual(u16(8),0,"USDZ entries must be uncompressed")
        XCTAssertEqual(offset%64,0,"USDZ payloads must be aligned to 64 bytes")
        XCTAssertTrue(String(decoding:bytes[offset...],as:UTF8.self).contains("prepend apiSchemas = [\"MaterialBindingAPI\"]"))
    }
    func testUSDZCancellationAndInvalidMeshesPreserveDestination() async throws {
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let meshes=try TubeMesher.build(braid)+[TubeMesher.plane(braid,settings:project.sceneSettings!)]
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url=folder.appendingPathComponent("cancelled.usdz"),original=Data("existing file".utf8)
        for milestone in [0.0,0.85,0.97] {
            for existing in [false,true] {
                if existing { try original.write(to:url) }
                let task=Task.detached {
                    try USDZExporter.write(meshes:meshes,to:url) { value,_ in
                        if value==milestone { withUnsafeCurrentTask { $0?.cancel() } }
                    }
                }
                do { try await task.value;XCTFail("Expected cancellation") }
                catch is CancellationError {}
                catch { XCTFail("Unexpected error: \(error)") }
                if existing {
                    XCTAssertEqual(try Data(contentsOf:url),original)
                    try FileManager.default.removeItem(at:url)
                } else { XCTAssertFalse(FileManager.default.fileExists(atPath:url.path)) }
            }
        }
        try original.write(to:url)
        var invalid=meshes[0];invalid.indices=[0,1]
        XCTAssertThrowsError(try USDZExporter.write(meshes:[invalid],to:url))
        invalid=meshes[0];invalid.normals[0].x = .nan
        XCTAssertThrowsError(try USDZExporter.write(meshes:[invalid],to:url))
        invalid=meshes[0];invalid.indices[0]=UInt32.max
        XCTAssertThrowsError(try USDZExporter.write(meshes:[invalid],to:url))
        XCTAssertThrowsError(try USDZExporter.write(meshes:[],to:url))
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    @MainActor func testPictureExportKeepsCurrentCameraAcrossAspectRatios() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal device unavailable") }
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let view=BraidMetalView(frame:CGRect(x:0,y:0,width:1000,height:800))
        view.display(braid,meshes:try TubeMesher.build(braid),settings:project.sceneSettings!)
        let referenceSize=CGSize(width:1000,height:800)
        let initial=try view.makePictureCapture()
        let before=try await Task.detached { try initial.render(size:referenceSize) }.value
        func difference(_ a:CGImage,_ b:CGImage) throws -> Double {
            let ap=try ImageProcessor.pixels(from:a),bp=try ImageProcessor.pixels(from:b)
            XCTAssertEqual(ap.width,bp.width);XCTAssertEqual(ap.height,bp.height)
            return zip(ap.pixels,bp.pixels).reduce(0) { $0+abs($1.0.r-$1.1.r)+abs($1.0.g-$1.1.g)+abs($1.0.b-$1.1.b) }/Double(ap.pixels.count*3)
        }
        view.orbit(dx:0.4,dy:-0.25)
        let rotated=try view.makePictureCapture()
        let rotation=try await Task.detached { try rotated.render(size:referenceSize) }.value
        XCTAssertGreaterThan(try difference(before,rotation),0.03,"Export must reflect rotation")
        view.zoom(factor:0.65)
        let zoomed=try view.makePictureCapture()
        let zoom=try await Task.detached { try zoomed.render(size:referenceSize) }.value
        XCTAssertGreaterThan(try difference(rotation,zoom),0.03,"Export must reflect zoom")
        view.pan(dx:100,dy:-45)
        let current=try view.makePictureCapture()
        let after=try await Task.detached { try current.render(size:referenceSize) }.value
        XCTAssertGreaterThan(try difference(zoom,after),0.03,"Export must reflect pan")
        // Later viewport changes cannot affect the camera frozen before the save panel.
        view.fit(columns:braid.columns,rows:braid.rows)
        let frozen=try await Task.detached { try current.render(size:referenceSize) }.value
        XCTAssertLessThan(try difference(after,frozen),0.01)
        // With the same height, changing aspect ratio must crop the sides, preserving zoom.
        for width in [800,450] {
            let image=try await Task.detached { try current.render(size:CGSize(width:width,height:800)) }.value
            let crop=try XCTUnwrap(after.cropping(to:CGRect(x:(1000-width)/2,y:0,width:width,height:800)))
            XCTAssertLessThan(try difference(crop,image),0.01,"Changing output shape must not zoom out")
        }
    }
    @MainActor func testPictureExportPresetsAndNativeRendering() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal device unavailable") }
        let project=try fixture(),braid=try CurveGenerator.generate(solution:project.result.solution,data:project.tileData)
        let view=BraidMetalView(frame:CGRect(x:0,y:0,width:1000,height:800))
        view.display(braid,meshes:try TubeMesher.build(braid),settings:project.sceneSettings!)
        view.orbit(dx:0.3,dy:-0.25);view.zoom(factor:0.9);view.pan(dx:15,dy:-10)
        let transform=view.cameraNode.transform,fov=view.cameraNode.camera!.fieldOfView
        let expected:[PictureExportSize:CGSize]=[
            .viewport:view.viewportPixelSize,.hd:CGSize(width:1280,height:720),.fullHD:CGSize(width:1920,height:1080),
            .ultraHD:CGSize(width:3840,height:2160),.instagramSquare:CGSize(width:1080,height:1080),
            .instagramPortrait:CGSize(width:1080,height:1350),.instagramTallPortrait:CGSize(width:1080,height:1440),
            .instagramLandscape:CGSize(width:1080,height:566),.instagramStory:CGSize(width:1080,height:1920)]
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        for preset in PictureExportSize.allCases {
            let size=preset.pixelSize(viewport:view.viewportPixelSize)
            XCTAssertEqual(size,expected[preset])
            let capture=try view.makePictureCapture(size:size)
            let cg=try await Task.detached { try capture.render() }.value
            XCTAssertEqual(cg.width,Int(size.width));XCTAssertEqual(cg.height,Int(size.height))
            let url=folder.appendingPathComponent("\(preset.rawValue).png")
            try ImageProcessor.writePNG(cg,to:url)
            let source=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil))
            let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int,Int(size.width))
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int,Int(size.height))
            let thumbnail=try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:64] as CFDictionary))
            XCTAssertGreaterThan(Set(try ImageProcessor.pixels(from:thumbnail).pixels).count,20,"Export must contain the lit scene")
            XCTAssertTrue(SCNMatrix4EqualToMatrix4(view.cameraNode.transform,transform))
            XCTAssertEqual(view.cameraNode.camera!.fieldOfView,fov)
            XCTAssertEqual(view.bounds.size,CGSize(width:1000,height:800))
        }
        for invalid in [CGSize.zero,CGSize(width:3.5,height:500),CGSize(width:8193,height:1),CGSize(width:CGFloat.infinity,height:500)] {
            XCTAssertThrowsError(try view.makePictureCapture(size:invalid))
        }
        // SwiftUI can lay out the viewport on fractional points; exports still use whole pixels.
        view.setFrameSize(CGSize(width:1000.25,height:800.25))
        let viewport=view.viewportPixelSize
        XCTAssertEqual(viewport.width,viewport.width.rounded());XCTAssertEqual(viewport.height,viewport.height.rounded())
        let frozen=try view.makePictureCapture(size:viewport)
        view.scene=nil
        let retained=try await Task.detached { try frozen.render() }.value
        XCTAssertEqual(retained.width,Int(viewport.width));XCTAssertEqual(retained.height,Int(viewport.height))
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
