import SwiftUI
import BraidCore

enum PhoneLiveSettings: String, CaseIterable, Identifiable {
    case dimensions = "outputDimensions"
    case imageWidth
    case luminance
    case geometry = "strandGeometry"
    case pictureDimensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dimensions: L("Output dimensions")
        case .imageWidth: L("Image width")
        case .luminance: L("Luminance and contrast")
        case .geometry: L("Strand geometry")
        case .pictureDimensions: L("Picture dimensions")
        }
    }

    var symbol: String {
        switch self {
        case .dimensions, .pictureDimensions: "aspectratio"
        case .imageWidth: "arrow.left.and.right"
        case .luminance: "circle.lefthalf.filled"
        case .geometry: "scribble"
        }
    }

    func isAvailable(on tab: Int) -> Bool {
        switch self {
        case .dimensions, .imageWidth, .luminance: tab == 0
        case .geometry: tab == 1
        case .pictureDimensions: tab == 3
        }
    }

    @MainActor @ViewBuilder
    func controls(_ settings: SettingsControls) -> some View {
        switch self {
        case .dimensions:
            settings.outputDimensions(compact: true)
        case .imageWidth:
            settings.imageWidth
            if !settings.state.hasSourceImage && settings.state.hasProject {
                Text(L("This project contains the sampled image. Open the original picture to change the crop or resize."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .luminance:
            settings.luminance
        case .geometry:
            settings.strandGeometry
        case .pictureDimensions:
            DimensionPicker.for3DPicture(model: settings.model, compact: true)
        }
    }
}

struct PhoneSettingsScreen: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let controls = SettingsControls(model: model, state: SidebarState(model: model))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Tiles & palette")).font(.headline).accessibilityAddTraits(.isHeader)
                    controls.palette
                    Divider().padding(.vertical, 8)
                    Text(L("Partition solve")).font(.headline).accessibilityAddTraits(.isHeader)
                    controls.partition
                }
                .frame(maxWidth: 540)
                .padding(20)
                .frame(maxWidth: .infinity)
                .disabled(model.blocksEditing)
            }
            .accessibilityIdentifier("phoneSettingsScroll")
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                        .accessibilityIdentifier("closePhoneSettings")
                }
            }
        }
    }
}
