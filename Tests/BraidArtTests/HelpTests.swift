import XCTest
import BraidCore
@testable import BraidArt

final class HelpTests:XCTestCase {
    @MainActor func testFirstLaunchHelpPersistsAndCanBeResetIndependently() throws {
        let suite="BraidArt.FirstLaunchHelpTests.\(UUID().uuidString)"
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("Keep",forKey:"otherPreference")
        var presentations=0
        FirstLaunchHelp.showIfNeeded(defaults:defaults) { presentations+=1 }
        XCTAssertEqual(presentations,1)

        let reopened=try XCTUnwrap(UserDefaults(suiteName:suite))
        FirstLaunchHelp.showIfNeeded(defaults:reopened) { presentations+=1 }
        XCTAssertEqual(presentations,1,"Later launches must not reopen help")

        reopened.removeObject(forKey:FirstLaunchHelp.preferenceKey)
        FirstLaunchHelp.showIfNeeded(defaults:reopened) { presentations+=1 }
        XCTAssertEqual(presentations,2,"Resetting the preference must restore first-launch help")
        XCTAssertEqual(reopened.string(forKey:"otherPreference"),"Keep")
    }

    func testHelpSearchFindsRelevantSectionsAndClearsEmptyQueries() {
        XCTAssertTrue(HelpTopic.matching("EILEEN COLLINS").contains(.picture))
        XCTAssertTrue(HelpTopic.matching(HelpTopic.crop.title.uppercased()).contains(.crop))
        XCTAssertTrue(HelpTopic.matching("  \(L("Export"))  ").contains(.sharing))
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
