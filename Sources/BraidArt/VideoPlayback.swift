import AVFoundation
import SwiftUI
import BraidCore

@MainActor
final class VideoPlayback:ObservableObject {
    let player:AVPlayer
    @Published private(set) var position:Double
    @Published private(set) var isPlaying=false
    private(set) var segment:VideoSegment
    var onPlaybackChanged:((Bool)->Void)?
    var onPaused:((Double)->Void)?
    private var periodic:Any?
    private var boundary:Any?
    private var ended:NSObjectProtocol?
    private var loopSeekPending=false

    init(source:VideoSource,segment:VideoSegment) {
        player=AVPlayer(url:source.url);player.actionAtItemEnd = .none
        self.segment=segment;position=segment.start
        periodic=player.addPeriodicTimeObserver(forInterval:CMTime(value:1,timescale:30),queue:.main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self,time.seconds.isFinite else { return }
                self.position=time.seconds
                if self.isPlaying,time.seconds>=self.segment.end { self.loop() }
            }
        }
        updateBoundary()
        ended=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:player.currentItem,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loop() }
        }
    }
    func setSegment(_ segment:VideoSegment) {
        self.segment=segment;updateBoundary()
        if position<segment.start || position>=segment.end {
            seek(to:segment.start,pause:false)
        }
    }
    func seek(to time:Double,pause:Bool=true) {
        if pause { _=self.pause(notify:false) }
        position=min(segment.end-0.000001,max(segment.start,time))
        player.seek(to:CMTime(seconds:position,preferredTimescale:600_000),toleranceBefore:.zero,toleranceAfter:.zero)
    }
    func play() {
        if position<segment.start || position>=segment.end-0.001 { seek(to:segment.start,pause:false) }
        isPlaying=true;onPlaybackChanged?(true);player.play()
    }
    @discardableResult func pause(notify:Bool=true)->Double {
        player.pause()
        let current=player.currentTime().seconds
        if current.isFinite { position=min(segment.end-0.000001,max(segment.start,current)) }
        isPlaying=false;onPlaybackChanged?(false)
        if notify { onPaused?(position) }
        return position
    }
    private func loop() {
        guard isPlaying,!loopSeekPending else { return }
        loopSeekPending=true
        player.seek(to:CMTime(seconds:segment.start,preferredTimescale:600_000),toleranceBefore:.zero,toleranceAfter:.zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.loopSeekPending=false
                guard finished,self.isPlaying else { return }
                self.position=self.segment.start;self.player.play()
            }
        }
    }
    private func updateBoundary() {
        player.currentItem?.forwardPlaybackEndTime=CMTime(seconds:segment.end,preferredTimescale:600_000)
        if let boundary { player.removeTimeObserver(boundary) }
        boundary=player.addBoundaryTimeObserver(forTimes:[NSValue(time:CMTime(seconds:segment.end,preferredTimescale:600_000))],queue:.main) { [weak self] in
            MainActor.assumeIsolated { self?.loop() }
        }
    }
    func invalidate() {
        player.pause();isPlaying=false;loopSeekPending=false;onPaused=nil;onPlaybackChanged=nil
        if let periodic { player.removeTimeObserver(periodic);self.periodic=nil }
        if let boundary { player.removeTimeObserver(boundary);self.boundary=nil }
        if let ended { NotificationCenter.default.removeObserver(ended);self.ended=nil }
        player.replaceCurrentItem(with:nil)
    }
    deinit {
        if let periodic { player.removeTimeObserver(periodic) }
        if let boundary { player.removeTimeObserver(boundary) }
        if let ended { NotificationCenter.default.removeObserver(ended) }
    }
}

struct VideoPreview: NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->PlayerSurface { let view=PlayerSurface();view.playerLayer.player=player;return view }
    func updateNSView(_ view:PlayerSurface,context:Context) { view.playerLayer.player=player }
    final class PlayerSurface:NSView {
        let playerLayer=AVPlayerLayer()
        override init(frame:NSRect) {
            super.init(frame:frame);wantsLayer=true;playerLayer.videoGravity = .resizeAspect;layer?.addSublayer(playerLayer)
        }
        required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout();playerLayer.frame=bounds }
    }
}
