import SwiftUI

/// Navigation du portail Vendeurs, selon les maquettes V1–V3 de claude-samuel (docs/maquettes/DESIGN-SYSTEM.md).
/// L'éditeur de paliers (V2) est poussé depuis Tableau ou Lots, pas dans un onglet.
///
/// T-129 : dépôts et vendeur viennent de `appContext` (session), jamais de `FakeData`.
/// Sans profil producteur (`vendorId` vide), chaque onglet affiche `VendorProfileMissingView`.
/// `.id(vendorId)` recrée les écrans et leurs ViewModels quand la session relie un autre vendeur.
struct VendorTabView: View {
    enum TabID: Hashable { case dashboard, offers, demand, revenue, search }

    @Environment(\.appContext) private var context
    @State private var selection: TabID = .dashboard
    /// Visite guidée de Racoonette : chaque étape ouvre son onglet, la bulle passe au-dessus des onglets.
    @State private var tour = GuidedTour.racoonette

    private var vendorId: String { context.vendorId.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasVendorProfile: Bool { !vendorId.isEmpty }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Tableau", systemImage: "house.fill", value: .dashboard) {
                vendorContent(title: "Tableau") {
                    VendorDashboardScreen(repositories: context.repositories, vendorId: vendorId)
                }
                .grenierTabContent(isSelected: selection == .dashboard)
            }
            Tab("Lots", systemImage: "shippingbox.fill", value: .offers) {
                vendorContent(title: "Lots") {
                    VendorOffersScreen(repositories: context.repositories, vendorId: vendorId, userId: context.userId)
                }
                .grenierTabContent(isSelected: selection == .offers)
            }
            Tab("Demande", systemImage: "map.fill", value: .demand) {
                vendorContent(title: "Demande") {
                    VendorDemandMapScreen(repositories: context.repositories, vendorId: vendorId)
                }
                .grenierTabContent(isSelected: selection == .demand)
            }
            Tab("Revenus", systemImage: "dollarsign.circle.fill", value: .revenue) {
                vendorContent(title: "Revenus") {
                    VendorRevenueScreen(repositories: context.repositories, vendorId: vendorId)
                }
                .grenierTabContent(isSelected: selection == .revenue)
            }
            Tab(value: .search, role: .search) {
                vendorContent(title: "Recherche") {
                    VendorSearchScreen(repositories: context.repositories, vendorId: vendorId)
                }
            }
        }
        // Bord net sous la barre de navigation pour tous les onglets et leurs fiches (T-140).
        .grenierScrollEdge()
        .overlay { GuidedTourOverlay(.racoonette) }
        .onChange(of: tour.currentStep, initial: true) { _, step in
            if let step { selection = Self.tab(for: step.screen) }
        }
        // « Revoir le tutoriel » : la carte d'accueil de Racoonette se présente sur le Tableau.
        .onChange(of: tour.showsWelcome, initial: true) { _, showsWelcome in
            if showsWelcome { selection = .dashboard }
        }
    }

    static func tab(for screen: TourScreen) -> TabID {
        switch screen {
        case .vendorDashboard: .dashboard
        case .vendorOffers, .vendorTierEditor: .offers
        case .vendorDemand: .demand
        case .vendorRevenue: .revenue
        // Écrans du portail Familles : jamais demandés par la visite de Racoonette.
        case .home, .offerDetail, .groups, .pickup, .impact: .dashboard
        }
    }

    @ViewBuilder
    private func vendorContent(title: LocalizedStringKey, @ViewBuilder screen: () -> some View) -> some View {
        if hasVendorProfile {
            screen().id(vendorId)
        } else {
            VendorProfileMissingView(title: title)
        }
    }
}

#Preview("Clair") {
    VendorTabView()
        .environment(\.appContext, .demo)
}

#Preview("Sombre") {
    VendorTabView()
        .environment(\.appContext, .demo)
        .preferredColorScheme(.dark)
}

#Preview("Sans profil producteur") {
    var context = AppContext.demo
    context.vendorId = ""
    return VendorTabView()
        .environment(\.appContext, context)
}
