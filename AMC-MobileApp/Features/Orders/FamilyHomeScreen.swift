import SwiftUI

/// F1 Accueil d'une famille (maquette `docs/maquettes/F1-accueil.png`) :
/// « Bonjour Amina », économies, commandes en cours du groupe, nouveaux lots près de chez toi.
struct FamilyHomeScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: FamilyHomeViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    StateView(
                        state: viewModel.state,
                        empty: .init(title: "Rien pour l'instant", systemImage: "house",
                                     message: "Reviens un peu plus tard."),
                        retry: { await viewModel.load() }
                    ) { content in
                        FamilyHomeContent(content: content)
                    }
                } else if context.groupId == nil {
                    NoGroupView()
                } else {
                    ProgressView("Chargement…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .grenierBackground()
            .navigationTitle(title)
            .profileToolbar()
            .offerDestination()
            .refreshable { await viewModel?.load() }
        }
        // Retour au premier plan ou du réseau : `load()` garde le contenu affiché pendant le rechargement.
        .refreshOnForeground { await viewModel?.load() }
        .task {
            guard viewModel == nil, let groupId = context.groupId else { return }
            let model = FamilyHomeViewModel(
                repositories: context.repositories,
                userId: context.userId,
                householdId: context.householdId,
                groupId: groupId
            )
            viewModel = model
            await model.load()
        }
    }

    private var title: String {
        if let firstName = viewModel?.state.value?.firstName { return "Bonjour \(firstName)" }
        return "Accueil"
    }
}

// MARK: - Contenu

private struct FamilyHomeContent: View {
    let content: FamilyHomeViewModel.Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(content.group.name)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -12)

                SavingsCard(savedCents: content.savedCents, orderCount: content.myOrders.count)

                currentOrdersSection

                newOffersSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: Commandes en cours

    @ViewBuilder
    private var currentOrdersSection: some View {
        let mine = content.myOrders
        let others = content.currentOrders.filter { !$0.hasMyShare }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(mine.count > 1 ? "Tes commandes en cours" : "Ta commande en cours")
            if mine.isEmpty {
                Text("Tu n'as pas encore de part dans une commande. Choisis un lot ci-dessous pour te lancer.")
                    .font(.body)
                    .foregroundStyle(.texteSecondaire)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grenierCard()
            } else {
                ForEach(mine) { summary in
                    OrderLink(summary: summary)
                }
            }
        }

        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Commandes ouvertes de \(content.group.name)")
                ForEach(others) { summary in
                    OrderLink(summary: summary)
                }
            }
        }
    }

    // MARK: Nouveaux lots

    @ViewBuilder
    private var newOffersSection: some View {
        if !content.newOffers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Nouveaux lots près de toi")
                VStack(spacing: 0) {
                    ForEach(Array(content.newOffers.enumerated()), id: \.element.id) { index, summary in
                        if index > 0 {
                            Divider().overlay(Color.piste).padding(.leading, 16)
                        }
                        NavigationLink(value: OfferRoute(offerId: summary.offer.id)) {
                            NewOfferRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.surface, in: .rect(cornerRadius: 24))
            }
        }
    }
}

/// Une commande en cours : `OfferCard` + incitation au prochain palier, poussée vers la fiche du lot.
private struct OrderLink: View {
    let summary: OfferSummary

    var body: some View {
        NavigationLink(value: OfferRoute(offerId: summary.offer.id)) {
            VStack(alignment: .leading, spacing: 8) {
                OfferCard(
                    offer: summary.offer,
                    product: summary.product,
                    vendor: summary.vendor,
                    committedShares: summary.committedShares,
                    committedHouseholds: summary.committedHouseholds
                )
                if let nudge {
                    Label(nudge, systemImage: GrenierSymbol.savings)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.horizontal, 16)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(summary.hasMyShare
                           ? "Ta part : \(summary.myShareQuantity) \(summary.myShareQuantity > 1 ? "parts" : "part"). Ouvre la fiche du lot."
                           : "Ouvre la fiche du lot.")
    }

    /// « Encore 2 parts pour débloquer −19 % » (les paliers comptent des parts).
    private var nudge: String? {
        let pricing = summary.pricing
        guard let missing = pricing.sharesToNextTier, let percent = pricing.nextTierDiscountPercent, percent > 0 else {
            return nil
        }
        return "Encore \(missing) \(missing > 1 ? "parts" : "part") pour débloquer −\(percent) %"
    }
}

/// Ligne d'un nouveau lot dans la liste groupée.
private struct NewOfferRow: View {
    let summary: OfferSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ProductIcon(category: summary.product.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.product.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text("\(summary.vendor.legalName) · \(summary.offer.shareUnit)")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(Money.format(summary.pricing.currentPriceCents))
                    .priceStyle(.headline)
                    .foregroundStyle(.texte)
                if summary.pricing.savingsPercent > 0 {
                    SavingsBadge(kind: .percent(summary.pricing.savingsPercent), compact: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre la fiche du lot.")
    }
}

/// Carte Economie : « 48 $ économisés » (maquette F1).
private struct SavingsCard: View {
    let savedCents: Cents
    let orderCount: Int

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Économisé avec ton groupe")
                    .font(.subheadline)
                Text(Money.formatRounded(savedCents))
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(savedCents)))
                Text(detail)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: GrenierSymbol.savings)
                    .font(.title2.bold())
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.onAccent.opacity(0.18), in: .circle)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.onAccent)
        .padding(20)
        .background(Color.economie, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Money.formatRounded(savedCents)) économisés avec ton groupe, \(detail)")
    }

    private var detail: String {
        if orderCount == 0 { return "vs l'épicerie du coin" }
        return "sur \(orderCount) \(orderCount > 1 ? "commandes" : "commande"), vs l'épicerie du coin"
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.texte)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Le ménage n'a pas encore de groupe : on l'oriente vers l'onglet Groupes.
private struct NoGroupView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Pas encore de groupe", systemImage: GrenierSymbol.groups)
                .symbolRenderingMode(.hierarchical)
        } description: {
            Text("Rejoins un groupe de ton quartier dans l'onglet Groupes pour acheter en gros avec tes voisins.")
        }
    }
}

#Preview("Clair") {
    FamilyHomeScreen()
        .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    FamilyHomeScreen()
        .environment(\.appContext, .instant)
        .preferredColorScheme(.dark)
}
