import XCTest
@testable import BraidCore

final class BackgroundTests:XCTestCase {
    private func error(_ image:PixelImage,settings:Settings)->Double {
        let tiles=TileData(settings:settings).allTiles.map { Lab(sRGB:$0.average) }
        return image.pixels.reduce(0) { total,color in
            total+(tiles.map { Lab(sRGB:color).distance(to:$0) }.min() ?? .infinity)
        }/Double(image.pixels.count)
    }
    private func assertVisible(_ match:BackgroundExtractor.Match,minimumDistance:Double=BackgroundExtractor.minimumStrandDistance,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertTrue(match.background.valid,file:file,line:line)
        XCTAssertFalse(match.palette.isEmpty,file:file,line:line)
        for color in match.palette {
            XCTAssertGreaterThanOrEqual(Lab(sRGB:color).distance(to:Lab(sRGB:match.background)),
                                       minimumDistance,file:file,line:line)
        }
    }

    func testIncreasingTheThresholdProducesStrongerBackgroundSeparation() throws {
        let image=PixelImage(width:4,height:1,pixels:Array(repeating:.black,count:4))
        var settings=Settings();settings.grayscale=true;settings.palette=[.black]
        var previous=0.0
        for threshold in [5.0,15,25,35,50] {
            settings.backgroundMinimumDistance=threshold
            let match=try BackgroundExtractor.matching(image,settings:settings)
            assertVisible(match,minimumDistance:threshold)
            XCTAssertEqual(match.palette,[.black])
            let distance=Lab(sRGB:.black).distance(to:Lab(sRGB:match.background))
            XCTAssertGreaterThan(distance,previous)
            XCTAssertLessThan(distance,threshold+2)
            previous=distance
        }
    }

