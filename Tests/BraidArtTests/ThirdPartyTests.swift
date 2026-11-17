import XCTest
@testable import BraidArt

final class ThirdPartyTests:XCTestCase {
    func testEveryBundledProjectRetainsLicensesAuthorsAndSourceReference() throws {
        for project in ThirdPartyDependency.projects {
            XCTAssertEqual(project.source.host,"github.com")
            XCTAssertTrue(project.source.path.hasPrefix("/coin-or/"))
            for filename in ["LICENSE","LIBRARY-LICENSE","AUTHORS","ORIGIN.md"] {
                let document=project.document(filename,title:filename)
                let url=try XCTUnwrap(document.localURL,"Missing \(project.name)/\(filename)")
                XCTAssertGreaterThan(try Data(contentsOf:url).count,0)
                XCTAssertEqual(document.origin?.scheme,"https")
            }
        }
        for document in [ThirdPartyNotice.bison,.ampl,.rational,.ciede] {
            let url=try XCTUnwrap(document.localURL)
            XCTAssertGreaterThan(try Data(contentsOf:url).count,0)
            XCTAssertNotNil(document.origin)
        }
    }
    func testInventoryKeepsImageRightsAndDoesNotAdvertiseAnApplicationLicense() throws {
        let inventory=try XCTUnwrap(ThirdPartyNotice.inventory.localURL)
        let text=try String(contentsOf:inventory,encoding:.utf8)
        XCTAssertTrue(text.contains("public domain"))
        XCTAssertTrue(text.contains("https://flic.kr/p/r9qvLn"))
        XCTAssertTrue(text.contains("https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut"))
        XCTAssertFalse(text.contains("Apache"))
        #if os(iOS)
        let root=Bundle.main.bundleURL
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("LICENSE").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Solver/LICENSE").path))
        #endif
    }
}
