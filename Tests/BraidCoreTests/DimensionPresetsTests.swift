import XCTest
@testable import BraidCore

final class DimensionPresetsTests:XCTestCase {
    func testBuiltInsKeepTheirLegacyEncodingAndCannotBeCustom() throws {
        let legacy:[String:PictureExportSize]=["viewport":.viewport,"hd":.hd,"fullHD":.fullHD,"ultraHD":.ultraHD,
            "instagramSquare":.instagramSquare,"instagramPortrait":.instagramPortrait,"instagramTallPortrait":.instagramTallPortrait,
            "instagramLandscape":.instagramLandscape,"instagramStory":.instagramStory]
        for (raw,preset) in legacy {
            let encoded=try JSONEncoder().encode(preset)
            XCTAssertEqual(try JSONDecoder().decode(String.self,from:encoded),raw)
            XCTAssertEqual(try JSONDecoder().decode(PictureExportSize.self,from:Data("\"\(raw)\"".utf8)),preset)
        }
        XCTAssertTrue(PictureExportSize.allCases.allSatisfy{$0.customSize == nil})
        XCTAssertEqual(Set(PictureExportSize.allCases.map(\.id)).count,PictureExportSize.allCases.count)
    }

    func testCustomSizeRoundTripsInBothProjectExportSettings() throws {
        let custom=try CustomPictureSize(name:"  Poster  ",width:257,height:401)
        let preset=PictureExportSize.custom(custom)
        XCTAssertEqual(custom.name,"Poster")
        var settings=Settings();settings.columns=8;settings.outputSize=preset
        let data=TileData(settings:settings)
        let result=SolveResult(solution:[[1,1],[1,1]],reports:[],costBackend:"Test",elapsedSeconds:0)
        var project=BraidProject(sourceName:"Test",settings:settings,sampledImage:PixelImage(width:2,height:2,pixels:Array(repeating:.gray,count:4)),tileData:data,result:result)
        project.pictureExportSize=preset
        let decoded=try JSONDecoder().decode(BraidProject.self,from:JSONEncoder().encode(project))
        try decoded.validate()
        XCTAssertEqual(decoded.settings.outputSize,preset)
        XCTAssertEqual(decoded.pictureExportSize,preset)
        XCTAssertEqual(decoded.settings.outputPixelSize,CGSize(width:257,height:401))
        XCTAssertEqual(decoded.settings.outputSize.customSize?.id,custom.id)
        let image=try TileRenderer.render(solution:result.solution,data:data,pixelSize:decoded.settings.outputPixelSize)
        XCTAssertEqual(image.width,257);XCTAssertEqual(image.height,401)
    }

    func testRejectsInvalidCustomDimensionsIncludingEncodedData() throws {
        for name in ["","  \n ",String(repeating:"a",count:81)] {
            XCTAssertThrowsError(try CustomPictureSize(name:name,width:100,height:100))
        }
        for (w,h) in [(0,100),(100,-1),(8193,100),(100,8193)] {
            XCTAssertThrowsError(try CustomPictureSize(name:"Invalid",width:w,height:h))
        }
        let valid=try PictureExportSize.custom(CustomPictureSize(name:"Valid",width:100,height:100))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(valid)) as? [String:Any])
        for (key,value) in [("width",0),("height",8193)] {
            var invalid=json;invalid[key]=value
            XCTAssertThrowsError(try JSONDecoder().decode(PictureExportSize.self,from:JSONSerialization.data(withJSONObject:invalid)))
        }
        json["name"]=""
        XCTAssertThrowsError(try JSONDecoder().decode(PictureExportSize.self,from:JSONSerialization.data(withJSONObject:json)))
    }
}