    func testThresholdRoundTripsAndOlderProjectsKeepTheDefault() throws {
        var settings=Settings()
        XCTAssertEqual(settings.backgroundMinimumDistance,15)
        settings.backgroundMinimumDistance=28
        let data=try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self,from:data),settings)
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        old.removeValue(forKey:"backgroundMinimumDistance")
        let decoded=try JSONDecoder().decode(Settings.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(decoded.backgroundMinimumDistance,15)
        XCTAssertTrue(decoded.hasSameImagePreparation(as:settings))
    }

    func testInvalidAndUnachievableThresholdsDoNotSilentlyWeakenContrast() throws {
        let image=PixelImage(width:1,height:1,pixels:[.gray])
        for invalid in [0.0,-1,51,.infinity,.nan] {
            var settings=Settings();settings.backgroundMinimumDistance=invalid
            XCTAssertThrowsError(try settings.validate())
            XCTAssertThrowsError(try BackgroundExtractor.matching(image,settings:settings))
        }
        var settings=Settings();settings.grayscale=true;settings.palette=[RGB(0.46,0.46,0.46)]
        settings.backgroundMinimumDistance=50
        XCTAssertThrowsError(try BackgroundExtractor.matching(image,settings:settings)) { error in
            XCTAssertEqual(error.localizedDescription,L("No background can meet the selected contrast with these strand colors. Lower Background contrast and extract again."))
        }
    }

    func testUniformSourceKeepsItsStrandVisibleWhileFittingTheBackground() throws {
        let color=RGB(0.18,0.42,0.73)
        let image=PixelImage(width:4,height:1,pixels:Array(repeating:color,count:4))
        var settings=Settings();settings.palette=[color];settings.background=RGB(1,0,1)
        let previous=error(image,settings:settings)
        let match=try BackgroundExtractor.matching(image,settings:settings)
        assertVisible(match);XCTAssertEqual(match.palette,[color])
        settings.background=match.background
        XCTAssertLessThan(error(image,settings:settings),previous)
    }

    func testAnExactButInvisibleBackgroundIsNeverKept() throws {
        for grayscale in [false,true] {
            for tone in [RGB.black,RGB(0.02,0.02,0.02),.gray,.white] {
                var settings=Settings();settings.palette=[tone];settings.background=tone;settings.grayscale=grayscale
                let image=PixelImage(width:1,height:1,pixels:[tone])
                let match=try BackgroundExtractor.matching(image,settings:settings)
                assertVisible(match);XCTAssertEqual(match.palette,[tone])
                if grayscale { XCTAssertEqual(match.background.r,match.background.g);XCTAssertEqual(match.background.g,match.background.b) }
            }
        }
    }

    func testFittingReducesTheRealTileColorErrorForDifferentGeometries() throws {
        for (width,gap) in [(0.2,0.1),(0.414,0.4),(0.6,0.3)] {
            var truth=Settings();truth.strandWidth=width;truth.gap=gap
            truth.palette=[RGB(0.05,0.08,0.15),RGB(0.9,0.8,0.7),RGB(0.65,0.2,0.1)]
            truth.background=RGB(0.12,0.32,0.5)
            let colors=TileData(settings:truth).allTiles.map(\.average)
            let image=PixelImage(width:colors.count,height:1,pixels:colors)
            var fitted=truth;fitted.background=RGB(1,0,1)
            let previous=error(image,settings:fitted)
            let match=try BackgroundExtractor.matching(image,settings:fitted)
            assertVisible(match);fitted.background=match.background;fitted.palette=match.palette
            XCTAssertLessThan(error(image,settings:fitted),previous*0.5)
            XCTAssertEqual(fitted.palette,truth.palette)
        }
    }

    func testGrayFittingIsDeterministicAndKeepsAnOptimalContrastingBackground() throws {
        let colors=(0..<24).map { i -> RGB in let value=Double(i)/23;return RGB(value,value,value) }
        let image=PixelImage(width:24,height:1,pixels:colors)
        var settings=Settings();settings.grayscale=true;settings.palette=[.black,.gray,.white]
        settings.background=RGB(0.9,0.05,0.7)
        let match=try BackgroundExtractor.matching(image,settings:settings)
        assertVisible(match)
        XCTAssertEqual(match.background.r,match.background.g);XCTAssertEqual(match.background.g,match.background.b)
        let repeated=try BackgroundExtractor.matching(image,settings:settings)
        XCTAssertEqual(match.background,repeated.background);XCTAssertEqual(match.palette,repeated.palette)
        settings.palette=[.black];settings.background = .white
        let target=TileData(settings:settings).allTiles[0].average
        let optimal=try BackgroundExtractor.matching(PixelImage(width:1,height:1,pixels:[target]),settings:settings)
        XCTAssertEqual(optimal.background,.white);XCTAssertEqual(optimal.palette,[.black])
    }

    func testDenseGrayPaletteOmitsConflictingShadesInsteadOfRelaxingContrast() throws {
        var settings=Settings();settings.grayscale=true
        settings.palette=(0..<8).map { i in let v=Double(i)/7;return RGB(v,v,v) }
        let image=PixelImage(width:8,height:1,pixels:settings.palette)
        let match=try BackgroundExtractor.matching(image,settings:settings)
        assertVisible(match)
        XCTAssertLessThan(match.palette.count,8)
        XCTAssertGreaterThanOrEqual(match.palette.count,5)
        XCTAssertTrue(match.palette.allSatisfy { settings.palette.contains($0) })
        XCTAssertEqual(match.background.r,match.background.g);XCTAssertEqual(match.background.g,match.background.b)
    }

    func testDistinctColorPaletteIsPreservedWhenAContrastingBackgroundExists() throws {
        var settings=Settings()
        settings.palette=[.black,.white,RGB(1,0,0),RGB(0,1,0),RGB(0,0,1),RGB(1,1,0),RGB(0,1,1),RGB(1,0,1)]
        let image=PixelImage(width:8,height:1,pixels:settings.palette)
        let match=try BackgroundExtractor.matching(image,settings:settings)
        assertVisible(match);XCTAssertEqual(match.palette,settings.palette)
    }

    func testGrayBackgroundSearchStillReachesPureBlackAndWhite() throws {
        for (strand,target) in [(RGB.white,RGB.black),(RGB.black,RGB.white)] {
            var settings=Settings();settings.grayscale=true;settings.palette=[strand]
            let match=try BackgroundExtractor.matching(PixelImage(width:1,height:1,pixels:[target]),settings:settings)
            assertVisible(match);XCTAssertEqual(match.background,target)
        }
    }

    func testManyUniqueColorsUsePopulationWeightsAndKeepTheBaselineCandidate() throws {
        var pixels=(0..<200).map { i -> RGB in
            let value=Double(i)/199;return RGB(value,0.2+0.4*value,0.9-0.6*value)
        }
        let dominant=RGB(0.2,0.6,0.7)
        pixels+=Array(repeating:dominant,count:2000)
        let image=PixelImage(width:pixels.count,height:1,pixels:pixels)
        var settings=Settings();settings.palette=[dominant,RGB(0.7,0.2,0.4)];settings.background = .black
        let previous=error(image,settings:settings),original=settings
        let match=try BackgroundExtractor.matching(image,settings:settings)
        assertVisible(match);settings.background=match.background;settings.palette=match.palette
        XCTAssertLessThan(error(image,settings:settings),previous)
        XCTAssertEqual(match.background,try BackgroundExtractor.matching(image,settings:original).background)
    }
}
