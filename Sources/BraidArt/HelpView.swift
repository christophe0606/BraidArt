import BraidCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum HelpTopic:String,CaseIterable {
    case overview,picture,crop,woven,sculpture,sharing
    var title:String {
        switch self {
        case .overview: return L("BraidArt Help")
        case .picture: return L("Start with a picture")
        case .crop: return L("Focus on what matters")
        case .woven: return L("See it woven")
        case .sculpture: return L("Explore another dimension")
        case .sharing: return L("Make it your own")
        }
    }
    var text:String {
        switch self {
        case .overview: return L("BraidArt transforms photographs and illustrations into patterns of interlacing strands. From a distance, the strands reveal your picture. Up close, they form a world of curves, crossings and loops.")
        case .picture: return L("Choose a portrait, a landscape or any picture you love. This example starts with NASA’s photograph of astronaut Eileen Collins.")
        case .crop: return L("Crop the picture to bring your subject closer. Here, a black-and-white crop of Eileen Collins’s face becomes the starting point for the artwork.")
        case .woven: return L("BraidArt reimagines the light, dark and color in your picture as connected strands, creating a new way to see a familiar image.")
        case .sculpture: return L("The same woven picture can become a 3D sculpture. Turn it around, move closer and discover how the strands pass over and under one another.")
        case .sharing:
            #if os(macOS)
            return L("Try different colors and levels of detail to find a look you like. Save your project to return to it later, or choose File → Export to keep and share your artwork as a picture or a 3D object.")
            #else
            return L("Try different colors and levels of detail to find a look you like. Save your project to return to it later, or use the export button to keep and share your artwork as a picture or a 3D object.")
            #endif
        }
    }
    static func matching(_ query:String)->[HelpTopic] {
        let query=query.trimmingCharacters(in:.whitespacesAndNewlines)
        return query.isEmpty ? [] : allCases.filter { ($0.title+" "+$0.text).localizedCaseInsensitiveContains(query) }
    }
}

@MainActor
final class HelpNavigation:ObservableObject {
    @Published var topic=HelpTopic.overview
    @Published var request=0
    func show(_ topic:HelpTopic) { self.topic=topic;request+=1 }
}

enum HelpIllustration: String, CaseIterable {
    case photograph="astronaut.png"
    case crop="astronaut-crop.png"
    case woven="astronaut-braid.png"
    case sculpture="astronaut-3d.png"

    var url:URL? {
        #if SWIFT_PACKAGE
        let bundle=Bundle.module
        #else
        let bundle=Bundle.main
        #endif
        return bundle.url(forResource:rawValue,withExtension:nil,subdirectory:"Help")
    }
    var image:PlatformImage? { url.flatMap { PlatformImage(contentsOfFile:$0.path) } }
    var description:String {
        switch self {
        case .photograph: return L("Original NASA color photograph of astronaut Eileen Collins")
        case .crop: return L("Cropped black-and-white view of Eileen Collins’s face")
        case .woven: return L("Eileen Collins’s face recreated with black and white interlacing strands")
        case .sculpture: return L("An angled view of Eileen Collins’s face as a sculpture of woven strands")
        }
    }
}

