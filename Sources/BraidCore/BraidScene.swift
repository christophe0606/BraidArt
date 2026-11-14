import AppKit
import SceneKit
import Metal

public enum BraidScene {
    public static func geometry(_ mesh:TubeMesh) -> SCNGeometry {
        // SIMD3 has 16-byte stride; SCNVector3 packs three Float components.
        let vertices=mesh.positions.map{SCNVector3($0.x,$0.y,$0.z)}
        let normals=mesh.normals.map{SCNVector3($0.x,$0.y,$0.z)}
        let element=SCNGeometryElement(indices:mesh.indices,primitiveType:.triangles)
        let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[element])
        let material=SCNMaterial();material.lightingModel = .physicallyBased
        material.diffuse.contents=NSColor(srgbRed:mesh.color.r,green:mesh.color.g,blue:mesh.color.b,alpha:1)
        material.metalness.contents=0.0;material.roughness.contents=mesh.name=="Backing plane" ? 0.65 : 0.23
        material.isDoubleSided=true;geometry.materials=[material]
        return geometry
    }
    public static func make(_ braid:BraidCurves, meshes:[TubeMesh], settings:SceneSettings) -> SCNScene {
        let scene=SCNScene();scene.background.contents=NSColor(calibratedWhite:0.10,alpha:1)
        for mesh in meshes {
            let node=SCNNode(geometry:geometry(mesh));node.name=mesh.name;scene.rootNode.addChildNode(node)
        }
        let plane=SCNNode(geometry:geometry(TubeMesher.plane(braid,settings:settings)));plane.name="Backing plane";scene.rootNode.addChildNode(plane)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=450;ambient.light!.color=NSColor.white;scene.rootNode.addChildNode(ambient)
        let key=SCNNode();key.light=SCNLight();key.light!.type = .directional;key.light!.intensity=1600
        key.eulerAngles=SCNVector3(-0.45,-0.4,0);key.light!.castsShadow=true
        key.light!.shadowMode = .deferred;key.light!.shadowRadius=3;key.light!.shadowSampleCount=16
        key.light!.shadowMapSize=CGSize(width:2048,height:2048)
        key.light!.orthographicScale=CGFloat(max(braid.columns,braid.rows))*0.8
        key.light!.zNear=0.01;key.light!.zFar=CGFloat(max(braid.columns,braid.rows))*5+10
        key.position=SCNVector3(Float(braid.columns)/2,-Float(braid.rows)/2,Float(max(braid.columns,braid.rows))+5)
        scene.rootNode.addChildNode(key)
        let fill=SCNNode();fill.light=SCNLight();fill.light!.type = .directional;fill.light!.intensity=500;fill.eulerAngles=SCNVector3(0.6,0.7,0);scene.rootNode.addChildNode(fill)
        return scene
    }
}

/// SceneKit rasterizes real tube meshes with Metal. Camera controls are explicit and deterministic.
public final class BraidMetalView: SCNView {
    public private(set) var cameraNode=SCNNode()
    public private(set) var target=SCNVector3Zero
    public private(set) var orbitYaw:Float=0
    public private(set) var orbitPitch:Float=0
    public private(set) var cameraDistance:Float=10
    private var fitDistance:Float=10
    private var lastPoint=NSPoint.zero
    private var panGesture=false
    public override var acceptsFirstResponder:Bool { true }
    public override init(frame:CGRect = .zero) {
        super.init(frame:frame,options:[SCNView.Option.preferredRenderingAPI.rawValue:SCNRenderingAPI.metal.rawValue])
        antialiasingMode = .multisampling4X
        autoenablesDefaultLighting=false;allowsCameraControl=false
        cameraNode.camera=SCNCamera();cameraNode.camera!.fieldOfView=38
        cameraNode.camera!.projectionDirection = .vertical
        cameraNode.camera!.wantsHDR=true;cameraNode.camera!.wantsExposureAdaptation=false
        cameraNode.camera!.exposureOffset = -0.35
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    public func display(_ braid:BraidCurves, meshes:[TubeMesh], settings:SceneSettings) {
        scene=BraidScene.make(braid,meshes:meshes,settings:settings)
        scene!.rootNode.addChildNode(cameraNode);pointOfView=cameraNode
        target=SCNVector3(Float(braid.columns)/2+0.5,-Float(braid.rows)/2-0.5,0)
        cameraNode.camera!.zNear=0.01;cameraNode.camera!.zFar=Double(max(braid.columns,braid.rows))*30+100
        fit(columns:braid.columns,rows:braid.rows)
    }
    public func updatePlane(_ braid:BraidCurves, settings:SceneSettings) {
        scene?.rootNode.childNode(withName:"Backing plane",recursively:false)?.geometry=BraidScene.geometry(TubeMesher.plane(braid,settings:settings))
        needsDisplay=true
    }
    /// Capture the live viewport, preserving its camera, lighting, background and pixel scale.
    public func captureImage() throws -> CGImage {
        guard scene != nil, pointOfView != nil, bounds.width>0, bounds.height>0 else {
            throw BraidError.invalid("Open a 3D rendering before exporting its picture.")
        }
        SCNTransaction.flush()
        let image=snapshot()
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
            throw BraidError.invalid("Cannot capture the current 3D rendering.")
        }
        return cg
    }
    public var viewportPixelSize:CGSize {
        let size=convertToBacking(bounds).size
        return CGSize(width:size.width.rounded(),height:size.height.rounded())
    }

