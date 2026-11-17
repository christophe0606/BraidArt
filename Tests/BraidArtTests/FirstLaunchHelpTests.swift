import XCTest
@testable import BraidArt

final class FirstLaunchHelpTests:XCTestCase {
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

}
