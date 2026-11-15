import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedLicense: AboutLicense?

    private let bookURL=URL(string:"https://press.princeton.edu/books/hardcover/9780691164069/opt-art")!
    private var version: String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development build"
        if let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String { return "Version \(version) (\(build))" }
        return version
    }

    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack(alignment:.center,spacing:18) {
                        Image(nsImage:AppIcon.image).resizable().interpolation(.low).frame(width:76,height:76)
                            .accessibilityLabel("BraidArt app icon")
                        VStack(alignment:.leading,spacing:5) {
                            Text("BraidArt").font(.largeTitle.weight(.semibold))
                            Text(version).font(.caption).foregroundStyle(.secondary)
                            Text("Copyright © 2026 Christophe Favergeon").font(.callout)
                        }
                    }
                    HStack {
                        Text("Licensed under Apache License 2.0.").font(.callout)
                        Spacer()
                        Button("License") { selectedLicense = .project }
                        Button("Notice") { selectedLicense = .notice }
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:9) {
                        Text("Inspiration").font(.headline)
                        Link("Opt Art: From Mathematical Optimization to Visual Design",destination:bookURL)
                            .font(.body.weight(.medium))
                            .accessibilityHint("Opens the book page at Princeton University Press")
                        Text("Robert Bosch · Princeton University Press · 2019").font(.callout).foregroundStyle(.secondary)
                        Text("Inspired by Robert Bosch’s book. BraidArt uses a substantially different implementation with additional features.")
                            .font(.callout).fixedSize(horizontal:false,vertical:true)
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:9) {
                        Text("Help illustrations").font(.headline)
                        Text("Eileen Collins · Photograph: NASA, via scikit-image")
                            .font(.callout.weight(.medium))
                        Text("Public domain. The scikit-image image record identifies this photograph as having no known copyright restrictions.")
                            .font(.callout).fixedSize(horizontal:false,vertical:true)
                        HStack(spacing:16) {
                            Link("Original NASA photograph",destination:URL(string:"https://flic.kr/p/r9qvLn")!)
                            Link("Image record and rights",destination:URL(string:"https://scikit-image.org/docs/stable/api/skimage.data.html#skimage.data.astronaut")!)
                        }
                        Text("The cropped portrait, woven picture and 3D artwork are adaptations made with BraidArt.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Link("NASA media usage guidelines",destination:URL(string:"https://www.nasa.gov/nasa-brand-center/images-and-media/")!)
                            .font(.callout)
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:12) {
                        Text("Included projects").font(.headline)
                        Text("Each project retains its own licenses. Original license texts, author notices and source references are included with the app.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        ForEach(AboutDependency.projects) { project in
                            HStack(spacing:12) {
                                VStack(alignment:.leading,spacing:3) {
                                    Text("\(project.name) \(project.version)").font(.callout.weight(.medium))
                                    Text("EPL 2.0 (release) · EPL 1.0 (library)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Link("Source",destination:project.source)
                                Menu("Licenses") {
                                    Button("EPL 2.0 — release license") { selectedLicense=project.document("LICENSE",title:"\(project.name) — EPL 2.0",upstreamPath:"LICENSE") }
                                    Button("EPL 1.0 — library license") { selectedLicense=project.document("LIBRARY-LICENSE",title:"\(project.name) — EPL 1.0",upstreamPath:"\(project.directory)/LICENSE") }
                                    Button("Authors") { selectedLicense=project.document("AUTHORS",title:"\(project.name) — Authors",upstreamPath:"\(project.directory)/AUTHORS") }
                                    Button("Origin and source archive") { selectedLicense=project.document("ORIGIN.md",title:"\(project.name) — Origin") }
                                }
                                .fixedSize()
                                .accessibilityLabel("Licenses for \(project.name)")
                            }
                        }
                        DisclosureGroup("Additional notices") {
                            VStack(alignment:.leading,spacing:10) {
                                noticeRow("Bison-generated parser",detail:"GPL v2 or later with the upstream output exception",license:.bison)
                                noticeRow("Lucent AMPL interface",detail:"Original permission and copyright notices",license:.ampl)
                                noticeRow("Rational approximation",detail:"CoinUtils attribution and EPL 1.0 notice",license:.rational)
                                noticeRow("CIEDE2000 reference data",detail:"Gaurav Sharma, Wencheng Wu and Edul N. Dalal",license:.inventory)
                            }.padding(.top,10)
                        }.font(.callout)
                        HStack {
                            Button("All third-party notices") { selectedLicense = .inventory }
                            Button("Show license files") {
                                if let folder=AboutLicense.inventory.localURL?.deletingLastPathComponent() { NSWorkspace.shared.open(folder) }
                            }.disabled(AboutLicense.inventory.localURL == nil)
                        }
                    }
                }.padding(26)
            }
            Divider()
            HStack {
                Link("BraidArt project",destination:URL(string:"https://github.com/christophe0606/BraidArt")!)
                Spacer()
                Button("Done") { dismissWindow(id:"about") }.keyboardShortcut(.cancelAction)
            }.padding(16)
        }
        .frame(width:650,height:740)
        .sheet(item:$selectedLicense) { LicenseTextView(license:$0) }
    }

    private func noticeRow(_ title: String,detail: String,license: AboutLicense) -> some View {
        HStack {
            VStack(alignment:.leading,spacing:3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Read notice") { selectedLicense=license }.accessibilityLabel("Read \(title) notice")
        }
    }
}

