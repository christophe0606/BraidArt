import Foundation

#if !SWIFT_PACKAGE
private final class BraidResourceMarker {}
extension Bundle {
    static var module:Bundle { Bundle(for:BraidResourceMarker.self) }
}
#endif
