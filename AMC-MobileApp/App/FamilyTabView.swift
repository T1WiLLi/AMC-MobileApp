import SwiftUI

/// Navigation du portail Familles (section « Écrans » de Requis).
struct FamilyTabView: View {
    enum TabID: Hashable { case home, groups, offers, cart, search }

    @State private var selection: TabID = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house.fill", value: .home) {
                FamilyHomeScreen()
            }
            Tab("Groupes", systemImage: "person.3.fill", value: .groups) {
                GroupsScreen()
            }
            Tab("Lots", systemImage: "shippingbox.fill", value: .offers) {
                OffersScreen()
            }
            Tab("Panier", systemImage: "basket.fill", value: .cart) {
                CartScreen()
            }
            Tab(value: .search, role: .search) {
                SearchScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview("Clair") {
    FamilyTabView()
}

#Preview("Sombre") {
    FamilyTabView()
        .preferredColorScheme(.dark)
}
