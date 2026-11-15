import BraidCore
import SwiftUI

@MainActor
final class ExportProgress: ObservableObject, Identifiable {
    let id=UUID()
    let title:String
    let filename:String
    @Published var progress=0.0
    @Published var message:String
    @Published var cancelling=false

    init(title:String,filename:String,message:String) { self.title=title;self.filename=filename;self.message=message }
}

struct ExportProgressView: View {
    @ObservedObject var export:ExportProgress
    let cancel:()->Void

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(export.title).font(.headline)
            Text(export.filename).foregroundStyle(.secondary).lineLimit(2)
            ProgressView(value:export.progress).tint(.orange)
            HStack {
                Text(export.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(export.progress,format:.percent.precision(.fractionLength(0))).font(.caption.monospacedDigit())
            }
            HStack {
                Spacer()
                Button(export.cancelling ? L("Cancelling…") : L("Cancel"),role:.cancel,action:cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(export.cancelling)
            }
        }
        .padding(24)
        .frame(width:420)
        .interactiveDismissDisabled()
    }
}
