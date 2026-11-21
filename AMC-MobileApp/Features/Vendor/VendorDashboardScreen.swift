import SwiftUI

struct VendorDashboardScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Tableau",
            systemImage: "house.fill",
            message: "Tes ventes de la semaine, les familles servies et les paliers atteints (maquette V1).",
            epic: "E09"
        )
    }
}

#Preview("Clair") {
    VendorDashboardScreen()
}

#Preview("Sombre") {
    VendorDashboardScreen()
        .preferredColorScheme(.dark)
}
