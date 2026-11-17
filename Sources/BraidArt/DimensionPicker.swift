import SwiftUI
import BraidCore

struct DimensionPicker:View {
    let title:String
    @Binding var selection:PictureExportSize
    let customDimensions:[PictureExportSize]
    var includeViewport=false
    var onManage:(()->Void)?

    private var customChoices:[PictureExportSize] {
        // A project carries its selected custom dimensions even on another Mac,
        // or after the preset has been changed or removed from the local library.
        var choices=customDimensions.map { $0.id==selection.id ? selection : $0 }
        if selection.customSize != nil,!choices.contains(where:{$0.id==selection.id}) { choices.append(selection) }
        return choices
    }
    var body:some View {
        #if os(iOS)
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:8) {
                dimensionMenu.labelsHidden().lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                manageButton
            }
        }.fixedSize(horizontal:false,vertical:true)
        #else
        HStack(spacing:8) { dimensionMenu;manageButton }
        #endif
    }
    private var dimensionMenu:some View {
            Picker(title,selection:$selection) {
                if includeViewport {
                    Text(PictureExportSize.viewport.title).tag(PictureExportSize.viewport)
                    Divider()
                }
                Section(L("Image dimensions")) {
                    ForEach(PictureExportSize.imageSizes) { size in Text(size.title).tag(size) }
                }
                Divider()
                Section(L("Video dimensions")) {
                    ForEach(PictureExportSize.videoSizes) { size in Text(size.title).tag(size) }
                }
                if !customChoices.isEmpty {
                    Divider()
                    Section(L("User-defined dimensions")) {
                        ForEach(customChoices) { size in Text(size.title).tag(size) }
                    }
                }
            }.pickerStyle(.menu)
    }
    @ViewBuilder private var manageButton:some View {
        if let onManage {
            Button(action:onManage) { Image(systemName:"slider.horizontal.3") }
                .buttonStyle(.borderless).help(L("Manage Dimensions…"))
                .accessibilityLabel(L("Manage Dimensions…"))
        }
    }
}
