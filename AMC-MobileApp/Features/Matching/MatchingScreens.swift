import SwiftUI

// S-09 Mise en relation familles ↔ producteurs (T-110).

// MARK: - Vendeur : groupes intéressés

/// « Groupes intéressés » : les groupes dont les envies rencontrent mes disponibilités (Matcher).
/// Poussée depuis « Mes disponibilités » ; « Créer un lot ciblé » ouvre le TierEditor prérempli sur la zone du groupe.
struct InterestedGroupsScreen: View {
    let onCreateLot: (VendorSupply) -> Void

    @State private var model: InterestedGroupsViewModel

    init(repositories: AppRepositories, vendorId: String, onCreateLot: @escaping (VendorSupply) -> Void) {
        _model = State(initialValue: InterestedGroupsViewModel(repositories: repositories, vendorId: vendorId))
        self.onCreateLot = onCreateLot
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Groupes intéressés")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.load() }
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Recherche des groupes…")
        case .empty:
            ContentUnavailableView(
                "Aucun groupe pour l'instant",
                systemImage: "person.3.sequence",
                description: Text("Quand des familles de tes zones voudront ce que tu as, leurs groupes apparaîtront ici.")
            )
        case .failed, .loaded:
            StateView(state: model.state, retry: { await model.load() }) { interests in
                List(interests) { interest in
                    InterestRow(interest: interest) {
                        if let supply = model.targetedSupply(for: interest) { onCreateLot(supply) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct InterestRow: View {
    let interest: InterestedGroupsViewModel.Interest
    let createLot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(interest.group.resolvedBranding.displayName).font(.headline)
                } icon: {
                    Image(systemName: interest.group.resolvedBranding.emblem)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                Label("\(interest.group.neighborhood) · \(GroupWishesViewModel.householdsText(interest.match.householdCount))",
                      systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            ForEach(interest.match.lines, id: \.self) { line in
                HStack {
                    Label(line.category.title, systemImage: ProductIcon.symbol(for: line.category))
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text("\(GroupWishesViewModel.quantityText(line.matchedQuantity, unit: line.unit)) sur \(GroupWishesViewModel.quantityText(line.wantedQuantity, unit: line.unit))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(line.isPartial ? Color.orange : Color.economie)
                }
            }
            .accessibilityElement(children: .combine)
            Button(action: createLot) {
                Label("Créer un lot ciblé", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Famille : offres qui correspondent

/// « Offres qui correspondent à vos souhaits » : lots actifs du quartier dans les catégories que ma famille veut.
/// Poussée depuis « Ce que le groupe veut » ; chaque lot ouvre sa fiche (`OfferRoute`).
struct MatchingOffersScreen: View {
    let groupId: String

    @Environment(\.appContext) private var context
    @State private var model: MatchingOffersViewModel?

    var body: some View {
        Group {
            if let model {
                switch model.state {
                case .idle, .loading:
                    ProgressView("Recherche des offres…")
                case .empty:
                    ContentUnavailableView(
                        model.hasNoWish ? "Dis ce que tu veux" : "Pas encore d'offre",
                        systemImage: model.hasNoWish ? "basket" : "sparkle.magnifyingglass",
                        description: Text(model.hasNoWish
                            ? "Ajoute une envie dans « Ce que le groupe veut » : les offres qui y répondent apparaîtront ici."
                            : "Aucun lot du quartier ne répond encore à tes envies. Les producteurs voient la demande du groupe.")
                    )
                case .failed, .loaded:
                    StateView(state: model.state, retry: { await model.load() }) { items in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(items) { item in
                                    NavigationLink(value: OfferRoute(offerId: item.offer.id)) {
                                        OfferCard(offer: item.offer, product: item.product, vendor: item.vendor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Offres pour toi")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model?.load() }
        .task {
            if model == nil {
                model = MatchingOffersViewModel(repositories: context.repositories, groupId: groupId,
                                                householdId: context.householdId)
            }
            await model?.load()
        }
    }
}

#Preview("Groupes intéressés") {
    NavigationStack {
        InterestedGroupsScreen(repositories: .fake(behavior: .instant), vendorId: FakeData.ID.fermeRive) { _ in }
    }
}

#Preview("Offres pour toi — sombre") {
    NavigationStack {
        MatchingOffersScreen(groupId: FakeData.ID.saintMichel)
            .offerDestination()
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}
