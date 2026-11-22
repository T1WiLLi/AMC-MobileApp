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
        StateView(
            state: model.state,
            empty: .init(
                title: "Aucun groupe pour l'instant",
                systemImage: "person.3.sequence",
                message: "Ici apparaissent les groupes qui veulent ce que tu produis. Ajoute tes disponibilités : quand des familles de tes zones en voudront, leurs groupes s'afficheront."
            ),
            retry: { await model.load() }
        ) { interests in
            InterestList(interests: interests) { interest in
                if let supply = model.targetedSupply(for: interest) { onCreateLot(supply) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Groupes intéressés")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InfoButton(topic: .interestedGroups)
            }
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

/// Liste des groupes : en-tête de section du portail Vendeur puis une carte Grenier par groupe (T-209).
private struct InterestList: View {
    let interests: [InterestedGroupsViewModel.Interest]
    let createLot: (InterestedGroupsViewModel.Interest) -> Void

    private var householdTotal: Int { interests.reduce(0) { $0 + $1.match.householdCount } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    GrenierSectionHeader(String(localized: "Ils veulent tes produits"), systemImage: "person.3.sequence.fill",
                                         font: .title2.bold(), info: .interestedGroups)
                    Text(GroupWishesViewModel.householdsText(householdTotal))
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                ForEach(interests) { interest in
                    InterestCard(interest: interest) { createLot(interest) }
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Carte d'un groupe : identité, zone et ménages, lignes couvertes avec leur barre, puis « Créer un lot ciblé ».
private struct InterestCard: View {
    let interest: InterestedGroupsViewModel.Interest
    let createLot: () -> Void

    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(interest.match.lines, id: \.self) { line in
                    LineRow(line: line)
                }
            }
            Button(action: createLot) {
                Label("Créer un lot ciblé", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.grenier)
        }
        .grenierCard()
        .contextMenu {
            Button(action: createLot) {
                Label("Créer un lot ciblé", systemImage: "scope")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: interest.group.resolvedBranding.emblem)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .grenierIconTile(.grenier, side: min(iconSide, 72), cornerRadius: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(interest.group.resolvedBranding.displayName)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Label(MontrealNeighborhood.displayName(for: interest.group.neighborhood), systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                Label(GroupWishesViewModel.householdsText(interest.match.householdCount), systemImage: "house.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Une catégorie demandée : ce que je peux servir sur ce que le groupe veut, et la part couverte.
private struct LineRow: View {
    let line: Matcher.Line

    private var tint: Color { line.isPartial ? .orange : .economie }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(line.category.title)
                        .foregroundStyle(.texte)
                } icon: {
                    Image(systemName: ProductIcon.symbol(for: line.category))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                .font(.subheadline)
                Spacer(minLength: 8)
                Text("\(GroupWishesViewModel.quantityText(line.matchedQuantity, unit: line.unit)) sur \(GroupWishesViewModel.quantityText(line.wantedQuantity, unit: line.unit))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(tint)
            }
            ProgressView(value: min(max(line.coverage, 0), 1))
                .tint(tint)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
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
                        model.hasNoWish ? String(localized: "Dis ce que tu veux") : String(localized: "Pas encore d'offre"),
                        systemImage: model.hasNoWish ? "basket" : "sparkle.magnifyingglass",
                        description: Text(model.hasNoWish
                            ? String(localized: "Ajoute une envie dans « Ce que le groupe veut » : les offres qui y répondent apparaîtront ici.")
                            : String(localized: "Aucun lot du quartier ne répond encore à tes envies. Les producteurs voient la demande du groupe."))
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
