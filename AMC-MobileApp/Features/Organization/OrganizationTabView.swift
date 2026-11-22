import SwiftUI

/// Navigation du portail Organismes (T-116, RQ-081) : Tableau, Financer, Parrainages, Impact + Recherche.
/// Un seul `OrganizationPortalModel` partagé : un panier financé dans un onglet se voit dans tous les autres.
struct OrganizationTabView: View {
    enum TabID: Hashable { case dashboard, fund, sponsorships, impact, search }

    @Environment(\.appContext) private var context
    @State private var selection: TabID = .dashboard
    @State private var model: OrganizationPortalModel?

    var body: some View {
        TabView(selection: $selection) {
            Tab("Tableau", systemImage: "chart.bar.doc.horizontal.fill", value: .dashboard) {
                OrganizationDashboardScreen(model: model) { selection = .fund }
                    .grenierTabContent(isSelected: selection == .dashboard)
            }
            Tab("Financer", systemImage: "heart.circle.fill", value: .fund) {
                OrganizationFundScreen(model: model)
                    .grenierTabContent(isSelected: selection == .fund)
            }
            Tab("Parrainages", systemImage: "hands.and.sparkles.fill", value: .sponsorships) {
                OrganizationSponsorshipsScreen(model: model)
                    .grenierTabContent(isSelected: selection == .sponsorships)
            }
            Tab("Impact", systemImage: "leaf.fill", value: .impact) {
                OrganizationImpactScreen(model: model)
                    .grenierTabContent(isSelected: selection == .impact)
            }
            Tab(value: .search, role: .search) {
                OrganizationSearchScreen(model: model)
            }
        }
        .grenierHaptic(.selection, trigger: selection)
        .task {
            let model = self.model ?? OrganizationPortalModel(
                repository: context.repositories.organizations, groups: context.repositories.groups,
                organizationId: context.organizationId
            )
            self.model = model
            await model.loadIfNeeded()
        }
    }
}

#Preview("Clair") {
    OrganizationTabView()
}

#Preview("Sombre") {
    OrganizationTabView()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    OrganizationTabView()
        .dynamicTypeSize(.accessibility5)
}
