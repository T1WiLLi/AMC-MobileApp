import SwiftUI

struct ImpactScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Impact",
            systemImage: "leaf.fill",
            message: "Tes économies et l'impact de ton quartier sur Montréal (maquette F6).",
            epic: "E12"
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
