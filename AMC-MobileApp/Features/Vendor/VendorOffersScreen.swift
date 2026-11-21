// VendorOffersScreen.swift
// Onglet Lots du portail Vendeur : lots ouverts en cartes, tap pour modifier (V2), « Créer un lot » pour en publier un.
// Lecture via `VendorDashboardViewModel` (lots actifs, parts engagées, palier, revenu prévu).

import SwiftUI

struct VendorOffersScreen: View {
    enum Route: Hashable {
        case create
        case edit(offerId: String)
    }

    private let repositories: AppRepositories
    private let vendorId: String
    @State private var model: VendorDashboardViewModel
    @State private var path: [Route] = []
    @State private var publishedTrigger = 0
    @Namespace private var transition

    init(repositories: AppRepositories = .fake(), vendorId: String = FakeData.ID.fermeRive) {
        self.repositories = repositories
        self.vendorId = vendorId
        _model = State(initialValue: VendorDashboardViewModel(repositories: repositories, vendorId: vendorId))
    }

    var body: some View {
        NavigationStack(path: $path) {
            StateView(
                state: model.state,
                empty: .init(
                    title: "Aucun lot ouvert",
                    systemImage: GrenierSymbol.offers,
                    message: "Crée ton premier lot : fixe tes paliers, les groupes du quartier font baisser le prix."
                ),
                retry: { await model.load() }
            ) { dashboard in
                offerList(dashboard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Lots")
            .profileToolbar()
            .safeAreaInset(edge: .bottom) { createButton }
            .navigationDestination(for: Route.self) { route in
                editor(for: route)
            }
            .task {
                if case .idle = model.state { await model.load() }
            }
            .sensoryFeedback(.success, trigger: publishedTrigger)
        }
    }

    // MARK: Liste

    private func offerList(_ dashboard: VendorDashboardViewModel.Dashboard) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(summaryText(dashboard))
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .padding(.horizontal, 4)

                ForEach(dashboard.offers) { summary in
                    NavigationLink(value: Route.edit(offerId: summary.id)) {
                        VendorOfferCard(summary: summary)
                            .matchedTransitionSource(id: summary.id, in: transition)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre l'éditeur de paliers de ce lot.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.refresh() }
    }

    private func summaryText(_ dashboard: VendorDashboardViewModel.Dashboard) -> String {
        let count = dashboard.offers.count
        let lots = count > 1 ? "lots ouverts" : "lot ouvert"
        return "\(count) \(lots) · \(dashboard.totalCommittedShares) parts engagées sur \(dashboard.totalShares) · revenu prévu \(Money.formatRounded(dashboard.projectedRevenueCents))"
    }

    // MARK: Création

    private var createButton: some View {
        Button {
            path.append(.create)
        } label: {
            Label("Créer un lot", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.glassProminent)
        .tint(.grenier)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityHint("Ouvre l'éditeur de paliers pour un nouveau lot.")
    }

    @ViewBuilder
    private func editor(for route: Route) -> some View {
        switch route {
        case .create:
            TierEditorScreen(repositories: repositories, vendorId: vendorId, onSaved: offerSaved)
        case .edit(let offerId):
            TierEditorScreen(repositories: repositories, vendorId: vendorId, offerId: offerId, onSaved: offerSaved)
                .navigationTransition(.zoom(sourceID: offerId, in: transition))
        }
    }

    private func offerSaved(_ offer: Offer) {
        publishedTrigger += 1
        Task { await model.refresh() }
    }
}

// MARK: - Carte d'un lot (côté vendeur)

/// Un lot ouvert : produit, échéance, palier atteint, barre de paliers, parts engagées et revenu prévu.
private struct VendorOfferCard: View {
    let summary: VendorDashboardViewModel.OfferSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            header {
                if let product = summary.product {
                    ProductIcon(category: product.category)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.title) · \(summary.offer.shareUnit)")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("ferme \(deadlineText)")
                        .font(.subheadline)
                        .foregroundStyle(summary.isClosingSoon ? Color.grenier : Color.texteSecondaire)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                tierBadge
            }

            TierProgressBar(
                tiers: summary.offer.tiers,
                committedShares: summary.committedShares,
                totalShares: summary.totalShares,
                compact: true
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    progressText
                    Spacer()
                    revenueText
                }
                VStack(alignment: .leading, spacing: 4) {
                    progressText
                    revenueText
                }
            }
        }
        .grenierCard()
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tierBadge: some View {
        if let number = summary.bestTierNumber {
            Label("Palier \(number)", systemImage: "checkmark.seal.fill")
                .font(.caption.bold())
                .foregroundStyle(Color.grenier)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.grenier.opacity(0.12), in: .capsule)
        } else {
            Text("\(summary.offer.tiers.count) paliers")
                .font(.caption.bold())
                .foregroundStyle(.texteSecondaire)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.piste, in: .capsule)
        }
    }

    private var progressText: some View {
        let families = summary.committedHouseholds > 1 ? "familles" : "famille"
        return Text("\(summary.committedHouseholds) \(families) · \(summary.committedShares) parts sur \(summary.totalShares)")
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            .monospacedDigit()
    }

    private var revenueText: some View {
        Text(Money.formatRounded(summary.projectedRevenueCents))
            .priceStyle(.priceCompact)
            .foregroundStyle(.texte)
            .accessibilityLabel("Revenu prévu \(Money.formatRounded(summary.projectedRevenueCents))")
    }

    private var deadlineText: String {
        summary.offer.deadline.formatted(.dateTime.weekday(.wide).hour().locale(Locale(identifier: "fr_CA")))
    }
}

#Preview("Clair") {
    VendorOffersScreen()
}

#Preview("Sombre") {
    VendorOffersScreen()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorOffersScreen()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Hors ligne") {
    VendorOffersScreen(repositories: .fake(behavior: .failing(.offline)))
}
