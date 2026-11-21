import SwiftUI

struct VendorOffersScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Lots",
            systemImage: "shippingbox.fill",
            message: "Tes lots ouverts et leurs paliers ; crée un lot avec l'éditeur de paliers (maquette V2).",
            epic: "E04"
        )
    }
}

#Preview("Clair") {
    VendorOffersScreen()
}

#Preview("Sombre") {
    VendorOffersScreen()
        .preferredColorScheme(.dark)
}
