import XCTest
@testable import BraidCore

final class CropTests: XCTestCase {
    private func assertValid(_ crop:Crop,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertTrue(crop.valid,"Out-of-bounds crop: \(crop)",file:file,line:line)
    }
    private func assertRatio(_ crop:Crop,_ ratio:Double,file:StaticString=#filePath,line:UInt=#line) {
        assertValid(crop,file:file,line:line)
        XCTAssertEqual(crop.width/crop.height,ratio,accuracy:1e-10,file:file,line:line)
    }

    func testMovingPreservesDimensionsAndStopsAtEveryBoundary() {
        let crop=Crop(x:0.2,y:0.3,width:0.4,height:0.2)
        for dx in [-2.0,-0.1,0,0.1,2] {
            for dy in [-2.0,-0.1,0,0.1,2] {
                let moved=CropGeometry.moved(crop,by:CGSize(width:dx,height:dy))
                assertValid(moved)
                XCTAssertEqual(moved.width,crop.width);XCTAssertEqual(moved.height,crop.height)
            }
        }
        let moved=CropGeometry.moved(crop,by:CGSize(width:0.1,height:-0.1))
        XCTAssertEqual(moved.x,0.3,accuracy:1e-12);XCTAssertEqual(moved.y,0.2,accuracy:1e-12)
    }

    func testAllExportPresetsHaveTheCorrectPhysicalRatioOnDifferentSources() {
        for imageSize in [CGSize(width:1600,height:900),CGSize(width:600,height:1600),CGSize(width:512,height:512)] {
            XCTAssertNil(CropGeometry.normalizedAspectRatio(for:nil,imageSize:imageSize))
            for preset in PictureExportSize.allCases where preset != .viewport {
                let ratio=CropGeometry.normalizedAspectRatio(for:preset,imageSize:imageSize)!
                let fitted=CropGeometry.fitted(Crop(),aspectRatio:ratio)
                let exported=preset.pixelSize(viewport:imageSize)
                assertRatio(fitted,ratio)
                XCTAssertEqual((fitted.width*imageSize.width)/(fitted.height*imageSize.height),
                               exported.width/exported.height,accuracy:1e-10)
            }
        }
    }

    func testDrawingInEveryDirectionRespectsTheRatioAndImageBounds() throws {
        let start=CGPoint(x:0.4,y:0.6)
        for ratio:Double? in [nil,1,16.0/9,4.0/5,9.0/16] {
            for end in [CGPoint(x:-1,y:-1),CGPoint(x:2,y:-1),CGPoint(x:-1,y:2),CGPoint(x:2,y:2)] {
                let crop=try XCTUnwrap(CropGeometry.drawn(from:start,to:end,aspectRatio:ratio))
                assertValid(crop)
                if let ratio { assertRatio(crop,ratio) }
                XCTAssertTrue(abs(crop.x-start.x)<1e-12 || abs(crop.x+crop.width-start.x)<1e-12)
                XCTAssertTrue(abs(crop.y-start.y)<1e-12 || abs(crop.y+crop.height-start.y)<1e-12)
            }
        }
        XCTAssertNil(CropGeometry.drawn(from:start,to:CGPoint(x:0.401,y:0.601),aspectRatio:nil))
    }

    func testEveryResizeHandlePreservesLockedRatiosEvenPastImageBounds() {
        for imageSize in [CGSize(width:1600,height:900),CGSize(width:600,height:1600)] {
            for preset in PictureExportSize.allCases where preset != .viewport {
                let ratio=CropGeometry.normalizedAspectRatio(for:preset,imageSize:imageSize)!
                let original=CropGeometry.scaled(CropGeometry.fitted(Crop(),aspectRatio:ratio),by:0.6)
                for handle in CropHandle.allCases {
                    for dx in [-2.0,-0.05,0,0.05,2] {
                        for dy in [-2.0,-0.05,0,0.05,2] {
                            let resized=CropGeometry.resized(original,handle:handle,by:CGSize(width:dx,height:dy),aspectRatio:ratio)
                            assertRatio(resized,ratio)
                            let p=handle.position
                            if p.x==0 { XCTAssertEqual(resized.x+resized.width,original.x+original.width,accuracy:1e-10) }
                            if p.x==1 { XCTAssertEqual(resized.x,original.x,accuracy:1e-10) }
                            if p.y==0 { XCTAssertEqual(resized.y+resized.height,original.y+original.height,accuracy:1e-10) }
                            if p.y==1 { XCTAssertEqual(resized.y,original.y,accuracy:1e-10) }
                        }
                    }
                }
            }
        }
    }

