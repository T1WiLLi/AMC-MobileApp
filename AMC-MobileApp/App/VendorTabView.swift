import SwiftUI

/// Navigation du portail Vendeurs, selon les maquettes V1–V3 de claude-samuel (docs/maquettes/DESIGN-SYSTEM.md).
/// L'éditeur de paliers (V2) est poussé depuis Tableau ou Lots, pas dans un onglet.
struct VendorTabView: View {
    enum TabID: Hashable { case dashboard, offers, demand, revenue, search }

    @State private var selection: TabID = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            Tab("Tableau", systemImage: "house.fill", value: .dashboard) {
                VendorDashboardScreen()
            }
            Tab("Lots", systemImage: "shippingbox.fill", value: .offers) {
                VendorOffersScreen()
            }
            Tab("Demande", systemImage: "map.fill", value: .demand) {
                VendorDemandMapScreen()
            }
            Tab("Revenus", systemImage: "dollarsign.circle.fill", value: .revenue) {
                VendorRevenueScreen()
            }
            Tab(value: .search, role: .search) {
                SearchScreen(
                    prompt: "Produit ou quartier",
                    emptyTitle: "Chercher la demande",
                    emptyMessage: "Un produit ou un quartier : vois quels groupes le veulent."
                )
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview("Clair") {
    VendorTabView()
}

#Preview("Sombre") {
    VendorTabView()
        .preferredColorScheme(.dark)
}
