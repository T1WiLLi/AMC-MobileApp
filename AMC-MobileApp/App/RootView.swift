import SwiftUI

/// Point d'entrée de l'interface. B-020 y branchera la navigation par portail (Familles / Vendeurs).
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Grenier",
            systemImage: "basket.fill",
            description: Text("Le garde-manger du quartier.")
        )
    }
}

#Preview("Clair") {
    RootView()
}

#Preview("Sombre") {
    RootView()
        .preferredColorScheme(.dark)
}