    func testFreeResizeMovesOnlyTheSelectedEdgesAndCannotInvert() {
        let crop=Crop(x:0.2,y:0.3,width:0.4,height:0.2)
        for handle in CropHandle.allCases {
            for delta in [-2.0,-0.05,0.05,2] {
                let resized=CropGeometry.resized(crop,handle:handle,by:CGSize(width:delta,height:delta),aspectRatio:nil)
                assertValid(resized)
                let p=handle.position
                if p.x != 0 { XCTAssertEqual(resized.x,crop.x,accuracy:1e-12) }
                if p.x != 1 { XCTAssertEqual(resized.x+resized.width,crop.x+crop.width,accuracy:1e-12) }
                if p.y != 0 { XCTAssertEqual(resized.y,crop.y,accuracy:1e-12) }
                if p.y != 1 { XCTAssertEqual(resized.y+resized.height,crop.y+crop.height,accuracy:1e-12) }
            }
        }
    }

    func testEditingNearImageCornersAndOnPanoramasKeepsCropsValid() throws {
        for imageSize in [CGSize(width:6000,height:200),CGSize(width:200,height:6000),CGSize(width:1200,height:800)] {
            for preset in PictureExportSize.allCases where preset != .viewport {
                let ratio=try XCTUnwrap(CropGeometry.normalizedAspectRatio(for:preset,imageSize:imageSize))
                let fitted=CropGeometry.fitted(Crop(),aspectRatio:ratio)
                let drawn=try XCTUnwrap(CropGeometry.drawn(from:.zero,to:CGPoint(x:1,y:1),aspectRatio:ratio))
                assertRatio(drawn,ratio)
                for delta in [CGSize(width:-2,height:-2),CGSize(width:2,height:-2),CGSize(width:2,height:2),CGSize(width:-2,height:2)] {
                    let atCorner=CropGeometry.moved(CropGeometry.scaled(fitted,by:0.7),by:delta)
                    for handle in CropHandle.allCases {
                        for translation in [CGSize(width:0.1,height:0.13),CGSize(width:-0.1,height:-0.13),delta] {
                            assertRatio(CropGeometry.resized(atCorner,handle:handle,by:translation,aspectRatio:ratio),ratio)
                        }
                    }
                    for factor in [0.1,0.9,1.1,10] { assertRatio(CropGeometry.scaled(atCorner,by:factor),ratio) }
                }
            }
        }
    }

    func testScalingKeepsTheCenterAndProportionsAtBothLimits() {
        for crop in [Crop(x:0.2,y:0.3,width:0.4,height:0.2),Crop(x:0,y:0,width:0.3,height:0.7)] {
            for factor in [0.0001,0.5,1,1.1,10,Double.infinity,-1] {
                let scaled=CropGeometry.scaled(crop,by:factor)
                assertRatio(scaled,crop.width/crop.height)
                XCTAssertEqual(scaled.x+scaled.width/2,crop.x+crop.width/2,accuracy:1e-12)
                XCTAssertEqual(scaled.y+scaled.height/2,crop.y+crop.height/2,accuracy:1e-12)
            }
        }
    }

    func testAspectRatioMetadataRoundTripsAndOlderSettingsStillDecode() throws {
        var settings=Settings();settings.cropAspectRatio = .instagramPortrait
        let data=try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self,from:data),settings)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        json.removeValue(forKey:"cropAspectRatio")
        let legacy=try JSONDecoder().decode(Settings.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(legacy.cropAspectRatio)
        XCTAssertTrue(settings.hasSameImagePreparation(as:legacy),"The menu choice alone does not change the sampled pixels")
    }
}
