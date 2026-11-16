import XCTest
import CoreGraphics
@testable import BraidCore

final class OutputImageTests:XCTestCase {
    func testEveryOutputPresetProducesItsExactDimensionsWithFractionalTiles() throws {
        let data=TileData(settings:Settings())
        let solution=Array(repeating:Array(repeating:9,count:37),count:23)
        for preset in PictureExportSize.outputSizes {
            let size=preset.pixelSize(viewport:.zero)
            let image=try TileRenderer.render(solution:solution,data:data,pixelSize:size)
            XCTAssertEqual(image.width,Int(size.width));XCTAssertEqual(image.height,Int(size.height))
        }
    }

    func testExactSizeRenderingMatchesExistingTilesAtIntegralTileSizes() throws {
        let data=TileData(settings:Settings())
        for id in data.allTiles.map(\.id) {
            let solution=[[id,id],[id,id]]
            let reference=try TileRenderer.render(solution:solution,data:data,tileSize:20)
            let image=try TileRenderer.render(solution:solution,data:data,pixelSize:CGSize(width:40,height:40))
            XCTAssertEqual(image.dataProvider?.data as Data?,reference.dataProvider?.data as Data?,"Tile \(id)")
        }
    }

    func testExactSizeRenderingRejectsBadDimensionsAndTileIDs() {
        let data=TileData(settings:Settings())
        for size in [CGSize.zero,CGSize(width:10.5,height:10),CGSize(width:10000,height:10000),CGSize(width:Double.infinity,height:10)] {
            XCTAssertThrowsError(try TileRenderer.render(solution:[[1]],data:data,pixelSize:size))
        }
        for solution:[[Int]] in [[],[[]],[[0]],[[999]],[[1],[1,2]]] {
            XCTAssertThrowsError(try TileRenderer.render(solution:solution,data:data,pixelSize:CGSize(width:20,height:20)))
        }
    }
}
