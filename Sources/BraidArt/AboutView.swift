#if os(macOS)
import BraidCore
import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    private let bookURL=URL(string:"https://press.princeton.edu/books/hardcover/9780691164069/opt-art")!
    private var version: String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? L("Development build")
        if let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String { return L("Version %@ (%@)", String(describing: version), String(describing: build)) }
        return version
    }

    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack(alignment:.center,spacing:18) {
                        Image(nsImage:AppIcon.image).resizable().interpolation(.low).frame(width:76,height:76)
                            .accessibilityLabel(L("BraidArt app icon"))
                        VStack(alignment:.leading,spacing:5) {
                            Text(L("BraidArt")).font(.largeTitle.weight(.semibold))
                            Text(version).font(.caption).foregroundStyle(.secondary)
                            Text(L("Copyright © 2026 Christophe Favergeon")).font(.callout)
                        }
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:9) {
                        Text(L("Inspiration")).font(.headline)
                        Link(L("Opt Art: From Mathematical Optimization to Visual Design"),destination:bookURL)
                            .font(.body.weight(.medium))
                            .accessibilityHint(L("Opens the book page at Princeton University Press"))
                        Text(L("Robert Bosch · Princeton University Press · 2019")).font(.callout).foregroundStyle(.secondary)
                        Text(L("Inspired by Robert Bosch’s book. BraidArt uses a substantially different implementation with additional features."))
                            .font(.callout).fixedSize(horizontal:false,vertical:true)
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:9) {
                        Text(L("Help illustrations")).font(.headline)
                        Text(L("Eileen Collins · Photograph: NASA, via scikit-image"))
                            .font(.callout.weight(.medium))
                        Text(L("Public domain. The scikit-image image record identifies this photograph as having no known copyright restrictions."))
                            .font(.callout).fixedSize(horizontal:false,vertical:true)
                        HStack(spacing:16) {
                            Link(L("Original NASA photograph"),destination:URL(string:"https://flic.kr/p/r9qvLn")!)
                            Link(L("Image record and rights"),destination:URL(string:"https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut")!)
                        }
                        Text(L("The cropped portrait, woven picture and 3D artwork are adaptations made with BraidArt."))
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Link(L("NASA media usage guidelines"),destination:URL(string:"https://www.nasa.gov/nasa-brand-center/images-and-media/")!)
                            .font(.callout)
                    }
                    Divider()
                    ThirdPartyLibrariesView()
                }.padding(26)
            }
            Divider()
            HStack {
                Spacer()
                Button(L("Done")) { dismissWindow(id:"about") }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(width:650,height:740)
    }

}

#endif
