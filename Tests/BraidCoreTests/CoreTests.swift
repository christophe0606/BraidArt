import XCTest
import CoreGraphics
import ImageIO
@testable import BraidCore

final class CoreTests: XCTestCase {
    func image(_ w:Int=3,_ h:Int=3)->PixelImage {
        PixelImage(width:w,height:h,pixels:(0..<(w*h)).map{ i in RGB(Double((i*37)%101)/100,Double((i*71)%101)/100,Double((i*19)%101)/100)})
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
        let input=image(2,2)
        var settings=Settings();settings.relativeGap=0;settings.secondsPerPartition=10;settings.threads=1
        let data=TileData(settings:settings),costs=try CostEngine.compute(image:input,tiles:data,useGPU:false)
        // Fixed incoming black/white colors exercise both seams, including their intersection.
        let left=[2,3],top=[2,3]
        let p=try PartitionSolver.makeProblem(block:Block(x:0,y:0,width:2,height:2),image:input,data:data,costs:costs,left:left,top:top)
        let text=try await CBCRunner.solve(problem:p,settings:settings)
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
        let (data,result)=try await PartitionSolver.solve(image:input,settings:settings)
        XCTAssertEqual(result.solution.count,3);XCTAssertEqual(result.solution[0].count,5);XCTAssertEqual(result.reports.count,6)
        try result.validate(tileData:data)
        XCTAssertEqual(result.reports.map{"\($0.row),\($0.column)"},["0,0","0,1","0,2","1,0","1,1","1,2"])
        let project=BraidProject(sourceName:"fixture.png",settings:settings,sampledImage:input,tileData:data,result:result)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        try ProjectExporter.export(project,to:folder)
        let loaded=try BraidProject.load(from:folder.appendingPathComponent("project.braidart"))
        XCTAssertEqual(loaded.result,result);XCTAssertEqual(loaded.tileData,data);XCTAssertEqual(loaded.sampledImage,input)
        let files=try FileManager.default.contentsOfDirectory(atPath:folder.appendingPathComponent("tiles").path)
        XCTAssertEqual(files.count,16)
        let preview=try XCTUnwrap(CGImageSourceCreateWithURL(folder.appendingPathComponent("result.png") as CFURL,nil))
        let exported=try XCTUnwrap(CGImageSourceCreateImageAtIndex(preview,0,nil))
        XCTAssertEqual(exported.width,1920);XCTAssertEqual(exported.height,1080)
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
    func testPaletteSeparationMergesShadesUsingTheirPixelPopulations() {
        let red=RGB(0.70,0.15,0.12),redShade=RGB(0.73,0.17,0.14)
        let blue=RGB(0.12,0.20,0.70),blueShade=RGB(0.14,0.22,0.73)
        let gray=RGB(0.45,0.45,0.45),grayShade=RGB(0.48,0.48,0.48)
        let groups=[(red,12),(redShade,4),(blue,8),(blueShade,8),(gray,12),(grayShade,4)]
        let pixels=groups.flatMap { Array(repeating:$0.0,count:$0.1) }
        let image=PixelImage(width:pixels.count,height:1,pixels:pixels)
        let shades=PaletteExtractor.dominantColors(in:image,count:6,minimumDistance:0)
        XCTAssertEqual(shades.count,6)
        let distinct=PaletteExtractor.dominantColors(in:image,count:6)
        XCTAssertEqual(distinct.count,3)
        let expected=[(red*12+redShade*4)*(1/16.0),(blue*8+blueShade*8)*(1/16.0),(gray*12+grayShade*4)*(1/16.0)]
        for color in expected {
            XCTAssertLessThan(distinct.map { Lab(sRGB:$0).distance(to:Lab(sRGB:color)) }.min() ?? .infinity,1e-8)
        }
        XCTAssertEqual(distinct,PaletteExtractor.dominantColors(in:image,count:6))
    }
    func testDistinctPaletteRetainsSmallMutedAccentsAgainstLargeBrownRegions() {
        let skin=RGB(0.76,0.60,0.53),hair=RGB(0.58,0.47,0.35),dark=RGB(0.08,0.06,0.04)
        let accents=[RGB(0.36,0.48,0.54),RGB(0.88,0.89,0.90),RGB(0.66,0.29,0.32)]
        var pixels=Array(repeating:skin,count:5000)+Array(repeating:hair,count:2500)+Array(repeating:dark,count:1500)
        for accent in accents { pixels+=Array(repeating:accent,count:8) }
        let input=PixelImage(width:pixels.count,height:1,pixels:pixels)
        let colors=PaletteExtractor.distinctColors(in:input,count:6,minimumDistance:6)
        XCTAssertEqual(colors.count,6)
        for accent in accents {
            XCTAssertLessThan(colors.map{Lab(sRGB:$0).distance(to:Lab(sRGB:accent))}.min() ?? .infinity,1e-8)
        }
        XCTAssertEqual(colors,PaletteExtractor.distinctColors(in:input,count:6,minimumDistance:6))
        for separation in [6.0,12,20] {
            let colors=PaletteExtractor.distinctColors(in:input,count:8,minimumDistance:separation)
            XCTAssertLessThanOrEqual(colors.count,8)
            for i in colors.indices { for j in (i+1)..<colors.count {
                XCTAssertGreaterThanOrEqual(Lab(sRGB:colors[i]).distance(to:Lab(sRGB:colors[j])),separation)
            } }
        }
    }
    func testDistinctPaletteHandlesSinglePixelAccentsAndIsolatedPhotographNoise() {
        let blue=RGB(0.2,0.4,0.8)
        let small=PixelImage(width:4,height:1,pixels:[.gray,.gray,.gray,blue])
        XCTAssertEqual(PaletteExtractor.distinctColors(in:small,count:6).count,2)
        var pixels=Array(repeating:RGB.gray,count:4096);pixels[0]=blue
        let large=PixelImage(width:64,height:64,pixels:pixels)
        XCTAssertEqual(PaletteExtractor.distinctColors(in:large,count:6),[.gray])
        XCTAssertEqual(PaletteExtractor.distinctColors(in:small,count:1),[.gray])
    }
    func testDistinctPaletteReservesHighlightsAndShadowsAlongsideTheMainColor() {
        let skin=RGB(0.76,0.60,0.53),white=RGB(0.90,0.91,0.92),dark=RGB(0.03,0.02,0.01)
        var pixels=Array(repeating:skin,count:5000)
        for color in [white,dark,RGB(0.36,0.48,0.54),RGB(0.66,0.29,0.32)] { pixels+=Array(repeating:color,count:4) }
        let colors=PaletteExtractor.distinctColors(in:PixelImage(width:pixels.count,height:1,pixels:pixels),count:3,minimumDistance:6)
        XCTAssertEqual(colors.count,3)
        for color in [skin,white,dark] {
            XCTAssertLessThan(colors.map{Lab(sRGB:$0).distance(to:Lab(sRGB:color))}.min() ?? .infinity,1e-8)
        }
    }
    func testDistinctPaletteFavorsVisibleAccentsOverAdditionalColoredShadows() {
        let skin=RGB(0.79,0.64,0.58),dark=RGB(0.02,0.01,0.01),white=RGB(0.98,0.89,0.90)
        let shadow=RGB(0.25,0.11,0.02),hair=RGB(0.58,0.44,0.37),eye=RGB(0.46,0.49,0.49),lip=RGB(0.55,0.25,0.25)
        var pixels=Array(repeating:skin,count:5000)
        for color in [dark,white,shadow,hair,eye,lip] { pixels+=Array(repeating:color,count:8) }
        let colors=PaletteExtractor.distinctColors(in:PixelImage(width:pixels.count,height:1,pixels:pixels),count:6,minimumDistance:6)
        XCTAssertEqual(colors.count,6)
        for color in [skin,dark,white,hair,eye,lip] {
            XCTAssertLessThan(colors.map{Lab(sRGB:$0).distance(to:Lab(sRGB:color))}.min() ?? .infinity,1e-8)
        }
    }
    func testDetailedPaletteSamplePreservesSmallFeaturesAndImagePreparation() throws {
        let skin=RGB(0.8,0.6,0.5),blue=RGB(0.2,0.4,0.8)
        var pixels=Array(repeating:skin,count:128*128)
        for y in 40..<48 { for x in 30..<38 { pixels[y*128+x]=blue } }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        defer { try? FileManager.default.removeItem(at:url) }
        try ImageProcessor.writePNG(ImageProcessor.cgImage(PixelImage(width:128,height:128,pixels:pixels)),to:url)
        var settings=Settings();settings.columns=8;settings.crop=Crop(x:0.2,y:0.2,width:0.5,height:0.5)
        let detail=try ImageProcessor.preparePalette(url:url,settings:settings)
        XCTAssertGreaterThan(detail.width,8)
        XCTAssertLessThanOrEqual(max(detail.width,detail.height),512)
        XCTAssertLessThan(detail.pixels.map{Lab(sRGB:$0).distance(to:Lab(sRGB:blue))}.min() ?? .infinity,1)
        settings.columns=32
        XCTAssertEqual(try ImageProcessor.preparePalette(url:url,settings:settings),detail)
        settings.grayscale=true
        let gray=try ImageProcessor.preparePalette(url:url,settings:settings)
        XCTAssertTrue(gray.pixels.allSatisfy{abs($0.r-$0.g)<=1/255.0 && abs($0.g-$0.b)<=1/255.0})
        settings.grayscale=false;settings.crop=Crop(x:0.7,y:0.2,width:0.3,height:0.5)
        let other=try ImageProcessor.preparePalette(url:url,settings:settings)
        XCTAssertGreaterThan(other.pixels.map{Lab(sRGB:$0).distance(to:Lab(sRGB:blue))}.min() ?? 0,20)
    }
    func testPaletteSeparationThresholdControlsWhetherShadesAreMerged() {
        let dark=RGB(0.45,0.45,0.45),light=RGB(0.55,0.55,0.55)
        let image=PixelImage(width:4,height:1,pixels:[dark,light,dark,light])
        let distance=Lab(sRGB:dark).distance(to:Lab(sRGB:light))
        XCTAssertGreaterThan(distance,6);XCTAssertLessThan(distance,12)
        XCTAssertEqual(PaletteExtractor.dominantColors(in:image,count:4,minimumDistance:6).count,2)
        XCTAssertEqual(PaletteExtractor.dominantColors(in:image,count:4,minimumDistance:12),[.gray])
        XCTAssertEqual(PaletteExtractor.dominantColors(in:image,count:4,minimumDistance:20),[.gray])
    }
    func testPaletteSeparationPreservesDifferentAccentsAmongManyGrayShades() {
        let red=RGB(0.8,0.1,0.1),blue=RGB(0.1,0.1,0.8)
        var pixels=(0..<80).map { i -> RGB in
            let value=0.4+Double(i%20)*0.01
            return RGB(value,value,value)
        }
        pixels+=Array(repeating:red,count:10)+Array(repeating:blue,count:10)
        let image=PixelImage(width:100,height:1,pixels:pixels)
        let colors=PaletteExtractor.dominantColors(in:image,count:3)
        XCTAssertEqual(colors.count,3)
        for accent in [red,blue] {
            XCTAssertLessThan(colors.map { Lab(sRGB:$0).distance(to:Lab(sRGB:accent)) }.min() ?? .infinity,1e-8)
        }
    }
    func testExtractedPaletteRespectsFinalSeparationAndMaximumCount() {
        let input=image(64,64)
        for separation in [6.0,12.0,20.0] {
            let colors=PaletteExtractor.dominantColors(in:input,count:8,minimumDistance:separation)
            XCTAssertTrue((1...8).contains(colors.count));XCTAssertTrue(colors.allSatisfy(\.valid))
            for i in colors.indices {
                for j in (i+1)..<colors.count {
                    XCTAssertGreaterThanOrEqual(Lab(sRGB:colors[i]).distance(to:Lab(sRGB:colors[j])),separation)
                }
            }
            XCTAssertEqual(colors,PaletteExtractor.dominantColors(in:input,count:8,minimumDistance:separation))
        }
        XCTAssertEqual(PaletteExtractor.dominantColors(in:input,count:1).count,1)
    }
    func testColorPaletteAndSingleTilePartitions() async throws {
        var settings=Settings();settings.palette=[RGB(0.1,0.3,0.7),RGB(0.9,0.5,0.1),RGB(0.8,0.1,0.2)]
        settings.partitionSize=1;settings.threads=1;settings.secondsPerPartition=5
        let input=image(3,3),data=TileData(settings:settings)
        let gpu=try CostEngine.compute(image:input,tiles:data),cpu=try CostEngine.compute(image:input,tiles:data,useGPU:false)
        XCTAssertLessThan(zip(gpu.values,cpu.values).map{abs($0-$1)}.max() ?? 0,0.003)
        let (_,result)=try await PartitionSolver.solve(image:input,settings:settings)
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
        let text=try await CBCRunner.solve(problem:problem,settings:settings)
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
        let text=try await CBCRunner.solve(problem:problem,settings:settings)
        let parsed=try PartitionSolver.parseSolution(text,problem:problem,data:data)
        XCTAssertEqual(parsed.ids.count,4)
        XCTAssertTrue(parsed.optimal)
    }

}
