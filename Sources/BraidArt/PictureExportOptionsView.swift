import SwiftUI
import BraidCore

@MainActor
final class PictureExportOptions: ObservableObject {
    @Published var size:PictureExportSize
    let viewport:CGSize
    init(size:PictureExportSize,viewport:CGSize) { self.size=size;self.viewport=viewport }
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
            Text("Keeps the camera angle and fits the current framing without cropping or stretching. Rendering starts after Save.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(12).frame(width:460)
    }
}