struct HelpView: View {
    @ObservedObject var navigation:HelpNavigation
    var body:some View {
        VStack(spacing:0) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:28) {
                    HStack(spacing:16) {
                        Image(platformImage:AppIcon.image).resizable().interpolation(.low).frame(width:64,height:64).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:5) {
                            Text(L("BraidArt Help")).font(.largeTitle.weight(.semibold))
                            Text(L("Turn a picture into woven art.")).font(.title3).foregroundStyle(.secondary)
                        }
                    }.id(HelpTopic.overview)
                    HelpBookReference()
                    Text(HelpTopic.overview.text)
                        .font(.body).fixedSize(horizontal:false,vertical:true)
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.top,spacing:24) {
                            pictureIntroduction.frame(minWidth:240)
                            cropIntroduction.frame(minWidth:240)
                        }
                        VStack(alignment:.leading,spacing:24) {
                            pictureIntroduction
                            cropIntroduction
                        }
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:16) {
                        explanation(.woven)
                        illustration(.woven).frame(maxWidth:.infinity).frame(height:480)
                    }.id(HelpTopic.woven)
                    Divider()
                    VStack(alignment:.leading,spacing:16) {
                        explanation(.sculpture)
                        illustration(.sculpture)
                    }.id(HelpTopic.sculpture)
                    Divider()
                    explanation(.sharing).id(HelpTopic.sharing)
                    #if os(iOS)
                    Text(L("Choose an export format, then save or share it using the system share sheet. To import from another app, share a photo or video to BraidArt, then open BraidArt."))
                        .foregroundStyle(.secondary)
                    Text(L("One finger to rotate · Two fingers to pan · Pinch to zoom"))
                        .font(.callout).foregroundStyle(.secondary)
                    #endif
                    Divider()
                    HelpIllustrationCredits()
                }
                .padding(32).frame(maxWidth:960).frame(maxWidth:.infinity)
            }
            .accessibilityIdentifier("helpDocument")
            .onChange(of:navigation.request) { _,_ in proxy.scrollTo(navigation.topic,anchor:.top) }
            .onAppear { proxy.scrollTo(navigation.topic,anchor:.top) }
            }
            #if os(macOS)
            Divider()
            HStack {
                Text(L("A picture. A pattern. A sculpture.")).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(L("Done")) { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut(.cancelAction)
            }.padding(16)
            #endif
        }
        #if os(macOS)
        .frame(minWidth:720,minHeight:580)
        #endif
    }

    private var pictureIntroduction:some View {
        VStack(alignment:.leading,spacing:12) {
            illustration(.photograph).frame(height:300)
            explanation(.picture)
        }.frame(maxWidth:.infinity).id(HelpTopic.picture)
    }
    private var cropIntroduction:some View {
        VStack(alignment:.leading,spacing:12) {
            illustration(.crop).frame(height:300)
            explanation(.crop)
        }.frame(maxWidth:.infinity).id(HelpTopic.crop)
    }
    private func explanation(_ topic:HelpTopic)->some View {
        VStack(alignment:.leading,spacing:8) {
            Text(topic.title).font(.title2.weight(.semibold))
            Text(topic.text).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func illustration(_ example:HelpIllustration)->some View {
        Group {
            if let image=example.image {
                Image(platformImage:image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:10))
        .accessibilityElement(children:.ignore).accessibilityLabel(example.description)
    }
}

/// Displayed immediately on opening Help, on both platforms.
struct HelpBookReference:View {
    static let url=URL(string:"https://press.princeton.edu/books/hardcover/9780691164069/opt-art")!
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(L("Inspiration")).font(.headline)
            Link(L("Opt Art: From Mathematical Optimization to Visual Design"),destination:Self.url)
                .font(.body.weight(.medium))
                .accessibilityHint(L("Opens the book page at Princeton University Press"))
                .accessibilityIdentifier("helpBookLink")
            Text(L("Robert Bosch · Princeton University Press · 2019")).font(.callout).foregroundStyle(.secondary)
            Text(L("Inspired by Robert Bosch’s book. BraidArt uses a substantially different implementation with additional features."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
    }
}

struct HelpIllustrationCredits:View {
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(L("Help illustrations")).font(.headline)
            Text(L("Eileen Collins · Photograph: NASA, via scikit-image")).font(.callout)
            Text(L("Public domain. The scikit-image image record identifies this photograph as having no known copyright restrictions."))
                .font(.callout).foregroundStyle(.secondary)
            Link(L("Original NASA photograph"),destination:URL(string:"https://flic.kr/p/r9qvLn")!)
                .font(.caption)
            Text(L("The cropped portrait, woven picture and 3D artwork are adaptations made with BraidArt."))
                .font(.caption).foregroundStyle(.secondary)
            Link(L("Image record and rights"),destination:URL(string:"https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut")!)
                .font(.caption)
            Link(L("NASA media usage guidelines"),destination:URL(string:"https://www.nasa.gov/nasa-brand-center/images-and-media/")!)
                .font(.caption)
        }
    }
}
