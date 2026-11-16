import Foundation

public struct VideoSegment:Equatable,Sendable {
    public let start:Double
    public let end:Double
    public var duration:Double { end-start }
    public init(start:Double,end:Double) throws {
        guard start.isFinite,end.isFinite,start>=0,end>start else {
            throw BraidError.invalid(L("Choose a non-empty video segment within the source video."))
        }
        self.start=start;self.end=end
    }
    public func validate(sourceDuration:Double) throws {
        guard end<=sourceDuration+0.000001 else { throw BraidError.invalid(L("Choose a non-empty video segment within the source video.")) }
    }
}
