import SwiftUI

/// Navigation du portail Familles, selon les maquettes de claude-samuel (docs/maquettes/DESIGN-SYSTEM.md, « Navigation »).
/// Les fiches de lot (F3, F4) sont poussées dans le NavigationStack de l'onglet, pas dans un onglet à part.
struct FamilyTabView: View {
    enum TabID: Hashable { case home, groups, pickup, impact, search }

    @State private var selection: TabID = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house.fill", value: .home) {
                FamilyHomeScreen()
            }
            Tab("Groupes", systemImage: "person.3.fill", value: .groups) {
                GroupsScreen()
            }
            Tab("Cueillette", systemImage: "qrcode", value: .pickup) {
                PickupScreen()
            }
            Tab("Impact", systemImage: "leaf.fill", value: .impact) {
                ImpactScreen()
            }
            Tab(value: .search, role: .search) {
                SearchScreen(linksToOffers: true)
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
