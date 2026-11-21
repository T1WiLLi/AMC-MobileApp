import SwiftUI

struct VendorDemandMapScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Demande",
            systemImage: "map.fill",
            message: "Où sont les groupes et ce qu'ils veulent.",
            epic: "E09"
        )
    }
}

#Preview("Clair") {
    VendorDemandMapScreen()
}

#Preview("Sombre") {
    VendorDemandMapScreen()
        .preferredColorScheme(.dark)
}
