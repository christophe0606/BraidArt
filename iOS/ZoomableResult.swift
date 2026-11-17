import SwiftUI

/// UIScrollView keeps the pinch focal point stable and supports dragging the enlarged result.
struct ZoomableResult:UIViewRepresentable {
    let image:UIImage
    @Binding var zoom:Double
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeUIView(context:Context)->ResultScrollView {
        let scroll=ResultScrollView();scroll.delegate=context.coordinator
        scroll.minimumZoomScale=0.25;scroll.maximumZoomScale=8
        scroll.backgroundColor = .secondarySystemBackground
        scroll.addSubview(scroll.picture)
        return scroll
    }
    func updateUIView(_ scroll:ResultScrollView,context:Context) {
        context.coordinator.parent=self
        context.coordinator.isUpdating=true
        defer { context.coordinator.isUpdating=false }
        if scroll.picture.image !== image {
            scroll.picture.image=image;scroll.setZoomScale(1,animated:false);scroll.needsFit=true
        }
        if !scroll.isZooming,abs(scroll.zoomScale-zoom)>0.001 { scroll.setZoomScale(zoom,animated:false) }
        scroll.setNeedsLayout()
    }
    final class ResultScrollView:UIScrollView {
        let picture=UIImageView()
        var needsFit=true
        var isFitting=false
        private var previousSize=CGSize.zero
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image=picture.image,bounds.width>0,bounds.height>0 else { return }
            if needsFit || previousSize != bounds.size {
                isFitting=true
                defer { isFitting=false }
                let currentZoom=zoomScale
                setZoomScale(1,animated:false)
                let fit=min(bounds.width/image.size.width,bounds.height/image.size.height)
                picture.frame=CGRect(origin:.zero,size:CGSize(width:image.size.width*fit,height:image.size.height*fit))
                picture.contentMode = .scaleAspectFit
                contentSize=picture.bounds.size
                needsFit=false;previousSize=bounds.size
                setZoomScale(currentZoom,animated:false)
            }
            contentInset=UIEdgeInsets(top:max(0,(bounds.height-contentSize.height)/2),left:max(0,(bounds.width-contentSize.width)/2),bottom:0,right:0)
        }
    }
    final class Coordinator:NSObject,UIScrollViewDelegate {
        var parent:ZoomableResult
        var isUpdating=false
        init(_ parent:ZoomableResult) { self.parent=parent }
        func viewForZooming(in scrollView:UIScrollView)->UIView? { (scrollView as? ResultScrollView)?.picture }
        func scrollViewDidZoom(_ scrollView:UIScrollView) {
            guard !isUpdating,(scrollView as? ResultScrollView)?.isFitting != true else { return }
            let value=Double(scrollView.zoomScale)
            DispatchQueue.main.async {
                // Ignore intermediate values superseded by another pinch sample or Fit.
                guard abs(Double(scrollView.zoomScale)-value)<0.001 else { return }
                if abs(self.parent.zoom-value)>0.001 { self.parent.zoom=value }
            }
        }
    }
}
