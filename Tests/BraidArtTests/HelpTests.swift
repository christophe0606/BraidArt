import XCTest
@testable import BraidArt

final class HelpTests:XCTestCase {
    func testHelpSearchFindsRelevantSectionsAndClearsEmptyQueries() {
        XCTAssertTrue(HelpTopic.matching("EILEEN COLLINS").contains(.picture))
        XCTAssertTrue(HelpTopic.matching("crop").contains(.crop))
        XCTAssertTrue(HelpTopic.matching("  export  ").contains(.sharing))
        XCTAssertTrue(HelpTopic.matching("3D").contains(.sculpture))
        XCTAssertTrue(HelpTopic.matching("  ").isEmpty)
        XCTAssertTrue(HelpTopic.matching("missing-topic-123").isEmpty)
    }
    func testAllHelpIllustrationsAreBundledAndReadable() throws {
        for illustration in HelpIllustration.allCases {
            let url=try XCTUnwrap(illustration.url,"Missing help image: \(illustration.rawValue)")
            XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
            let image=try XCTUnwrap(illustration.image)
            XCTAssertGreaterThan(image.size.width,0);XCTAssertGreaterThan(image.size.height,0)
        }
    }
}
