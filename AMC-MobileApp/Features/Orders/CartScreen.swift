import SwiftUI

struct CartScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Panier",
            systemImage: "basket.fill",
            message: "Tes parts dans les commandes groupées et le total estimé.",
            epic: "E05, E07"
        )
    }
}

#Preview("Clair") {
    CartScreen()
}

#Preview("Sombre") {
    CartScreen()
        .preferredColorScheme(.dark)
}
