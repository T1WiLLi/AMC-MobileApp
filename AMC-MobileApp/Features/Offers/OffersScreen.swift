import SwiftUI

struct OffersScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Lots",
            systemImage: "shippingbox.fill",
            message: "Les lots des producteurs, avec leurs prix par palier.",
            epic: "E05"
        )
    }
}

#Preview("Clair") {
    OffersScreen()
}

#Preview("Sombre") {
    OffersScreen()
        .preferredColorScheme(.dark)
}
