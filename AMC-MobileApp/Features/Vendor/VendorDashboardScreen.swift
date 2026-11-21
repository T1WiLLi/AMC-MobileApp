import SwiftUI

struct VendorDashboardScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Tableau de bord",
            systemImage: "chart.bar.fill",
            message: "Tes lots actifs, les familles engagées et tes revenus prévus.",
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
