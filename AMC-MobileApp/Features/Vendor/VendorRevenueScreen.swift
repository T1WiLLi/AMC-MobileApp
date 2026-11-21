import SwiftUI

struct VendorRevenueScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Revenus",
            systemImage: "dollarsign.circle.fill",
            message: "Tes ventes par lot et par quartier, et tes livraisons à venir."
        )
    }
}

#Preview("Clair") {
    VendorRevenueScreen()
}

#Preview("Sombre") {
    VendorRevenueScreen()
        .preferredColorScheme(.dark)
}
