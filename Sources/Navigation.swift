import SwiftUI

// ett tydligt < i varje pushad vy: systemets bakåtknapp konkurrerar med
// kartornas panorering och svepgesten fastnar där
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
    func mateBackButton() -> some View { modifier(BackButton()) }
}