private struct AboutDependency: Identifiable {
    let directory: String
    let name: String
    let version: String
    var id: String { directory }
    var source: URL { URL(string:"https://github.com/coin-or/\(directory)/tree/releases/\(version)")! }
    func document(_ filename: String,title: String,upstreamPath: String? = nil) -> AboutLicense {
        let original=upstreamPath.map { URL(string:"https://github.com/coin-or/\(directory)/blob/releases/\(version)/\($0)")! } ?? source
        return AboutLicense(title:title,resource:"Solver/licenses/\(directory)/\(filename)",repository:"Licenses/\(directory)/\(filename)",origin:original)
    }
    static let projects=[
        AboutDependency(directory:"Cbc",name:"COIN-OR CBC",version:"2.10.13"),
        AboutDependency(directory:"Clp",name:"COIN-OR CLP",version:"1.17.11"),
        AboutDependency(directory:"CoinUtils",name:"COIN-OR CoinUtils",version:"2.11.12"),
        AboutDependency(directory:"Osi",name:"COIN-OR Osi",version:"0.108.11"),
        AboutDependency(directory:"Cgl",name:"COIN-OR Cgl",version:"0.60.9")
    ]
}

private struct AboutLicense: Identifiable {
    let title: String
    let resource: String
    let repository: String
    let origin: URL
    var id: String { resource }
    var localURL: URL? {
        var candidates=[URL]()
        if let resources=Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(resource)) }
        // Also support running the Swift package directly from Xcode.
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(root.appendingPathComponent(repository))
        return candidates.first{FileManager.default.fileExists(atPath:$0.path)}
    }
    static let project=AboutLicense(title:"BraidArt — Apache License 2.0",resource:"LICENSE",repository:"LICENSE",origin:URL(string:"https://www.apache.org/licenses/LICENSE-2.0")!)
    static let notice=AboutLicense(title:"BraidArt — Notice",resource:"NOTICE",repository:"NOTICE",origin:URL(string:"https://github.com/christophe0606/BraidArt")!)
    static let inventory=AboutLicense(title:"Third-party licenses and origins",resource:"Solver/licenses/README.md",repository:"Licenses/README.md",origin:URL(string:"https://github.com/christophe0606/BraidArt/tree/master/Licenses")!)
    static let bison=AboutLicense(title:"Bison — Generated parser notice and exception",resource:"Solver/licenses/Bison/GENERATED-PARSER-NOTICE.txt",repository:"Licenses/Bison/GENERATED-PARSER-NOTICE.txt",origin:URL(string:"https://github.com/coin-or/CoinUtils/blob/releases/2.11.12/CoinUtils/src/CoinModelUseful2.cpp")!)
    static let ampl=AboutLicense(title:"Lucent — AMPL interface notice",resource:"Solver/licenses/Cbc/AMPL-NOTICE.txt",repository:"Licenses/Cbc/AMPL-NOTICE.txt",origin:URL(string:"https://github.com/coin-or/Cbc/blob/releases/2.10.13/Cbc/src/Cbc_ampl.cpp")!)
    static let rational=AboutLicense(title:"CoinUtils — Rational approximation attribution",resource:"Solver/licenses/CoinUtils/RATIONAL-NOTICE.txt",repository:"Licenses/CoinUtils/RATIONAL-NOTICE.txt",origin:URL(string:"https://github.com/coin-or/CoinUtils/blob/releases/2.11.12/CoinUtils/src/CoinRational.cpp")!)
}

private struct LicenseTextView: View {
    @Environment(\.dismiss) private var dismiss
    let license: AboutLicense
    @State private var text=""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(license.title).font(.title2.weight(.semibold))
            ScrollView([.vertical,.horizontal]) {
                Text(text).font(.system(.callout,design:.monospaced)).textSelection(.enabled)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(12)
            }.background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8))
            HStack {
                Link("Original source",destination:license.origin)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width:700,height:580)
        .task(id:license.id) {
            if let url=license.localURL,let contents=try? String(contentsOf:url,encoding:.utf8) { text=contents }
            else { text="This notice could not be opened. Use Original source to view it online." }
        }
    }
}
