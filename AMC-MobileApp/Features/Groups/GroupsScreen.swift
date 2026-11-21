import SwiftUI

struct GroupsScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Groupes",
            systemImage: "person.3.fill",
            message: "Les groupes d'achat de ton quartier, sur la carte et en liste."
        )
    }
}

#Preview("Clair") {
    GroupsScreen()
}

#Preview("Sombre") {
    GroupsScreen()
        .preferredColorScheme(.dark)
}
