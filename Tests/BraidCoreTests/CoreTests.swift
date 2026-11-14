import XCTest
import CoreGraphics
@testable import BraidCore

final class CoreTests: XCTestCase {
    func image(_ w:Int=3,_ h:Int=3)->PixelImage {
        PixelImage(width:w,height:h,pixels:(0..<(w*h)).map{ i in RGB(Double((i*37)%101)/100,Double((i*71)%101)/100,Double((i*19)%101)/100)})
    }
    func solver() throws -> URL {
        guard let url=CBCRunner.discover() else { throw XCTSkip("Build COIN-OR CBC with Scripts/build-solver.sh") };return url
    }
    func testNotebookTileOrderWeightsAndEdges() throws {
        let d=TileData(settings:Settings())
        XCTAssertEqual(d.allTiles.count,16)
        XCTAssertEqual(d.allTiles.map(\.id),Array(1...16))
        // Mathematica: first color changes every two tiles; kinds have groups of four.
        XCTAssertEqual(d.allTiles[2].kind,.vCross)
        XCTAssertEqual(d.allTiles[2].firstColor,1);XCTAssertEqual(d.allTiles[2].secondColor,0)
        XCTAssertEqual(d.allTiles[4].kind,.hCross)
        XCTAssertEqual(d.allTiles[9].kind,.circLeft)
        XCTAssertEqual(d.allTiles[9].left,0);XCTAssertEqual(d.allTiles[9].top,0)
        XCTAssertEqual(d.allTiles[9].right,1);XCTAssertEqual(d.allTiles[9].bottom,1)
        XCTAssertEqual(d.allTiles[13].top,1);XCTAssertEqual(d.allTiles[13].bottom,0)
        XCTAssertEqual(d.allTiles[0].average.r,0.2,accuracy:1e-12)
        XCTAssertEqual(d.allTiles[3].average.r,0.8,accuracy:1e-12)
        XCTAssertEqual(d.allTiles[8].average.r,0.5*(1-Double.pi*0.414/2),accuracy:1e-12)
    }
    // Sharma–Wu–Dalal reference data; origin and paper citation: Licenses/README.md.
    func testCIEDE2000PublishedReferencePairs() {
        let pairs: [(Lab,Lab,Double)] = [
            (Lab(50,2.6772,-79.7751),Lab(50,0,-82.7485),2.0425),
            (Lab(50,3.1571,-77.2803),Lab(50,0,-82.7485),2.8615),
            (Lab(50,2.8361,-74.0200),Lab(50,0,-82.7485),3.4412),
            (Lab(50,-1.3802,-84.2814),Lab(50,0,-82.7485),1.0000),
            (Lab(50,0,0),Lab(50,-1,2),2.3669),
            (Lab(50,2.49,-0.001),Lab(50,-2.49,0.001),7.1792)
        ]
        for (a,b,expected) in pairs {
            XCTAssertEqual(a.distance(to:b),expected,accuracy:0.0001)
            XCTAssertEqual(b.distance(to:a),expected,accuracy:0.0001)
        }
        XCTAssertEqual(Lab(sRGB:.white).l,100,accuracy:0.0001)
    }
    func testMetalMatchesCPU() throws {
        let input=image(8,8),tiles=TileData(settings:Settings())
        let cpu=try CostEngine.compute(image:input,tiles:tiles,useGPU:false)
        let gpu=try CostEngine.compute(image:input,tiles:tiles)
        let maxError=zip(cpu.values,gpu.values).map{abs($0-$1)}.max() ?? 0
        XCTAssertLessThan(maxError,0.003)
        if !gpu.backend.hasPrefix("Metal") {throw XCTSkip("Metal unavailable in this execution environment; CPU fallback verified")}
    }
    func testCBCMatchesBruteForceAndBothSeams() async throws {
        let executable=try solver(),input=image(2,2)
        var settings=Settings();settings.relativeGap=0;settings.secondsPerPartition=10;settings.threads=1
        let data=TileData(settings:settings),costs=try CostEngine.compute(image:input,tiles:data,useGPU:false)
        // Fixed incoming black/white colors exercise both seams, including their intersection.
        let left=[2,3],top=[2,3]
        let p=try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:2,height:2),image:input,data:data,costs:costs,left:left,top:top)
        let text=try await CBCRunner.solve(problem:p,executable:executable,settings:settings)
        let parsed=try PartitionSolver.parseSolution(text,problem:p,data:data)
        var best=Double.infinity
        for a in data.allTiles where a.left==data.allTiles[left[0]-1].right && a.top==data.allTiles[top[0]-1].bottom {
            for b in data.allTiles where a.right==b.left && b.top==data.allTiles[top[1]-1].bottom {
                for c in data.allTiles where a.bottom==c.top && c.left==data.allTiles[left[1]-1].right {
                    for d in data.allTiles where b.bottom==d.top && c.right==d.left {
                        best=min(best,costs[0,a.id-1]+costs[1,b.id-1]+costs[2,c.id-1]+costs[3,d.id-1])
                    }
                }
            }
        }
        let objective=parsed.ids.enumerated().reduce(0.0){$0+costs[$1.offset,$1.element-1]}
        XCTAssertEqual(objective,best,accuracy:1e-5);XCTAssertTrue(parsed.optimal)
    }
    func testPartitionsRemaindersAndRoundTrip() async throws {
        var settings=Settings();settings.columns=8;settings.partitionSize=2;settings.secondsPerPartition=5;settings.threads=1
        let input=image(5,3)
        let (data,result)=try await PartitionSolver.solve(image:input,settings:settings,executable:solver())
        XCTAssertEqual(result.solution.count,3);XCTAssertEqual(result.solution[0].count,5);XCTAssertEqual(result.reports.count,6)
        try result.validate(tileData:data)
        XCTAssertEqual(result.reports.map{"\($0.row),\($0.column)"},["0,0","0,1","0,2","1,0","1,1","1,2"])
        let project=BraidProject(sourceName:"fixture.png",settings:settings,sampledImage:input,tileData:data,result:result)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try ProjectExporter.export(project,to:folder,tileSize:20)
        let loaded=try BraidProject.load(from:folder.appendingPathComponent("project.braidart"))
        XCTAssertEqual(loaded.result,result);XCTAssertEqual(loaded.tileData,data);XCTAssertEqual(loaded.sampledImage,input)
        let files=try FileManager.default.contentsOfDirectory(atPath:folder.appendingPathComponent("tiles").path)
        XCTAssertEqual(files.count,16)
        let wl=try String(contentsOf:folder.appendingPathComponent("data.wl"),encoding:.utf8)
        XCTAssertTrue(wl.contains("DarkKnot[VCross[{RGBColor["));XCTAssertTrue(wl.contains("\"allTilesImg\" -> {Import["))
    }
    func testRejectsRelaxationsBrokenTopologyAndCorruptProjects() throws {
        let input=image(2,1),data=TileData(settings:Settings()),costs=try CostEngine.compute(image:input,tiles:data,useGPU:false)
        let p=try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:2,height:1),image:input,data:data,costs:costs)
        XCTAssertThrowsError(try PartitionSolver.parseSolution("Stopped on time (no integer solution - continuous used)\n0 x0_1 1\n1 x1_1 1",problem:p,data:data))
        XCTAssertThrowsError(try PartitionSolver.parseSolution("Optimal\n0 x0_1 0.5\n1 x0_2 0.5\n2 x1_1 1",problem:p,data:data))
        XCTAssertThrowsError(try PartitionSolver.parseSolution("Optimal\n0 x0_1 1\n1 x1_3 1",problem:p,data:data))
        var settings=Settings();settings.palette=[.black,.black]
        XCTAssertThrowsError(try settings.validate())
        var result=SolveResult(solution:[[99]],reports:[],costBackend:"CPU",elapsedSeconds:0)
        XCTAssertThrowsError(try result.validate(tileData:data));result.solution=[[1,1],[1]]
        XCTAssertThrowsError(try result.validate(tileData:data))
    }
    func testImageOrientationCropAndResize() throws {
        let source=PixelImage(width:8,height:8,pixels:(0..<64).map{$0<32 ? .white : .black})
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        defer {try? FileManager.default.removeItem(at:url)}
        let cg=try ImageProcessor.cgImage(source)
        try ImageProcessor.writePNG(cg,to:url)
        let sampled=try ImageProcessor.pixels(from:cg)
        XCTAssertEqual(sampled.pixels.first,.white);XCTAssertEqual(sampled.pixels.last,.black)
        var settings=Settings();settings.columns=8;settings.crop=Crop(x:0,y:0,width:1,height:0.5)
        let prepared=try ImageProcessor.prepare(url:url,settings:settings)
        XCTAssertEqual(prepared.width,8);XCTAssertEqual(prepared.height,4)
        XCTAssertGreaterThan(prepared.pixels[0].r,0.9)
        XCTAssertGreaterThan(prepared.pixels[prepared.pixels.count-1].r,0.9)
        settings.crop=Crop(x:0,y:0.5,width:1,height:0.5)
        let bottom=try ImageProcessor.prepare(url:url,settings:settings)
        XCTAssertLessThan(bottom.pixels[0].r,0.1)
    }
    func testDominantPaletteDeterministicAndSingleColor() {
        let i=PixelImage(width:4,height:2,pixels:[.black,.white,.black,.white,.black,.white,.black,.white])
        XCTAssertEqual(PaletteExtractor.dominantColors(in:i,count:4),[.black,.white])
        XCTAssertEqual(PaletteExtractor.dominantColors(in:PixelImage(width:2,height:1,pixels:[.gray,.gray]),count:4),[.gray])
    }
    func testColorPaletteAndSingleTilePartitions() async throws {
        var settings=Settings();settings.palette=[RGB(0.1,0.3,0.7),RGB(0.9,0.5,0.1),RGB(0.8,0.1,0.2)]
        settings.partitionSize=1;settings.threads=1;settings.secondsPerPartition=5
        let input=image(3,3),data=TileData(settings:settings)
        let gpu=try CostEngine.compute(image:input,tiles:data),cpu=try CostEngine.compute(image:input,tiles:data,useGPU:false)
        XCTAssertLessThan(zip(gpu.values,cpu.values).map{abs($0-$1)}.max() ?? 0,0.003)
        let (_,result)=try await PartitionSolver.solve(image:input,settings:settings,executable:solver())
        XCTAssertEqual(result.reports.count,9);try result.validate(tileData:data)
    }
    func testCBCReadsFiveColorObjectiveAtReaderBufferBoundary() async throws {
        var settings=Settings()
        settings.palette=[.black,.white,RGB(1,0,0),RGB(0,1,0),RGB(0,0,1)]
        settings.threads=1;settings.relativeGap=0;settings.secondsPerPartition=5
        let input=image(1,1),data=TileData(settings:settings)
        // These 100 coefficients produce a 2046-byte objective line in the old
        // writer: exactly two 1023-byte input chunks in CoinUtils 2.11.12.
        // CBC then reports "End inserted / Unable to read objective function".
        let values=(0..<100).map { Float($0<46 ? 1 : 10) }
        let costs=CostTable(values:values,tileCount:100,backend:"regression fixture")
        let originalLine=data.allTiles.map { String(format:" + %.9f %@",locale:Locale(identifier:"en_US_POSIX"),costs[0,$0.id-1],"x0_\($0.id)") }.joined()
        XCTAssertEqual(originalLine.utf8.count,2046)
        let problem=try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:1,height:1),image:input,data:data,costs:costs)
        let text=try await CBCRunner.solve(problem:problem,executable:solver(),settings:settings)
        let parsed=try PartitionSolver.parseSolution(text,problem:problem,data:data)
        XCTAssertEqual(parsed.ids.count,1)
        XCTAssertEqual(costs[0,parsed.ids[0]-1],1)
        XCTAssertTrue(parsed.optimal)
    }
    func testCBCReadsMaximumPaletteWithBothIncomingBoundaries() async throws {
        var settings=Settings()
        settings.palette=[.black,.white,RGB(1,0,0),RGB(0,1,0),RGB(0,0,1),RGB(1,1,0),RGB(0,1,1),RGB(1,0,1)]
        settings.threads=1;settings.relativeGap=0;settings.secondsPerPartition=5
        let input=image(2,2),data=TileData(settings:settings)
        let costs=CostTable(values:Array(repeating:Float(1),count:4*256),tileCount:256,backend:"regression fixture")
        let left=[1,1],top=[1,1]
        let problem=try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:2,height:2),image:input,data:data,costs:costs,left:left,top:top)
        let text=try await CBCRunner.solve(problem:problem,executable:solver(),settings:settings)
        let parsed=try PartitionSolver.parseSolution(text,problem:problem,data:data)
        XCTAssertEqual(parsed.ids.count,4)
        XCTAssertTrue(parsed.optimal)
    }
    func testCancellationStopsChildAndCleansFiles() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let exe=root.appendingPathComponent("cbc-test")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to:exe,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:exe.path)
        let input=image(1,1),data=TileData(settings:Settings()),costs=try CostEngine.compute(image:input,tiles:data,useGPU:false)
        let p=try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:1,height:1),image:input,data:data,costs:costs)
        let started=Date(),task=Task {try await CBCRunner.solve(problem:p,executable:exe,settings:Settings())}
        try await Task.sleep(nanoseconds:150_000_000);task.cancel()
        do { _=try await task.value;XCTFail("Expected cancellation") } catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
        XCTAssertLessThan(Date().timeIntervalSince(started),2)
    }

}
