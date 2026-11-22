import SwiftUI

/// Onglet Recherche du portail Organismes (T-116) : un groupe ou un quartier, puis Financer.
struct OrganizationSearchScreen: View {
    let model: OrganizationPortalModel?

    @State private var query = ""
    @State private var donationTarget: GroupSolidarityProfile?

    var body: some View {
        NavigationStack {
            OrganizationStateContainer(model: model) { model, _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.searchResults.isEmpty {
                            EmptyStateView(title: "Aucun groupe trouvé", systemImage: "magnifyingglass",
                                           message: "Cherche un quartier pour trouver les groupes qui ont besoin d'aide et les financer. Essaie un autre nom de quartier.")
                        }
                        ForEach(model.searchResults) { profile in
                            GroupNeedCard(profile: profile, distance: model.distanceText(for: profile),
                                          isSponsored: profile.isSponsored(by: model.organizationId)) {
                                Button {
                                    donationTarget = profile
                                } label: {
                                    Label("Financer", systemImage: "heart.fill")
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.glass)
                                .tint(.grenier)
                            }
                        }
                    }
                    .padding(16)
                }
                .searchable(text: $query, prompt: "Groupe ou quartier")
                .searchSuggestions {
                    ForEach(model.neighborhoodSuggestions, id: \.self) { slug in
                        let name = MontrealNeighborhood.displayName(for: slug)
                        Label(name, systemImage: "mappin.and.ellipse").searchCompletion(name)
                    }
                }
                .onChange(of: query, initial: true) { _, text in model.searchText = text }
                // T-208 : toucher un groupe ouvre sa fiche publique.
                .organizationGroupDestination(model: model)
                .sheet(item: $donationTarget) { profile in
                    DonationSheet(model: model, groupId: profile.groupId)
                }
            }
            .grenierBackground()
            .navigationTitle("Rechercher")
        }
    }
}

#Preview("Clair") {
    let model = OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    OrganizationSearchScreen(model: model)
        .task { await model.load() }
}