    /// Freeze an independent scene and camera for a background render at the requested pixel size.
    public func makePictureCapture(size:CGSize) throws -> BraidPictureCapture {
        guard let scene,let pointOfView,let sourceCamera=pointOfView.camera,bounds.width>0,bounds.height>0 else {
            throw BraidError.invalid("Open a 3D rendering before exporting its picture.")
        }
        guard size.width.isFinite,size.height.isFinite,(1...8192).contains(size.width),(1...8192).contains(size.height),
              size.width.rounded()==size.width,size.height.rounded()==size.height else {
            throw BraidError.invalid("Picture dimensions must be whole pixels between 1 and 8192.")
        }
        SCNTransaction.flush()
        let frozen=SCNScene()
        frozen.background.contents=scene.background.contents
        frozen.lightingEnvironment.contents=scene.lightingEnvironment.contents
        frozen.lightingEnvironment.intensity=scene.lightingEnvironment.intensity
        // Cloned nodes retain immutable mesh geometry; later viewport changes replace nodes/geometry.
        for child in scene.rootNode.childNodes where child !== pointOfView { frozen.rootNode.addChildNode(child.clone()) }
        let camera=SCNNode();camera.camera=sourceCamera.copy() as? SCNCamera
        camera.transform=pointOfView.presentation.worldTransform
        // Expand the field of view for narrower output, keeping the entire current framing.
        let expansion=max(1,(bounds.width/bounds.height)/(size.width/size.height))
        camera.camera!.fieldOfView=2*atan(tan(sourceCamera.fieldOfView*CGFloat.pi/360)*expansion)*180/CGFloat.pi
        frozen.rootNode.addChildNode(camera)
        return BraidPictureCapture(scene:frozen,camera:camera,size:size)
    }
    public func fit(columns:Int,rows:Int,oblique:Bool=false) {
        let aspect=Float(max(1,bounds.width)/max(1,bounds.height))
        fitDistance=max(Float(rows),Float(columns)/aspect)*0.5/tan(38*Float.pi/360)*1.15+1
        cameraDistance=fitDistance;orbitYaw=oblique ? -0.35 : 0;orbitPitch=oblique ? -0.35 : 0
        target=SCNVector3(Float(columns)/2+0.5,-Float(rows)/2-0.5,0);updateCamera()
    }
    public func orbit(dx:Float,dy:Float) { orbitYaw += dx;orbitPitch=min(1.45,max(-1.45,orbitPitch+dy));updateCamera() }
    public func zoom(factor:Float) { cameraDistance=min(fitDistance*15,max(0.5,cameraDistance*factor));updateCamera() }
    public func pan(dx:Float,dy:Float) {
        let scale=cameraDistance*0.001
        let transform=cameraNode.presentation.worldTransform
        target.x += (-CGFloat(dx)*transform.m11+CGFloat(dy)*transform.m21)*CGFloat(scale)
        target.y += (-CGFloat(dx)*transform.m12+CGFloat(dy)*transform.m22)*CGFloat(scale)
        target.z += (-CGFloat(dx)*transform.m13+CGFloat(dy)*transform.m23)*CGFloat(scale)
        updateCamera()
    }
    private func updateCamera() {
        cameraNode.position=SCNVector3(target.x+CGFloat(cameraDistance*sin(orbitYaw)*cos(orbitPitch)),target.y+CGFloat(cameraDistance*sin(orbitPitch)),target.z+CGFloat(cameraDistance*cos(orbitYaw)*cos(orbitPitch)))
        cameraNode.look(at:target);needsDisplay=true
    }
    public override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(self);lastPoint=event.locationInWindow;panGesture=event.modifierFlags.contains(.shift) }
    public override func rightMouseDown(with event:NSEvent) { lastPoint=event.locationInWindow;panGesture=true }
    public override func otherMouseDown(with event:NSEvent) { rightMouseDown(with:event) }
    public override func mouseDragged(with event:NSEvent) {
        let p=event.locationInWindow,dx=Float(p.x-lastPoint.x),dy=Float(p.y-lastPoint.y);lastPoint=p
        if panGesture { pan(dx:dx,dy:dy) } else { orbit(dx:-dx*0.008,dy:-dy*0.008) }
    }
    public override func rightMouseDragged(with event:NSEvent) { mouseDragged(with:event) }
    public override func otherMouseDragged(with event:NSEvent) { mouseDragged(with:event) }
    public override func scrollWheel(with event:NSEvent) { zoom(factor:exp(-min(80,max(-80,Float(event.scrollingDeltaY)))*0.01)) }
    public override func magnify(with event:NSEvent) { zoom(factor:exp(-Float(event.magnification))) }
}

/// Owns its frozen scene; rendering is serialized and never touches the live view.
public final class BraidPictureCapture: @unchecked Sendable {
    private let scene:SCNScene
    private let camera:SCNNode
    private let size:CGSize
    private let lock=NSLock()
    fileprivate init(scene:SCNScene,camera:SCNNode,size:CGSize) { self.scene=scene;self.camera=camera;self.size=size }
    public func render() throws -> CGImage {
        lock.lock();defer { lock.unlock() }
        try Task.checkCancellation()
        guard let device=MTLCreateSystemDefaultDevice() else { throw BraidError.invalid("Metal is unavailable for picture export.") }
        let renderer=SCNRenderer(device:device,options:nil)
        renderer.scene=scene;renderer.pointOfView=camera;renderer.autoenablesDefaultLighting=false
        let image=renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling4X)
        try Task.checkCancellation()
        guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),cg.width==Int(size.width),cg.height==Int(size.height) else {
            throw BraidError.invalid("Cannot render the selected picture size.")
        }
        return cg
    }
}
