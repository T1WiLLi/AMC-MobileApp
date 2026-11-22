import SwiftUI

/// Navigation du portail Familles, selon les maquettes de claude-samuel (docs/maquettes/DESIGN-SYSTEM.md, « Navigation »).
/// Les fiches de lot (F3, F4) sont poussées dans le NavigationStack de l'onglet, pas dans un onglet à part.
struct FamilyTabView: View {
    enum TabID: Hashable { case home, groups, pickup, impact, search }

    @State private var selection: TabID = .home
    /// Lien d'invitation reçu (B-058) : bascule sur l'onglet Groupes, qui ouvre la feuille « Rejoindre ».
    @Environment(InviteLinkRouter.self) private var inviteLinks: InviteLinkRouter?
    /// Visite guidée de Noisette (FB-19) : chaque étape ouvre son onglet, la bulle passe au-dessus des onglets.
    @State private var tour = GuidedTour.noisette

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
        .onChange(of: inviteLinks?.pendingCode, initial: true) { _, code in
            if code != nil { selection = .groups }
        }
        .overlay { GuidedTourOverlay(.noisette) }
        .onChange(of: tour.currentStep, initial: true) { _, step in
            if let step { selection = Self.tab(for: step.screen) }
        }
        // « Revoir le tutoriel » : la carte d'accueil de Noisette se présente sur l'Accueil.
        .onChange(of: tour.showsWelcome, initial: true) { _, showsWelcome in
            if showsWelcome { selection = .home }
        }
    }

    static func tab(for screen: TourScreen) -> TabID {
        switch screen {
        case .home, .offerDetail: .home
        case .pickup: .pickup
        case .groups: .groups
        case .impact: .impact
        // Écrans du portail Vendeurs : jamais demandés par la visite de Noisette.
        case .vendorDashboard, .vendorOffers, .vendorTierEditor, .vendorDemand, .vendorRevenue: .home
        }
    }
}

#Preview("Clair") {
    FamilyTabView()
}

#Preview("Sombre") {
    FamilyTabView()
        .preferredColorScheme(.dark)
}
