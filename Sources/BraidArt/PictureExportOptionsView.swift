import SwiftUI
import BraidCore

@MainActor
final class PictureExportOptions: ObservableObject {
    @Published var size:PictureExportSize { didSet { onSizeChange?(size) } }
    let viewport:CGSize
    let customDimensions:[PictureExportSize]
    private let onSizeChange:((PictureExportSize)->Void)?
    init(size:PictureExportSize,viewport:CGSize,customDimensions:[PictureExportSize] = [],onSizeChange:((PictureExportSize)->Void)? = nil) {
        self.size=size;self.viewport=viewport;self.customDimensions=customDimensions;self.onSizeChange=onSizeChange
    }
    var pixelSize:CGSize { size.pixelSize(viewport:viewport) }
}

struct PictureExportOptionsView: View {
    @ObservedObject var options:PictureExportOptions
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            DimensionPicker(title:L("Output size"),selection:$options.size,customDimensions:options.customDimensions,includeViewport:true)
            Text(L("%@ × %@ pixels · PNG", String(describing: Int(options.pixelSize.width)), String(describing: Int(options.pixelSize.height))))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(L("Exports the area inside the red frame in the 3D view, keeping your current rotation and pan. Changing the output size updates the frame. Rendering starts after Save."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(12).frame(width:460)
    }
}
