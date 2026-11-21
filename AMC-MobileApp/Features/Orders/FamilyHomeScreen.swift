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
                        empty: .init(title: "Rien pour l'instant", systemImage: "basket",
                                     message: "Aucune commande ni aucun lot dans ton quartier. Reviens un peu plus tard."),
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
                GroupBanner(
                    group: content.group,
                    orderCount: content.currentOrders.count,
                    newOfferCount: content.newOffers.count
                )
                .cascadeAppear(0)

                SavingsCard(savedCents: content.savedCents, orderCount: content.myOrders.count)
                    .cascadeAppear(1)

                currentOrdersSection
                    .cascadeAppear(2)

                newOffersSection
                    .cascadeAppear(3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // Rechargement qui change les économies : retour haptique, le montant défile à l'écran.
        .grenierHaptic(.success, trigger: content.savedCents)
    }

    // MARK: Commandes en cours

    private var currentOrdersSection: some View {
        let mine = content.myOrders
        let others = content.currentOrders.filter { !$0.hasMyShare }
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                GrenierSectionHeader(
                    mine.count > 1 ? "Tes commandes en cours" : "Ta commande en cours",
                    systemImage: "cart.fill"
                )
                if mine.isEmpty {
                    NoOrderCard(hasOffersBelow: !content.newOffers.isEmpty)
                } else {
                    ForEach(mine) { summary in
                        OrderLink(summary: summary)
                    }
                }
            }

            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    GrenierSectionHeader("Commandes ouvertes de \(content.group.name)", systemImage: GrenierSymbol.groups)
                    ForEach(others) { summary in
                        OrderLink(summary: summary)
                    }
                }
            }
        }
    }

    // MARK: Nouveaux lots

    private var newOffersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GrenierSectionHeader("Nouveaux lots près de toi", systemImage: "sparkles")
            if content.newOffers.isEmpty {
                NoNewOfferCard()
            } else {
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

// MARK: - En-tête du groupe

/// Bandeau du groupe en tête d'écran : icône, nom, quartier, et trois pastilles de chiffres.
private struct GroupBanner: View {
    let group: NeighborhoodGroup
    let orderCount: Int
    let newOfferCount: Int

    @ScaledMetric(relativeTo: .title2) private var tileSide: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: GrenierSymbol.groups)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: min(tileSide, 80), height: min(tileSide, 80))
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(Color.texte)
                    Label(group.neighborhood, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(Color.texteSecondaire)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            chips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .combine)
        .onAppear { hasAppeared = true }
    }

    /// Côte à côte, ou empilées sous Dynamic Type accessibilité (rien n'est coupé).
    private var chips: some View {
        let layout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            StatChip(
                value: group.householdCount,
                label: FrenchPlural.word(group.householdCount, "famille"),
                systemImage: "house.fill",
                tint: .solidarite
            )
            StatChip(
                value: orderCount,
                label: FrenchPlural.word(orderCount, "commande"),
                systemImage: "cart.fill",
                tint: .grenier
            )
            StatChip(
                value: newOfferCount,
                label: FrenchPlural.word(newOfferCount, "nouveau lot", plural: "nouveaux lots"),
                systemImage: "shippingbox.fill",
                tint: .economie
            )
        }
    }
}

/// Pastille « 24 familles » : icône teintée, chiffre arrondi, mot.
private struct StatChip: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value, format: .number)
                .fontDesign(.rounded)
                .monospacedDigit()
                .bold()
                .contentTransition(.numericText(value: Double(value)))
                .foregroundStyle(Color.texte)
            Text(label)
                .foregroundStyle(Color.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: .capsule)
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
                if summary.hasMyShare {
                    Label(
                        "Ta part : \(FrenchPlural.count(summary.myShareQuantity, "part"))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.economie)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.horizontal, 16)
                }
                if let nudge {
                    Label(nudge, systemImage: GrenierSymbol.savings)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.grenier)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.horizontal, 16)
                }
            }
        }
        .pressable()
        .accessibilityHint("Ouvre la fiche du lot.")
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
                Label(summary.vendor.legalName, systemImage: "storefront.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
                Label(summary.offer.shareUnit, systemImage: "scalemass.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
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
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.texteSecondaire)
                    .accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Économisé avec ton groupe", systemImage: "banknote.fill")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(Money.formatRounded(savedCents))
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(savedCents)))
                Label(detail, systemImage: "cart.badge.minus")
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: GrenierSymbol.savings)
                    .font(.title2.bold())
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.onAccent.opacity(0.18), in: .circle)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                    .symbolEffect(.bounce, options: .nonRepeating, value: savedCents)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.onAccent)
        .padding(20)
        .background(Color.economie, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Money.formatRounded(savedCents)) économisés avec ton groupe, \(detail)")
        .onAppear { hasAppeared = true }
    }

    private var detail: String {
        if orderCount == 0 { return "vs l'épicerie du coin" }
        return "sur \(orderCount) \(orderCount > 1 ? "commandes" : "commande"), vs l'épicerie du coin"
    }
}

// MARK: - États vides illustrés

/// Pas encore de part : petite scène panier et invitation vers les lots du dessous.
private struct NoOrderCard: View {
    let hasOffersBelow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            GrenierSymbolScene(
                symbol: "cart.badge.plus",
                satellites: [.init("carrot.fill", tint: .economie), .init("leaf.fill", tint: .economie)]
            )
            Text("Tu n'as pas encore de part dans une commande.")
                .font(.headline)
                .foregroundStyle(Color.texte)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if hasOffersBelow {
                Label("Choisis un lot ci-dessous pour te lancer", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce.down, options: .repeat(.periodic(delay: 2.5)), isActive: !reduceMotion)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Aucun nouveau lot dans la zone du groupe.
private struct NoNewOfferCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.texteSecondaire)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pas de nouveau lot pour l'instant")
                    .font(.headline)
                    .foregroundStyle(Color.texte)
                Text("Les producteurs en ajoutent chaque semaine : tire vers le bas pour actualiser.")
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

/// Le ménage n'a pas encore de groupe : on l'oriente vers l'onglet Groupes.
private struct NoGroupView: View {
    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                GrenierSymbolScene(
                    symbol: GrenierSymbol.groups,
                    satellites: [.init("house.fill", tint: .solidarite), .init("mappin.and.ellipse"), .init("basket.fill", tint: .economie)]
                )
                Text("Pas encore de groupe")
                    .font(.title2.bold())
                    .foregroundStyle(Color.texte)
            }
        } description: {
            Text("Rejoins un groupe de ton quartier dans l'onglet Groupes pour acheter en gros avec tes voisins.")
        } actions: {
            Label("Onglet Groupes, en bas de l'écran", systemImage: "arrow.down.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.grenier)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Apparition en cascade

private struct CascadeAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.06 * Double(index))) {
                    isVisible = true
                }
            }
    }
}

private extension View {
    /// Carte qui glisse et apparaît en cascade (rang `index`) ; immédiate sous Reduce Motion.
    func cascadeAppear(_ index: Int) -> some View {
        modifier(CascadeAppear(index: index))
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

#Preview("AX5") {
    FamilyHomeScreen()
        .environment(\.appContext, .instant)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Sans groupe") {
    NoGroupView()
        .grenierBackground()
}
