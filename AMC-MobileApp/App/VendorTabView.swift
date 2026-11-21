import SwiftUI

/// Navigation du portail Vendeurs (section « Écrans » de Requis).
struct VendorTabView: View {
    enum TabID: Hashable { case dashboard, catalog, demand, deliveries }

    @State private var selection: TabID = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            Tab("Tableau de bord", systemImage: "chart.bar.fill", value: .dashboard) {
                VendorDashboardScreen()
            }
            Tab("Catalogue", systemImage: "tag.fill", value: .catalog) {
                VendorCatalogScreen()
            }
            Tab("Demande", systemImage: "map.fill", value: .demand) {
                VendorDemandMapScreen()
            }
            Tab("Livraisons", systemImage: "truck.box.fill", value: .deliveries) {
                VendorDeliveriesScreen()
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
