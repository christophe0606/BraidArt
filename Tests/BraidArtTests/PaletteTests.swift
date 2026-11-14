import XCTest
import SwiftUI
import BraidCore
@testable import BraidArt

final class PaletteTests: XCTestCase {
    @MainActor func testAccentExtractionUsesSampledProjectWhenOriginalIsUnavailable() async throws {
        let model=AppModel()
        XCTAssertTrue(model.paletteIncludeAccents)
        XCTAssertEqual(model.paletteCount,6)
        let skin=RGB(0.76,0.60,0.53),blue=RGB(0.36,0.48,0.54),white=RGB(0.88,0.89,0.90)
        let pixels=Array(repeating:skin,count:100)+Array(repeating:blue,count:2)+Array(repeating:white,count:2)
        let image=PixelImage(width:104,height:1,pixels:pixels)
        model.prepared=image
        model.extractPalette()
        let deadline=ContinuousClock.now.advanced(by:.seconds(5))
        while model.busy,ContinuousClock.now<deadline { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.settings.palette,PaletteExtractor.distinctColors(in:image,count:6))
        XCTAssertEqual(model.settings.palette.count,3)
    }

    @MainActor func testExtractionUsesSelectedColorSeparation() async throws {
        let model=AppModel()
        XCTAssertEqual(model.paletteSeparation,.medium)
        model.paletteCount=4
        model.paletteIncludeAccents=false
        let dark=RGB(0.45,0.45,0.45),light=RGB(0.55,0.55,0.55)
        model.prepared=PixelImage(width:4,height:1,pixels:[dark,light,dark,light])
        for separation in PaletteSeparation.allCases {
            model.paletteSeparation=separation
            model.extractPalette()
            let deadline=ContinuousClock.now.advanced(by:.seconds(5))
            while model.busy,ContinuousClock.now<deadline { try await Task.sleep(for:.milliseconds(10)) }
            XCTAssertFalse(model.busy)
            let expected=separation == .keepShades || separation == .low ? 2 : 1
            XCTAssertEqual(model.settings.palette.count,expected)
            XCTAssertTrue(model.status.contains("Extracted \(expected) of up to 4 colors"))
        }
    }

    @MainActor func testRetainedPickerAfterPaletteShrinksAndRegrows() async {
        let model=AppModel()
        model.replacePalette([.black,.white,RGB(1,0,0),RGB(0,1,0),RGB(0,0,1)])
        let removed=model.paletteEntries[4]
        let binding=model.paletteColorBinding(for:removed)
        model.replacePalette([.black,.white])
        XCTAssertEqual(RGB(color:binding.wrappedValue),removed.color)
        binding.wrappedValue = .orange
        model.removePaletteColor(removed)
        XCTAssertEqual(model.settings.palette,[.black,.white])
        model.settings.palette.append(contentsOf:[RGB(1,0,0),RGB(0,1,0),RGB(0,0,1)])
        let regrown=model.settings.palette
        binding.wrappedValue = .purple
        model.removePaletteColor(removed)
        XCTAssertEqual(model.settings.palette,regrown)
    }

    @MainActor func testRetainedControlsCannotEditShiftedOrReplacedColors() async {
        let model=AppModel()
        model.replacePalette([.black,.white,RGB(1,0,0)])
        let entries=model.paletteEntries
        let binding=model.paletteColorBinding(for:entries[1])
        model.removePaletteColor(entries[0])
        XCTAssertEqual(model.settings.palette,[.white,RGB(1,0,0)])
        binding.wrappedValue = .green
        model.removePaletteColor(entries[1])
        XCTAssertEqual(model.settings.palette,[.white,RGB(1,0,0)])
        let sameSizeBinding=model.paletteColorBinding(for:model.paletteEntries[0])
        model.replacePalette([.black,.white])
        sameSizeBinding.wrappedValue = .blue
        XCTAssertEqual(model.settings.palette,[.black,.white])
    }

    @MainActor func testCurrentPickerRemainsEditableAndLastColorCannotBeRemoved() async {
        let model=AppModel()
        let entry=model.paletteEntries[0]
        let binding=model.paletteColorBinding(for:entry)
        binding.wrappedValue = .red
        binding.wrappedValue = .green
        XCTAssertEqual(model.settings.palette[0],RGB(color:.green))
        let readback=RGB(color:binding.wrappedValue),expected=RGB(color:.green)
        XCTAssertEqual(readback.r,expected.r,accuracy:1e-6)
        XCTAssertEqual(readback.g,expected.g,accuracy:1e-6)
        XCTAssertEqual(readback.b,expected.b,accuracy:1e-6)
        XCTAssertEqual(model.paletteEntries[0].id,entry.id)
        model.replacePalette([.black])
        model.removePaletteColor(model.paletteEntries[0])
        XCTAssertEqual(model.settings.palette,[.black])
    }

    @MainActor func testTileLibraryKeepsMetadataWithRenderedImagesAcrossPaletteChanges() async {
        let model=AppModel()
        model.replacePalette([.black,.white,RGB(1,0,0)])
        model.refreshTiles()
        let retained=model.tilePreviews
        XCTAssertEqual(retained.map(\.tile),model.tileData.allTiles)
        XCTAssertEqual(retained.count,36)
        model.replacePalette([.black])
        // SwiftUI may still display the old previews before settingsChanged refreshes them.
        XCTAssertEqual(model.tilePreviews.map(\.tile),retained.map(\.tile))
        XCTAssertEqual(retained.last?.tile.id,36)
        XCTAssertEqual(retained.last?.tile.kind,.circRight)
        model.refreshTiles()
        XCTAssertEqual(model.tilePreviews.map(\.tile),model.tileData.allTiles)
        XCTAssertEqual(model.tilePreviews.count,4)
    }
}
