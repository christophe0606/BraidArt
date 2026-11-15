import Foundation

/// Orbit controls and their pan target, sufficient to restore the camera and continue editing it.
public struct CameraState: Codable, Equatable, Sendable {
    public var target: CurvePoint
    public var orbitYaw: Float
    public var orbitPitch: Float
    public var cameraDistance: Float
    public var fitDistance: Float
    public var fieldOfView: Double

    public init(target:CurvePoint,orbitYaw:Float,orbitPitch:Float,cameraDistance:Float,fitDistance:Float,fieldOfView:Double = 38) {
        self.target=target;self.orbitYaw=orbitYaw;self.orbitPitch=orbitPitch
        self.cameraDistance=cameraDistance;self.fitDistance=fitDistance;self.fieldOfView=fieldOfView
    }
    public func validate() throws {
        guard [target.x,target.y,target.z,Double(orbitYaw),Double(orbitPitch),Double(cameraDistance),Double(fitDistance),fieldOfView].allSatisfy(\.isFinite),
              (-1.45...1.45).contains(orbitPitch),cameraDistance>=0.5,fitDistance>0,(1...179).contains(fieldOfView) else {
            throw BraidError.invalid("Invalid saved 3D camera.")
        }
    }
}
