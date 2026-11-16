import SwiftUI
import BraidCore

struct VideoTimelineView:View {
    @ObservedObject var playback:VideoPlayback
    let source:VideoSource
    let segment:VideoSegment
    let selectFrame:(Double)->Void
    let changeSegment:(Double,Double)->Void
    let disabled:Bool

    private var minimumDuration:Double { min(source.duration,1/max(1,source.frameRate)) }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Button {
                    if playback.isPlaying { playback.pause() } else { playback.play() }
                } label: {
                    Label(playback.isPlaying ? L("Pause segment") : L("Play segment"),systemImage:playback.isPlaying ? "pause.fill" : "play.fill")
                }.disabled(disabled)
                Spacer()
                Text(String(format:L("Frame: %.3f s"),playback.position)).font(.caption.monospacedDigit())
            }
            GeometryReader { proxy in
                let width=max(1,proxy.size.width-16)
                let start=8+width*segment.start/source.duration,end=8+width*segment.end/source.duration
                let playhead=8+width*min(source.duration,max(0,playback.position))/source.duration
                ZStack(alignment:.topLeading) {
                    RoundedRectangle(cornerRadius:5).fill(.secondary.opacity(0.18)).frame(width:width,height:30).offset(x:8,y:10)
                    Rectangle().fill(.orange.opacity(0.25)).frame(width:max(1,end-start),height:30).offset(x:start,y:10)
                    Rectangle().strokeBorder(.orange,lineWidth:1).frame(width:max(1,end-start),height:30).offset(x:start,y:10)
                    Rectangle().fill(.primary).frame(width:2,height:44).offset(x:playhead-1,y:3).allowsHitTesting(false)
                    Image(systemName:"arrowtriangle.down.fill").font(.system(size:10)).position(x:playhead,y:3).allowsHitTesting(false)
                    handle(start:true,x:start,width:width)
                    handle(start:false,x:end,width:width)
                }.frame(height:50).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("videoTimeline")).onChanged { value in
                        let time=(value.location.x-8)/width*source.duration
                        selectFrame(min(segment.end-0.000001,max(segment.start,time)))
                    })
                    .coordinateSpace(name:"videoTimeline")
                    .accessibilityElement(children:.contain)
                    .accessibilityLabel(L("Video segment and playhead"))
                    .accessibilityAdjustableAction { direction in
                        selectFrame(min(segment.end-0.000001,max(segment.start,playback.position+(direction == .increment ? 1 : -1)/source.frameRate)))
                    }
            }.frame(height:50).disabled(disabled)
            HStack {
                Text(String(format:L("Start: %.3f s"),segment.start))
                Spacer()
                Text(String(format:L("Duration: %.3f s"),segment.duration))
                Spacer()
                Text(String(format:L("End: %.3f s"),segment.end))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(L("Drag the orange handles to trim the segment. Click or drag the playhead to choose a test frame. Playback loops the segment; you can adjust the crop while it plays."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func handle(start:Bool,x:Double,width:Double)->some View {
        RoundedRectangle(cornerRadius:4).fill(.orange)
            .overlay { Capsule().fill(.white).frame(width:2,height:18) }
            .frame(width:14,height:38).position(x:x,y:25)
            .highPriorityGesture(DragGesture(minimumDistance:0,coordinateSpace:.named("videoTimeline")).onChanged { value in
                let time=(value.location.x-8)/width*source.duration
                if start { changeSegment(min(segment.end-minimumDuration,max(0,time)),segment.end) }
                else { changeSegment(segment.start,max(segment.start+minimumDuration,min(source.duration,time))) }
            })
            .accessibilityLabel(start ? L("Segment start") : L("Segment end"))
            .accessibilityValue(String(format:"%.3f",start ? segment.start : segment.end))
            .accessibilityAdjustableAction { direction in
                let delta=(direction == .increment ? 1.0 : -1.0)/source.frameRate
                if start { changeSegment(min(segment.end-minimumDuration,max(0,segment.start+delta)),segment.end) }
                else { changeSegment(segment.start,max(segment.start+minimumDuration,min(source.duration,segment.end+delta))) }
            }
            .help(start ? L("Drag to change the segment start") : L("Drag to change the segment end"))
    }
}
