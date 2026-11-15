import SwiftUI
import BraidCore

@MainActor
final class PictureExportOptions: ObservableObject {
    @Published var size:PictureExportSize { didSet { onSizeChange?(size) } }
    let viewport:CGSize
    private let onSizeChange:((PictureExportSize)->Void)?
    init(size:PictureExportSize,viewport:CGSize,onSizeChange:((PictureExportSize)->Void)? = nil) {
        self.size=size;self.viewport=viewport;self.onSizeChange=onSizeChange
    }
    var pixelSize:CGSize { size.pixelSize(viewport:viewport) }
}

struct PictureExportOptionsView: View {
    @ObservedObject var options:PictureExportOptions
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Picker("Output size",selection:$options.size) {
                ForEach(PictureExportSize.allCases) { size in Text(size.title).tag(size) }
            }
            Text("\(Int(options.pixelSize.width)) × \(Int(options.pixelSize.height)) pixels · PNG")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("Exports the area inside the red frame in the 3D view, keeping your current rotation and pan. Changing the output size updates the frame. Rendering starts after Save.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(12).frame(width:460)
    }
}
