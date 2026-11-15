import SwiftUI
import BraidCore

struct Braid3DView: NSViewRepresentable {
    let braid:BraidCurves
    let meshes:[TubeMesh]
    let generation:Int
    let settings:SceneSettings
    let reset:Int
    let oblique:Bool
    let camera:CameraState?
    let onCameraChanged:(CameraState)->Void
    let onViewReady:(BraidMetalView)->Void
    class Coordinator { var generation = -1;var reset = -1;var settings:SceneSettings? }
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeNSView(context:Context)->BraidMetalView {
        let view=BraidMetalView()
        onViewReady(view)
        return view
    }
    func updateNSView(_ view:BraidMetalView,context:Context) {
        let c=context.coordinator
        // Scene setup and restoration must not publish the intermediate fitted camera.
        view.onCameraChanged=nil
        if c.generation != generation {
            view.display(braid,meshes:meshes,settings:settings);c.generation=generation;c.settings=settings
            if let camera { try? view.restoreCamera(camera) }
            else { view.fit(columns:braid.columns,rows:braid.rows,oblique:oblique) }
            c.reset=reset
        }
        if c.settings != settings { view.updatePlane(braid,settings:settings);c.settings=settings }
        if c.reset != reset { view.fit(columns:braid.columns,rows:braid.rows,oblique:oblique);c.reset=reset }
        view.onCameraChanged=onCameraChanged
        onCameraChanged(view.cameraState)
    }
}
