import SwiftUI

struct FamilyHomeScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Accueil",
            systemImage: "house.fill",
            message: "Tes commandes en cours et tes économies du mois.",
            epic: "E05, E12"
        )
    }
}

#Preview("Clair") {
    FamilyHomeScreen()
}

#Preview("Sombre") {
    FamilyHomeScreen()
        .preferredColorScheme(.dark)
}
