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
                    .grenierTabContent(isSelected: selection == .home)
            }
            Tab("Groupes", systemImage: "person.3.fill", value: .groups) {
                GroupsScreen()
                    .grenierTabContent(isSelected: selection == .groups)
            }
            Tab("Cueillette", systemImage: "qrcode", value: .pickup) {
                PickupScreen()
                    .grenierTabContent(isSelected: selection == .pickup)
            }
            Tab("Impact", systemImage: "leaf.fill", value: .impact) {
                ImpactScreen()
                    .grenierTabContent(isSelected: selection == .impact)
            }
            Tab(value: .search, role: .search) {
                SearchScreen(prompt: "Riz, pommes, producteur…", linksToOffers: true)
            }
        }
        // Bord net sous la barre de navigation pour tous les onglets et leurs fiches (T-140).
        .grenierScrollEdge()
    }
}

#Preview("Clair") {
    FamilyTabView()
}

#Preview("Sombre") {
    FamilyTabView()
        .preferredColorScheme(.dark)
}
