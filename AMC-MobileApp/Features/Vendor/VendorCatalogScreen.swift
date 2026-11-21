import SwiftUI

struct VendorCatalogScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Catalogue",
            systemImage: "tag.fill",
            message: "Tes produits et tes lots à prix dégressifs.",
            epic: "E04"
        )
    }
}

#Preview("Clair") {
    VendorCatalogScreen()
}

#Preview("Sombre") {
    VendorCatalogScreen()
        .preferredColorScheme(.dark)
}
