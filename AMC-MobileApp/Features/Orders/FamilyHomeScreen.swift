import SwiftUI

struct FamilyHomeScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Accueil",
            systemImage: "house.fill",
            message: "Tes commandes en cours, ta part et tes économies du mois."
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
