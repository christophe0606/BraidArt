import SwiftUI
import BraidCore

#if os(macOS)
typealias BraidViewRepresentable = NSViewRepresentable
#else
typealias BraidViewRepresentable = UIViewRepresentable
#endif

struct Braid3DView: BraidViewRepresentable {
    let braid:BraidCurves
    let meshes:[TubeMesh]
    let generation:Int
    let settings:SceneSettings
    let reset:Int
    let camera:CameraState?
    let onCameraChanged:(CameraState)->Void
    let onViewReady:(BraidMetalView)->Void
    class Coordinator { var generation = -1;var reset = -1;var settings:SceneSettings? }
    func makeCoordinator()->Coordinator { Coordinator() }
    #if os(iOS)
    func makeUIView(context:Context)->BraidMetalView { makeView() }
    func updateUIView(_ view:BraidMetalView,context:Context) { updateView(view,context:context) }
    #else
    func makeNSView(context:Context)->BraidMetalView { makeView() }
    func updateNSView(_ view:BraidMetalView,context:Context) { updateView(view,context:context) }
    #endif
    private func makeView()->BraidMetalView {
        let view=BraidMetalView()
        onViewReady(view)
        return view
    }
    private func updateView(_ view:BraidMetalView,context:Context) {
        let c=context.coordinator
        // Scene setup and restoration must not publish the intermediate fitted camera.
        view.onCameraChanged=nil
        if c.generation != generation {
            view.display(braid,meshes:meshes,settings:settings);c.generation=generation;c.settings=settings
            if let camera { try? view.restoreCamera(camera) }
            c.reset=reset
        }
        if c.settings != settings { view.updatePlane(braid,settings:settings);c.settings=settings }
        if c.reset != reset { view.fit(columns:braid.columns,rows:braid.rows);c.reset=reset }
        view.onCameraChanged=onCameraChanged
        onCameraChanged(view.cameraState)
    }
}
