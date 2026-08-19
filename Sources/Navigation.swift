import SwiftUI

// a plain < in every pushed view: the system back gesture competes with the maps'
// panning and gets stuck there
struct BackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Back"))
                }
            }
    }
}

extension View {
    func appBackButton() -> some View { modifier(BackButton()) }
}
