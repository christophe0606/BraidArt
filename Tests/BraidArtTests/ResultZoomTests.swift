import AppKit
import XCTest
@testable import BraidArt

final class ResultZoomTests: XCTestCase {
    @MainActor func testMagnificationKeepsItsAnchorAndFitRecentersTheResult() throws {
        let view = MacResultScrollView()
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let image = NSImage(size: NSSize(width: 640, height: 480))
        view.update(image: image, zoom: 1)
        view.layoutSubtreeIfNeeded()

        let document = try XCTUnwrap(view.documentView)
        XCTAssertTrue(view.allowsMagnification)
        XCTAssertEqual(document.frame.height, 460, accuracy: 1)
        XCTAssertEqual(view.contentView.bounds.midX, document.frame.midX, accuracy: 1)
        XCTAssertEqual(view.contentView.bounds.midY, document.frame.midY, accuracy: 1)

        let anchor = CGPoint(x: document.frame.midX + 40, y: document.frame.midY + 15)
        let originalPoint = view.contentView.convert(anchor, to: view)
        view.setMagnification(2, centeredAt: anchor)
        view.update(image: image, zoom: 1)
        XCTAssertEqual(view.magnification, 2)
        let zoomedPoint = view.contentView.convert(anchor, to: view)
        XCTAssertEqual(zoomedPoint.x, originalPoint.x, accuracy: 1)
        XCTAssertEqual(zoomedPoint.y, originalPoint.y, accuracy: 1)

        var rememberedZoom: Double?
        view.onZoomChanged = { rememberedZoom = $0 }
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: view)
        XCTAssertEqual(rememberedZoom, 2)

        view.update(image: image, zoom: 1)
        XCTAssertEqual(view.magnification, 1)
        XCTAssertEqual(view.contentView.bounds.midX, document.frame.midX, accuracy: 1)
        XCTAssertEqual(view.contentView.bounds.midY, document.frame.midY, accuracy: 1)
    }
}
