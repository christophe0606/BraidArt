import SwiftUI
import BraidCore

struct DimensionManagerView:View {
    @ObservedObject var model:AppModel
    let target:DimensionSelectionTarget
    @Environment(\.dismiss) private var dismiss
    @State private var editing:PictureExportSize?
    @State private var name=""
    @State private var width="1920"
    @State private var height="1080"
    @State private var error:String?

    private var valid:Bool {
        guard let w=Int(width),let h=Int(height) else { return false }
        return (try? CustomPictureSize(name:name,width:w,height:h)) != nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(L("Manage Dimensions…")).font(.title2.bold())
            Text(L("Built-in dimensions are fixed. Create your own named sizes in pixels."))
                .font(.callout).foregroundStyle(.secondary)
            List {
                Section(L("User-defined dimensions")) {
                    if model.customDimensions.isEmpty { Text(L("No custom dimensions yet.")).foregroundStyle(.secondary) }
                    ForEach(model.customDimensions) { size in
                        HStack {
                            Text(size.title)
                            Spacer()
                            Button(L("Edit")) { edit(size) }.buttonStyle(.borderless)
                            Button(role:.destructive) {
                                model.deleteCustomDimensions(size)
                                if editing?.id==size.id { reset() }
                            } label: { Image(systemName:"trash") }
                                .buttonStyle(.borderless).help(L("Delete dimensions"))
                                .accessibilityLabel(L("Delete dimensions"))
                        }
                    }
                }
                Section(L("Image dimensions")) { lockedRows(PictureExportSize.imageSizes) }
                Section(L("Video dimensions")) { lockedRows(PictureExportSize.videoSizes) }
            }.listStyle(.inset).frame(height:300)
            HStack {
                Text(editing == nil ? L("New dimensions") : L("Edit dimensions")).font(.headline)
                Spacer()
                if editing != nil { Button(L("New dimensions"),action:reset) }
            }
            Grid(alignment:.leading,horizontalSpacing:12,verticalSpacing:10) {
                GridRow {
                    Text(L("Name"))
                    TextField(L("Preset name"),text:$name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L("Width (px)"))
                    TextField(L("Width (px)"),text:$width).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L("Height (px)"))
                    TextField(L("Height (px)"),text:$height).textFieldStyle(.roundedBorder)
                }
            }.onSubmit { if valid { save() } }
            Text(L("Name: 1–80 characters. Width and height: 1–8192 whole pixels."))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(editing == nil ? L("Add dimensions") : L("Save changes"),action:save)
                    .buttonStyle(.borderedProminent).disabled(!valid)
            }
        }.padding(24).frame(width:620)
    }
    private func lockedRows(_ sizes:[PictureExportSize])->some View {
        ForEach(sizes) { size in
            HStack {
                Text(size.title)
                Spacer()
                Image(systemName:"lock.fill").foregroundStyle(.secondary).accessibilityLabel(L("Built-in dimensions"))
            }
        }
    }
    private func edit(_ preset:PictureExportSize) {
        guard let custom=preset.customSize else { return }
        editing=preset;name=custom.name;width=String(custom.width);height=String(custom.height);error=nil
    }
    private func reset() { editing=nil;name="";width="1920";height="1080";error=nil }
    private func save() {
        guard let w=Int(width),let h=Int(height) else { return }
        do {
            if let editing {
                try model.editCustomDimensions(editing,name:name,width:w,height:h)
            } else {
                let preset=try model.addCustomDimensions(name:name,width:w,height:h)
                switch target {
                case .output: model.setOutputSize(preset)
                case .picture: model.pictureExportSize=preset
                }
            }
            reset()
        } catch { self.error=error.localizedDescription }
    }
}
