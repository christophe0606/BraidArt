import SwiftUI
import AppKit

enum HelpTopic:String,CaseIterable {
    case overview,picture,crop,woven,sculpture,sharing
    var title:String {
        switch self {
        case .overview: return "BraidArt Help"
        case .picture: return "Start with a picture"
        case .crop: return "Focus on what matters"
        case .woven: return "See it woven"
        case .sculpture: return "Explore another dimension"
        case .sharing: return "Make it your own"
        }
    }
    var text:String {
        switch self {
        case .overview: return "BraidArt transforms photographs and illustrations into patterns of interlacing strands. From a distance, the strands reveal your picture. Up close, they form a world of curves, crossings and loops."
        case .picture: return "Choose a portrait, a landscape or any picture you love. This example starts with NASA’s photograph of astronaut Eileen Collins."
        case .crop: return "Crop the picture to bring your subject closer. Here, a black-and-white crop of Eileen Collins’s face becomes the starting point for the artwork."
        case .woven: return "BraidArt reimagines the light, dark and color in your picture as connected strands, creating a new way to see a familiar image."
        case .sculpture: return "The same woven picture can become a 3D sculpture. Turn it around, move closer and discover how the strands pass over and under one another."
        case .sharing: return "Try different colors and levels of detail to find a look you like. Save your project to return to it later, or choose File → Export to keep and share your artwork as a picture or a 3D object."
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

    var url:URL? { Bundle.module.url(forResource:rawValue,withExtension:nil,subdirectory:"Help") }
    var image:NSImage? { url.flatMap { NSImage(contentsOf:$0) } }
    var description:String {
        switch self {
        case .photograph: return "Original NASA color photograph of astronaut Eileen Collins"
        case .crop: return "Cropped black-and-white view of Eileen Collins’s face"
        case .woven: return "Eileen Collins’s face recreated with black and white interlacing strands"
        case .sculpture: return "An angled view of Eileen Collins’s face as a sculpture of woven strands"
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
                        Image(nsImage:AppIcon.image).resizable().interpolation(.low).frame(width:64,height:64).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:5) {
                            Text("BraidArt Help").font(.largeTitle.weight(.semibold))
                            Text("Turn a picture into woven art.").font(.title3).foregroundStyle(.secondary)
                        }
                    }.id(HelpTopic.overview)
                    Text(HelpTopic.overview.text)
                        .font(.body).fixedSize(horizontal:false,vertical:true)
                    HStack(alignment:.top,spacing:24) {
                        VStack(alignment:.leading,spacing:12) {
                            illustration(.photograph).frame(height:300)
                            explanation(.picture)
                        }.frame(maxWidth:.infinity).id(HelpTopic.picture)
                        VStack(alignment:.leading,spacing:12) {
                            illustration(.crop).frame(height:300)
                            explanation(.crop)
                        }.frame(maxWidth:.infinity).id(HelpTopic.crop)
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
                }
                .padding(32).frame(maxWidth:960).frame(maxWidth:.infinity)
            }
            .onChange(of:navigation.request) { _,_ in proxy.scrollTo(navigation.topic,anchor:.top) }
            .onAppear { proxy.scrollTo(navigation.topic,anchor:.top) }
            }
            Divider()
            HStack {
                Text("A picture. A pattern. A sculpture.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(minWidth:720,minHeight:580)
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
                Image(nsImage:image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:10))
        .accessibilityElement(children:.ignore).accessibilityLabel(example.description)
    }
}
