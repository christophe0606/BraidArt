import SwiftUI
import BraidCore

struct MobileInfoView:View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var navigation=HelpNavigation()
    var body:some View {
        NavigationStack {
            HelpView(navigation:navigation)
                .navigationTitle(L("BraidArt Help"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.confirmationAction) {
                        Button(L("Done")) { dismiss() }.accessibilityIdentifier("closeHelp")
                    }
                    ToolbarItem(placement:.bottomBar) {
                        NavigationLink(L("Third-party licenses and origins")) { ThirdPartyCreditsView() }
                            .accessibilityIdentifier("thirdPartyCreditsLink")
                    }
                }
        }
    }
}
