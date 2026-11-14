import SwiftUI

@MainActor
final class PDFExportProgress: ObservableObject, Identifiable {
    let id=UUID()
    let filename:String
    @Published var progress=0.0
    @Published var message="Preparing vector PDF…"
    @Published var cancelling=false

    init(filename:String) { self.filename=filename }
}

struct PDFExportView: View {
    @ObservedObject var export:PDFExportProgress
    let cancel:()->Void

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Exporting PDF").font(.headline)
            Text(export.filename).foregroundStyle(.secondary).lineLimit(2)
            ProgressView(value:export.progress).tint(.orange)
            HStack {
                Text(export.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(export.progress,format:.percent.precision(.fractionLength(0))).font(.caption.monospacedDigit())
            }
            HStack {
                Spacer()
                Button(export.cancelling ? "Cancelling…" : "Cancel",role:.cancel,action:cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(export.cancelling)
            }
        }
        .padding(24)
        .frame(width:420)
        .interactiveDismissDisabled()
    }
}
