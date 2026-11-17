import SwiftUI
import BraidCore
#if os(macOS)
import AppKit
#endif

/// Third-party notices only, shared by the desktop About window and mobile Help.
struct ThirdPartyCreditsView:View {
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HelpIllustrationCredits()
                Divider()
                ThirdPartyLibrariesView()
            }.padding(24)
        }.navigationTitle(L("Third-party licenses and origins"))
            .accessibilityIdentifier("thirdPartyCredits")
    }
}

struct ThirdPartyLibrariesView:View {
    @State private var selectedLicense:ThirdPartyNotice?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L("Included projects")).font(.headline)
            Text(L("Each project retains its own licenses. Original license texts, author notices and source references are included with the app."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            ForEach(ThirdPartyDependency.projects) { project in
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(L("%@ %@", String(describing: project.name), String(describing: project.version))).font(.callout.weight(.medium))
                        Text(L("EPL 2.0 (release) · EPL 1.0 (library)")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(L("Source"),destination:project.source)
                        .accessibilityIdentifier("thirdPartySource-\(project.directory)")
                    Menu(L("Licenses")) {
                        Button(L("EPL 2.0 — release license")) { selectedLicense=project.document("LICENSE",title:L("%@ — EPL 2.0", String(describing: project.name)),upstreamPath:"LICENSE") }
                        Button(L("EPL 1.0 — library license")) { selectedLicense=project.document("LIBRARY-LICENSE",title:L("%@ — EPL 1.0", String(describing: project.name)),upstreamPath:"\(project.directory)/LICENSE") }
                        Button(L("Authors")) { selectedLicense=project.document("AUTHORS",title:L("%@ — Authors", String(describing: project.name)),upstreamPath:"\(project.directory)/AUTHORS") }
                        Button(L("Origin and source archive")) { selectedLicense=project.document("ORIGIN.md",title:L("%@ — Origin", String(describing: project.name))) }
                    }
                    .fixedSize()
                    .accessibilityLabel(L("Licenses for %@", String(describing: project.name)))
                    .accessibilityIdentifier("thirdPartyLicenses-\(project.directory)")
                }
            }
            DisclosureGroup(L("Additional notices")) {
                VStack(alignment:.leading,spacing:10) {
                    noticeRow(L("Bison-generated parser"),detail:L("GPL v2 or later with the upstream output exception"),license:.bison)
                    noticeRow(L("Lucent AMPL interface"),detail:L("Original permission and copyright notices"),license:.ampl)
                    noticeRow(L("Rational approximation"),detail:L("CoinUtils attribution and EPL 1.0 notice"),license:.rational)
                    noticeRow(L("CIEDE2000 reference data"),detail:L("Gaurav Sharma, Wencheng Wu and Edul N. Dalal"),license:.ciede)
                }.padding(.top,10)
            }.font(.callout)
            HStack {
                Button(L("All third-party notices")) { selectedLicense = .inventory }
                #if os(macOS)
                Button(L("Show license files")) {
                    if let folder=ThirdPartyNotice.inventory.localURL?.deletingLastPathComponent() { NSWorkspace.shared.open(folder) }
                }.disabled(ThirdPartyNotice.inventory.localURL == nil)
                #endif
            }
        }
        .sheet(item:$selectedLicense) { ThirdPartyNoticeView(license:$0) }
    }
    private func noticeRow(_ title: String,detail: String,license: ThirdPartyNotice) -> some View {
        HStack {
            VStack(alignment:.leading,spacing:3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Read notice")) { selectedLicense=license }.accessibilityLabel(L("Read %@ notice", String(describing: title)))
        }
    }
}

