import SwiftUI

struct VendorDeliveriesScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Livraisons",
            systemImage: "truck.box.fill",
            message: "Tes livraisons consolidées par point de cueillette.",
            epic: "E09"
        )
    }
}

#Preview("Clair") {
    VendorDeliveriesScreen()
}

#Preview("Sombre") {
    VendorDeliveriesScreen()
        .preferredColorScheme(.dark)
}
