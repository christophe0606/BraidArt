import Foundation
import CoreGraphics

public enum CurveExporter {
    /// One page of filled vector strand contours with fine black edges, as in the reference PDF.
    public static func writePDF(_ braid: BraidCurves, to url: URL, pointsPerTile: Double = 24) throws {
        guard pointsPerTile.isFinite,(1...1000).contains(pointsPerTile) else { throw BraidError.invalid("Invalid PDF scale.") }
        var box=CGRect(x:0,y:0,width:Double(braid.columns)*pointsPerTile,height:Double(braid.rows)*pointsPerTile)
        let output=NSMutableData()
        guard let consumer=CGDataConsumer(data:output),let ctx=CGContext(consumer:consumer,mediaBox:&box,nil) else { throw BraidError.invalid("Cannot create vector PDF.") }
        ctx.beginPDFPage(nil)
        ctx.scaleBy(x:pointsPerTile,y:pointsPerTile)
        ctx.translateBy(x:-0.5,y:Double(braid.rows)+0.5)
        let bounds=CGRect(x:0.5,y:-Double(braid.rows)-0.5,width:Double(braid.columns),height:Double(braid.rows))
        ctx.setFillColor(red:braid.background.r,green:braid.background.g,blue:braid.background.b,alpha:1)
        ctx.fill(bounds);ctx.clip(to:bounds)
        // The reference uses an outline about 0.02 tile wide. Inset its center so the
        // outside strand width is preserved. Outlining the contour also edges cut ends.
        let edgeWidth=0.02
        ctx.setStrokeColor(red:0,green:0,blue:0,alpha:1)
        ctx.setLineWidth(edgeWidth);ctx.setLineJoin(.round)
        for curve in braid.curves {
            let color=braid.palette[curve.colorIndex]
            ctx.setFillColor(red:color.r,green:color.g,blue:color.b,alpha:1)
            var fragments=[[CurveSegment]](),current=[CurveSegment]()
            for s in curve.segments {
                if s.points.count==2 && !s.raised {
                    // Split the underpass before outlining it, giving the two exposed
                    // ends their own fine edges instead of erasing them with a mask.
                    let cut=(braid.strandWidth+braid.gap)/2
                    var before=s,after=s
                    before.points=[s.start,s.point(at:0.5-cut)]
                    after.points=[s.point(at:0.5+cut),s.end]
                    current.append(before);fragments.append(current);current=[after]
                } else { current.append(s) }
            }
            let uninterrupted=fragments.isEmpty
            if curve.closed && !uninterrupted {
                // A closed curve's arbitrary tracing origin must not introduce an end seam.
                fragments[0]=current+fragments[0]
            } else if !current.isEmpty { fragments.append(current) }
            for fragment in fragments {
                guard let first=fragment.first else { continue }
                let path=CGMutablePath();path.move(to:CGPoint(x:first.start.x,y:first.start.y))
                for s in fragment {
                    if s.points.count==2 || s.raised { path.addLine(to:CGPoint(x:s.end.x,y:s.end.y)) }
                    else { path.addCurve(to:CGPoint(x:s.end.x,y:s.end.y),control1:CGPoint(x:s.points[1].x,y:s.points[1].y),control2:CGPoint(x:s.points[2].x,y:s.points[2].y)) }
                }
                if curve.closed && uninterrupted { path.closeSubpath() }
                let contour=path.copy(strokingWithWidth:braid.strandWidth-edgeWidth,lineCap:.butt,lineJoin:.round,miterLimit:10)
                ctx.addPath(contour);ctx.drawPath(using:.fillStroke)
            }
        }
        ctx.endPDFPage();ctx.closePDF()
        try (output as Data).write(to:url,options:.atomic)
    }
}
