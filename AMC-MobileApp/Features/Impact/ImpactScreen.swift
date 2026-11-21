import SwiftUI

struct ImpactScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Impact",
            systemImage: "leaf.fill",
            message: "Tes économies et l'impact de ton quartier sur Montréal."
        )
    }
}

#Preview("Clair") {
    ImpactScreen()
}

#Preview("Sombre") {
    ImpactScreen()
        .preferredColorScheme(.dark)
}
