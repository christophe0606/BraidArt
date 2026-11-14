import AppKit
let size=1024
let image=NSImage(size:NSSize(width:size,height:size))
image.lockFocus()
NSColor(calibratedRed:0.10,green:0.12,blue:0.15,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:25,y:25,width:974,height:974),xRadius:210,yRadius:210).fill()
let orange=NSColor(calibratedRed:0.96,green:0.53,blue:0.22,alpha:1)
let cream=NSColor(calibratedRed:0.94,green:0.90,blue:0.79,alpha:1)
func curve(_ points:[NSPoint],color:NSColor,width:CGFloat) {
 let path=NSBezierPath();path.move(to:points[0]);path.curve(to:points[3],controlPoint1:points[1],controlPoint2:points[2]);path.lineWidth=width;path.lineCapStyle = .round
 color.setStroke();path.stroke()
}
let dark=NSColor(calibratedRed:0.10,green:0.12,blue:0.15,alpha:1)
let a=[NSPoint(x:210,y:240),NSPoint(x:850,y:240),NSPoint(x:180,y:784),NSPoint(x:814,y:784)]
let b=[NSPoint(x:210,y:784),NSPoint(x:850,y:784),NSPoint(x:180,y:240),NSPoint(x:814,y:240)]
curve(a,color:orange,width:115);curve(b,color:dark,width:155);curve(b,color:cream,width:115)
// A small repeat makes the knot read as a woven construction.
curve([NSPoint(x:510,y:450),NSPoint(x:500,y:475),NSPoint(x:500,y:500),NSPoint(x:510,y:525)],color:dark,width:150)
curve([NSPoint(x:510,y:450),NSPoint(x:500,y:475),NSPoint(x:500,y:500),NSPoint(x:510,y:525)],color:orange,width:110)
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
