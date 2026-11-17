import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import BraidCore
import AVFoundation

struct CropEditor: View {
    let image: PlatformImage
    @Binding var crop: Crop
    @Binding var hasSelection: Bool
    let aspectRatio: Double?
    let onDelete: ()->Void
    var player:AVPlayer?=nil
    @State private var drag: CropDrag?
    @State private var scaleStart: Crop?
    @State private var draft: Crop?
    @FocusState private var focused: Bool

    private enum Operation {
        case draw(CGPoint), move(Crop), resize(Crop,CropHandle)
    }
    private struct CropDrag { let operation:Operation }

    var body: some View {
        GeometryReader { proxy in
            // Leave room for the handles even when the crop touches an image edge.
            let fitted=PictureExportSize.frame(for:image.size,in:CGRect(origin:.zero,size:proxy.size).insetBy(dx:10,dy:10))
            let selection=draft ?? (hasSelection ? crop : nil)
            ZStack(alignment:.topLeading) {
                Color.black.opacity(0.2)
                Image(platformImage:image).resizable().frame(width:fitted.width,height:fitted.height)
                    .offset(x:fitted.minX,y:fitted.minY)
                if let player {
                    VideoPreview(player:player).frame(width:fitted.width,height:fitted.height)
                        .offset(x:fitted.minX,y:fitted.minY).allowsHitTesting(false)
                }
                if let selection {
                    let rect=displayRect(selection,in:fitted)
                    Path { path in
                        path.addRect(fitted);path.addRect(rect)
                    }.fill(.black.opacity(0.45),style:FillStyle(eoFill:true))
                    Rectangle().stroke(.orange,lineWidth:2).frame(width:rect.width,height:rect.height)
                        .position(x:rect.midX,y:rect.midY)
                    ForEach(CropHandle.allCases,id:\.self) { handle in
                        RoundedRectangle(cornerRadius:2).fill(.white)
                            .overlay { RoundedRectangle(cornerRadius:2).stroke(.orange,lineWidth:1.5) }
                            .frame(width:9,height:9)
                            .position(x:rect.minX+handle.position.x*rect.width,y:rect.minY+handle.position.y*rect.height)
                    }
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:2).onChanged { value in
                    guard scaleStart == nil,fitted.width>0,fitted.height>0 else { return }
                    if drag == nil {
                        let selectedRect=displayRect(crop,in:fitted)
                        let handle=hasSelection ? hitHandle(at:value.startLocation,rect:selectedRect) : nil
                        guard fitted.contains(value.startLocation) || handle != nil else { return }
                        focused=true
                        let start=normalized(value.startLocation,in:fitted)
                        if hasSelection {
                            if let handle {
                                drag=CropDrag(operation:.resize(crop,handle))
                            } else if selectedRect.contains(value.startLocation) {
                                drag=CropDrag(operation:.move(crop))
                                #if os(macOS)
                                NSCursor.closedHand.set()
                                #endif
                            } else {
                                drag=CropDrag(operation:.draw(start))
                            }
                        } else {
                            drag=CropDrag(operation:.draw(start))
                        }
                    }
                    let translation=CGSize(width:value.translation.width/fitted.width,height:value.translation.height/fitted.height)
                    switch drag?.operation {
                    case .draw(let start): draft=CropGeometry.drawn(from:start,to:normalized(value.location,in:fitted),aspectRatio:aspectRatio)
                    case .move(let original): draft=CropGeometry.moved(original,by:translation)
                    case .resize(let original,let handle): draft=CropGeometry.resized(original,handle:handle,by:translation,aspectRatio:aspectRatio)
                    case nil: break
                    }
                }.onEnded { _ in commit();drag=nil
                    #if os(macOS)
                    NSCursor.arrow.set()
                    #endif
                })
                .simultaneousGesture(MagnificationGesture().onChanged { value in
                    guard hasSelection,drag == nil else { return }
                    if scaleStart == nil { scaleStart=crop }
                    if let original=scaleStart { draft=CropGeometry.scaled(original,by:value) }
                }.onEnded { _ in commit();scaleStart=nil })
                #if os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard drag == nil,scaleStart == nil else { return }
                        if hasSelection {
                            let rect=displayRect(crop,in:fitted)
                            if let handle=hitHandle(at:location,rect:rect) {
                                switch handle {
                                case .left,.right: NSCursor.resizeLeftRight.set()
                                case .top,.bottom: NSCursor.resizeUpDown.set()
                                default: NSCursor.crosshair.set()
                                }
                            } else if rect.contains(location) { NSCursor.openHand.set() }
                            else { NSCursor.arrow.set() }
                        } else if fitted.contains(location) { NSCursor.crosshair.set() }
                        else { NSCursor.arrow.set() }
                    case .ended: NSCursor.arrow.set()
                    }
                }
                #endif
        }
        .clipShape(RoundedRectangle(cornerRadius:12))
        .focusable().focused($focused).focusEffectDisabled()
        #if os(macOS)
        .onDeleteCommand { if hasSelection { onDelete() } }
        #endif
        .onChange(of:hasSelection) { _,_ in draft=nil;drag=nil;scaleStart=nil }
        .onChange(of:crop) { _,_ in draft=nil;drag=nil;scaleStart=nil }
        .accessibilityLabel(L("Crop editor"))
        .accessibilityHint(L("Drag inside the crop to move it, or drag one of its eight handles to resize. Pinch to scale. Press Delete to reset the crop."))
    }

    private func commit() {
        if let draft { crop=draft;hasSelection=true }
        draft=nil
    }
    private func normalized(_ point:CGPoint,in fitted:CGRect)->CGPoint {
        CGPoint(x:(point.x-fitted.minX)/fitted.width,y:(point.y-fitted.minY)/fitted.height)
    }
    private func displayRect(_ crop:Crop,in fitted:CGRect)->CGRect {
        CGRect(x:fitted.minX+crop.x*fitted.width,y:fitted.minY+crop.y*fitted.height,
               width:crop.width*fitted.width,height:crop.height*fitted.height)
    }
    private func hitHandle(at point:CGPoint,rect:CGRect)->CropHandle? {
        // Prefer corners if a small crop makes their hit areas overlap an edge.
        let corners:[CropHandle]=[.topLeft,.topRight,.bottomRight,.bottomLeft]
        if let corner=corners.min(by:{ distance(point,to:$0,rect:rect)<distance(point,to:$1,rect:rect) }),
           distance(point,to:corner,rect:rect)<=13 { return corner }
        let insideX=point.x>=rect.minX && point.x<=rect.maxX
        let insideY=point.y>=rect.minY && point.y<=rect.maxY
        if insideX,abs(point.y-rect.minY)<=8 { return .top }
        if insideX,abs(point.y-rect.maxY)<=8 { return .bottom }
        if insideY,abs(point.x-rect.minX)<=8 { return .left }
        if insideY,abs(point.x-rect.maxX)<=8 { return .right }
        return nil
    }
    private func distance(_ point:CGPoint,to handle:CropHandle,rect:CGRect)->Double {
        hypot(point.x-(rect.minX+handle.position.x*rect.width),point.y-(rect.minY+handle.position.y*rect.height))
    }
}
