import Foundation
import CoreGraphics

public enum CropHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    public var position: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x:0,y:0)
        case .top: return CGPoint(x:0.5,y:0)
        case .topRight: return CGPoint(x:1,y:0)
        case .right: return CGPoint(x:1,y:0.5)
        case .bottomRight: return CGPoint(x:1,y:1)
        case .bottom: return CGPoint(x:0.5,y:1)
        case .bottomLeft: return CGPoint(x:0,y:1)
        case .left: return CGPoint(x:0,y:0.5)
        }
    }
}

/// Crop coordinates and translations are fractions of the oriented source image.
/// A fixed ratio is converted into that coordinate space before editing.
public enum CropGeometry {
    public static let minimumSize=0.02

    public static func normalizedAspectRatio(for preset:PictureExportSize?,imageSize:CGSize)->Double? {
        guard let preset,preset != .viewport,imageSize.width>0,imageSize.height>0 else { return nil }
        let size=preset.pixelSize(viewport:imageSize)
        return (size.width/size.height)*(imageSize.height/imageSize.width)
    }

    public static func fitted(_ crop:Crop,aspectRatio:Double?)->Crop {
        guard let ratio=aspectRatio,ratio.isFinite,ratio>0 else { return crop }
        let width=min(crop.width,crop.height*ratio),height=width/ratio
        return Crop(x:crop.x+(crop.width-width)/2,y:crop.y+(crop.height-height)/2,width:width,height:height)
    }

    public static func moved(_ crop:Crop,by translation:CGSize)->Crop {
        Crop(x:clamp(crop.x+translation.width,0,1-crop.width),
             y:clamp(crop.y+translation.height,0,1-crop.height),width:crop.width,height:crop.height)
    }

    /// Scale around the center, stopping at the image boundary or minimum size.
    /// Both dimensions always use the same factor, including in free mode.
    public static func scaled(_ crop:Crop,by factor:Double)->Crop {
        guard factor.isFinite,factor>0 else { return crop }
        let cx=crop.x+crop.width/2,cy=crop.y+crop.height/2
        let maximum=min(2*min(cx,1-cx)/crop.width,2*min(cy,1-cy)/crop.height)
        let minimum=min(1,max(minimumSize/crop.width,minimumSize/crop.height))
        let scale=clamp(factor,minimum,maximum)
        let width=crop.width*scale,height=crop.height*scale
        return Crop(x:cx-width/2,y:cy-height/2,width:width,height:height)
    }

    public static func drawn(from start:CGPoint,to end:CGPoint,aspectRatio:Double?)->Crop? {
        let start=pointInImage(start),end=pointInImage(end)
        let sx=end.x>=start.x ? 1.0 : -1.0,sy=end.y>=start.y ? 1.0 : -1.0
        var width=abs(end.x-start.x),height=abs(end.y-start.y)
        if let ratio=aspectRatio,ratio.isFinite,ratio>0 {
            let maxWidth=min(sx>0 ? 1-start.x : start.x,(sy>0 ? 1-start.y : start.y)*ratio)
            width=min(max(width,height*ratio),maxWidth);height=width/ratio
        }
        let minWidth=min(minimumSize,aspectRatio ?? 1)
        let minHeight=min(minimumSize,1/(aspectRatio ?? 1))
        guard width>=minWidth,height>=minHeight else { return nil }
        return Crop(x:sx>0 ? start.x : start.x-width,y:sy>0 ? start.y : start.y-height,width:width,height:height)
    }

    public static func resized(_ crop:Crop,handle:CropHandle,by translation:CGSize,aspectRatio:Double?)->Crop {
        let p=handle.position
        let left=p.x==0,right=p.x==1,top=p.y==0,bottom=p.y==1
        let minWidth=min(minimumSize,crop.width),minHeight=min(minimumSize,crop.height)
        guard let ratio=aspectRatio,ratio.isFinite,ratio>0 else {
            let x0=left ? clamp(crop.x+translation.width,0,crop.x+crop.width-minWidth) : crop.x
            let x1=right ? clamp(crop.x+crop.width+translation.width,crop.x+minWidth,1) : crop.x+crop.width
            let y0=top ? clamp(crop.y+translation.height,0,crop.y+crop.height-minHeight) : crop.y
            let y1=bottom ? clamp(crop.y+crop.height+translation.height,crop.y+minHeight,1) : crop.y+crop.height
            return Crop(x:x0,y:y0,width:x1-x0,height:y1-y0)
        }
        let sx=left ? -1.0 : 1.0,sy=top ? -1.0 : 1.0
        let anchorX=left ? crop.x+crop.width : crop.x
        let anchorY=top ? crop.y+crop.height : crop.y
        let cx=crop.x+crop.width/2,cy=crop.y+crop.height/2
        let minimum=min(crop.width,max(minimumSize,minimumSize*ratio))
        if (left || right) && (top || bottom) {
            // Project the dragged corner onto the fixed-ratio diagonal.
            let requestedWidth=crop.width+sx*translation.width
            let requestedHeight=crop.height+sy*translation.height
            let requested=(requestedWidth+requestedHeight/ratio)/(1+1/(ratio*ratio))
            let maximum=min(left ? anchorX : 1-anchorX,(top ? anchorY : 1-anchorY)*ratio)
            let width=clamp(requested,minimum,maximum),height=width/ratio
            return Crop(x:left ? anchorX-width : anchorX,y:top ? anchorY-height : anchorY,width:width,height:height)
        } else if left || right {
            let maximum=min(left ? anchorX : 1-anchorX,2*min(cy,1-cy)*ratio)
            let width=clamp(crop.width+sx*translation.width,minimum,maximum),height=width/ratio
            return Crop(x:left ? anchorX-width : anchorX,y:cy-height/2,width:width,height:height)
        } else {
            let maximum=min(top ? anchorY : 1-anchorY,2*min(cx,1-cx)/ratio)
            let height=clamp(crop.height+sy*translation.height,minimum/ratio,maximum),width=height*ratio
            return Crop(x:cx-width/2,y:top ? anchorY-height : anchorY,width:width,height:height)
        }
    }

    private static func clamp(_ value:Double,_ lower:Double,_ upper:Double)->Double {
        min(max(value,min(lower,upper)),upper)
    }
    private static func pointInImage(_ point:CGPoint)->CGPoint {
        CGPoint(x:clamp(point.x,0,1),y:clamp(point.y,0,1))
    }
}
