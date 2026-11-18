import AppKit
import SwiftUI

/// AppKit handles trackpad magnification and keeps the pinch anchored to the picture.
struct MacZoomableResult: NSViewRepresentable {
    let image: NSImage
    @Binding var zoom: Double

    func makeNSView(context: Context) -> MacResultScrollView { MacResultScrollView() }

    func updateNSView(_ view: MacResultScrollView, context: Context) {
        let selection = $zoom
        view.onZoomChanged = { selection.wrappedValue = $0 }
        view.update(image: image, zoom: zoom)
    }
}

final class MacResultScrollView: NSScrollView {
    private let picture = NSImageView()
    private var appliedZoom: Double?
    var onZoomChanged: ((Double) -> Void)?

    init() {
        super.init(frame: .zero)
        contentView = CenteredResultClipView()
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        minMagnification = 0.25
        maxMagnification = 4
        picture.imageScaling = .scaleProportionallyUpOrDown
        documentView = picture
        NotificationCenter.default.addObserver(self, selector: #selector(magnificationEnded),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) { return nil }

    func update(image: NSImage, zoom: Double) {
        if picture.image !== image {
            picture.image = image
            needsLayout = true
        }
        // Updates unrelated to zoom can arrive in the middle of a pinch.
        guard appliedZoom != zoom else { return }
        appliedZoom = zoom
        if magnification != zoom { magnification = zoom }
    }

    override func layout() {
        super.layout()
        guard let image = picture.image, image.size.width > 0, image.size.height > 0 else { return }
        let viewport = contentView.frame.size
        let scale = min(max(1, viewport.width - 40) / image.size.width,
                        max(1, viewport.height - 40) / image.size.height)
        let fittedSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard picture.frame.size != fittedSize else { return }
        picture.setFrameSize(fittedSize)
        contentView.scroll(to: contentView.constrainBoundsRect(contentView.bounds).origin)
        reflectScrolledClipView(contentView)
    }

    @objc private func magnificationEnded() {
        let zoom = min(maxMagnification, max(minMagnification, magnification))
        appliedZoom = zoom
        onZoomChanged?(zoom)
    }
}

private final class CenteredResultClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return bounds }
        let document = documentView.frame
        if bounds.width > document.width { bounds.origin.x = document.midX - bounds.width / 2 }
        if bounds.height > document.height { bounds.origin.y = document.midY - bounds.height / 2 }
        return bounds
    }
}