struct ThirdPartyDependency: Identifiable {
    let directory: String
    let name: String
    let version: String
    var id: String { directory }
    var source: URL { URL(string:"https://github.com/coin-or/\(directory)/tree/releases/\(version)")! }
    func document(_ filename: String,title: String,upstreamPath: String? = nil) -> ThirdPartyNotice {
        let original=upstreamPath.map { URL(string:"https://github.com/coin-or/\(directory)/blob/releases/\(version)/\($0)")! } ?? source
        return ThirdPartyNotice(title:title,resource:"Solver/licenses/\(directory)/\(filename)",repository:"Licenses/\(directory)/\(filename)",origin:original)
    }
    static let projects=[
        ThirdPartyDependency(directory:"Cbc",name:"COIN-OR CBC",version:"2.10.13"),
        ThirdPartyDependency(directory:"Clp",name:"COIN-OR CLP",version:"1.17.11"),
        ThirdPartyDependency(directory:"CoinUtils",name:"COIN-OR CoinUtils",version:"2.11.12"),
        ThirdPartyDependency(directory:"Osi",name:"COIN-OR Osi",version:"0.108.11"),
        ThirdPartyDependency(directory:"Cgl",name:"COIN-OR Cgl",version:"0.60.9")
    ]
}

struct ThirdPartyNotice: Identifiable {
    let title: String
    let resource: String
    let repository: String
    let origin: URL?
    var id: String { resource }
    var localURL: URL? {
        var candidates=[URL]()
        if let resources=Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(resource)) }
        // Also support running the Swift package directly from Xcode.
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(root.appendingPathComponent(repository))
        return candidates.first{FileManager.default.fileExists(atPath:$0.path)}
    }
    static let inventory=ThirdPartyNotice(title:L("Third-party licenses and origins"),resource:"Solver/licenses/README.md",repository:"Licenses/README.md",origin:nil)
    static let ciede=ThirdPartyNotice(title:L("CIEDE2000 reference data"),resource:"Solver/licenses/README.md",repository:"Licenses/README.md",origin:URL(string:"https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/")!)
    static let bison=ThirdPartyNotice(title:L("Bison — Generated parser notice and exception"),resource:"Solver/licenses/Bison/GENERATED-PARSER-NOTICE.txt",repository:"Licenses/Bison/GENERATED-PARSER-NOTICE.txt",origin:URL(string:"https://github.com/coin-or/CoinUtils/blob/releases/2.11.12/CoinUtils/src/CoinModelUseful2.cpp")!)
    static let ampl=ThirdPartyNotice(title:L("Lucent — AMPL interface notice"),resource:"Solver/licenses/Cbc/AMPL-NOTICE.txt",repository:"Licenses/Cbc/AMPL-NOTICE.txt",origin:URL(string:"https://github.com/coin-or/Cbc/blob/releases/2.10.13/Cbc/src/Cbc_ampl.cpp")!)
    static let rational=ThirdPartyNotice(title:L("CoinUtils — Rational approximation attribution"),resource:"Solver/licenses/CoinUtils/RATIONAL-NOTICE.txt",repository:"Licenses/CoinUtils/RATIONAL-NOTICE.txt",origin:URL(string:"https://github.com/coin-or/CoinUtils/blob/releases/2.11.12/CoinUtils/src/CoinRational.cpp")!)
}

private struct ThirdPartyNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    let license: ThirdPartyNotice
    @State private var text=""
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(license.title).font(.title2.weight(.semibold))
            ScrollView([.vertical,.horizontal]) {
                Text(text).font(.system(.callout,design:.monospaced)).textSelection(.enabled)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(12)
            }.background(.background,in:RoundedRectangle(cornerRadius:8))
            HStack {
                if let origin=license.origin {
                    Link(L("Original source"),destination:origin).accessibilityIdentifier("thirdPartyOriginalSource")
                }
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width:700,height:580)
        #else
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        #endif
        .task(id:license.id) {
            if let url=license.localURL,let contents=try? String(contentsOf:url,encoding:.utf8) { text=contents }
            else { text=L("This notice could not be opened. Use Original source to view it online.") }
        }
    }
}
