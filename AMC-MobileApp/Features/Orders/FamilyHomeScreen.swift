import SwiftUI

/// F1 Accueil d'une famille (maquette `docs/maquettes/F1-accueil.png`) :
/// « Bonjour Amina », économies, commandes en cours du groupe, nouveaux lots près de chez toi.
struct FamilyHomeScreen: View {
    @Environment(\.appContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: FamilyHomeViewModel?
    /// Identité pour laquelle `viewModel` a été créé : un autre compte (ou un autre groupe) recrée le modèle.
    @State private var loadedIdentity: String?
    @AppStorage(HomeSection.storageKey) private var rawLayout = ""
    @State private var isEditingLayout = false

    var body: some View {
        NavigationStack {
            Group {
                if context.isResolved && !context.hasGroup {
                    NoGroupView()
                } else if let viewModel, !viewModel.state.isLoading, !isIdle(viewModel.state) {
                    StateView(
                        state: viewModel.state,
                        empty: .init(title: "Rien pour l'instant", systemImage: "basket",
                                     message: "Aucune commande ni aucun lot dans ton quartier. Reviens un peu plus tard."),
                        retry: { await viewModel.load() }
                    ) { content in
                        FamilyHomeContent(content: content, largeGreeting: usesInlineTitle ? title : nil)
                    }
                } else {
                    FamilyHomeSkeleton()
                }
            }
            .grenierBackground()
            .navigationTitle(usesInlineTitle ? "Accueil" : title)
            .navigationBarTitleDisplayMode(usesInlineTitle ? .inline : .automatic)
            .profileToolbar()
            .toolbar {
                // B-037 : sections réorganisables (ordre, masquage, Réinitialiser).
                if viewModel?.state.value != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Modifier l'accueil", systemImage: "square.3.layers.3d.down.right") {
                            isEditingLayout = true
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditingLayout) {
                SectionLayoutEditor(title: "Modifier l'accueil", sections: HomeSection.infos, raw: $rawLayout)
            }
            .offerDestination()
            .refreshable { await viewModel?.load() }
            // Retour depuis une fiche de lot ou depuis un autre onglet : une part réservée entre-temps
            // (et le nouveau prix) s'affiche tout de suite. `load()` garde le contenu affiché pendant le rechargement.
            .onAppear { reloadIfAlreadyLoaded() }
        }
        // Retour au premier plan ou du réseau : `load()` garde le contenu affiché pendant le rechargement.
        .refreshOnForeground { await viewModel?.load() }
        .task(id: identity) {
            guard context.hasGroup, let groupId = context.groupId else {
                viewModel = nil
                loadedIdentity = nil
                return
            }
            guard viewModel == nil || loadedIdentity != identity else { return }
            let model = FamilyHomeViewModel(
                repositories: context.repositories,
                userId: context.userId,
                householdId: context.householdId,
                groupId: groupId
            )
            viewModel = model
            loadedIdentity = identity
            await model.load()
        }
    }

    /// Compte, ménage et groupe courants : la salutation suit la personne connectée.
    private var identity: String {
        "\(context.userId)|\(context.householdId)|\(context.groupId ?? "")"
    }

    /// Aux tailles d'accessibilité, le grand titre « Bonjour … » serait coupé : il passe dans le contenu, sur plusieurs lignes.
    private var usesInlineTitle: Bool { dynamicTypeSize.isAccessibilitySize }

    private var title: String {
        if let firstName = viewModel?.state.value?.firstName, !firstName.isEmpty { return "Bonjour \(firstName)" }
        return "Accueil"
    }

    private func isIdle(_ state: LoadState<FamilyHomeViewModel.Content>) -> Bool {
        if case .idle = state { true } else { false }
    }

    /// Recharge seulement après un premier chargement : la `.task` s'occupe du tout premier.
    private func reloadIfAlreadyLoaded() {
        guard let viewModel, viewModel.state.value != nil else { return }
        Task { await viewModel.load() }
    }
}

// MARK: - Contenu

/// Sections de l'Accueil, dans l'ordre par défaut (B-037).
enum HomeSection: String, CaseIterable {
    case group, savings, orders, offers

    static let storageKey = "home.sectionLayout"

    static var infos: [SectionInfo] {
        allCases.map { section in
            switch section {
            case .group: SectionInfo(id: section.rawValue, title: "Mon groupe", systemImage: GrenierSymbol.groups, tint: .grenier)
            case .savings: SectionInfo(id: section.rawValue, title: "Économies", systemImage: GrenierSymbol.savings, tint: .economie)
            case .orders: SectionInfo(id: section.rawValue, title: "Commandes en cours", systemImage: "cart.fill", tint: .grenier)
            case .offers: SectionInfo(id: section.rawValue, title: "Nouveaux lots près de toi", systemImage: "sparkles", tint: .solidarite)
            }
        }
    }
}

private struct FamilyHomeContent: View {
    let content: FamilyHomeViewModel.Content
    /// Salutation affichée dans le contenu (tailles d'accessibilité) : elle passe à la ligne au lieu d'être coupée.
    var largeGreeting: String?

    @AppStorage(HomeSection.storageKey) private var rawLayout = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [HomeSection] {
        SectionLayout(raw: rawLayout, defaults: HomeSection.allCases.map(\.rawValue))
            .visible.compactMap(HomeSection.init(rawValue:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let largeGreeting {
                    Text(largeGreeting)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    view(for: section)
                        .cascadeAppear(index)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? nil : .smooth, value: sections)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .grenierScrollEdge()
        // Rechargement qui change les économies : retour haptique, le montant défile à l'écran.
        .grenierHaptic(.success, trigger: content.savedCents)
    }

    @ViewBuilder
    private func view(for section: HomeSection) -> some View {
        switch section {
        case .group:
            GroupBanner(
                group: content.group,
                orderCount: content.currentOrders.count,
                newOfferCount: content.newOffers.count
            )
        case .savings:
            SavingsCard(savedCents: content.savedCents, orderCount: content.myOrders.count)
        case .orders:
            currentOrdersSection
        case .offers:
            newOffersSection
        }
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
                    ForEach(Array(mine.enumerated()), id: \.element.id) { index, summary in
                        OrderLink(summary: summary)
                            .grenierAppear(index: index)
                    }
                }
            }

            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    GrenierSectionHeader("Commandes ouvertes de \(content.group.name)", systemImage: GrenierSymbol.groups)
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, summary in
                        OrderLink(summary: summary)
                            .grenierAppear(index: mine.count + index)
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
                                .grenierZoomSource(OfferRoute(offerId: summary.offer.id))
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

    /// Côte à côte quand les trois tiennent sur une ligne sans couper un mot, sinon empilées
    /// (plus de « fa-milles » ni « com-mande » coupés en deux à la taille par défaut).
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipViews(fixed: true) }
            VStack(alignment: .leading, spacing: 8) { chipViews(fixed: false) }
        }
    }

    @ViewBuilder
    private func chipViews(fixed: Bool) -> some View {
        Group {
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
        .fixedSize(horizontal: fixed, vertical: true)
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
                // La fiche du lot sort de la carte en zoom (T-123).
                .grenierZoomSource(OfferRoute(offerId: summary.offer.id))
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
            ProductIcon(product: summary.product)
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
            } else {
                FamilyCallToAction(destination: .browseOffers)
            }
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .contain)
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
            Text("Rejoins un groupe de ton quartier pour acheter en gros avec tes voisins.")
        } actions: {
            FamilyCallToAction(destination: .findGroup)
        }
    }
}

// MARK: - Chargement

/// Squelette de l'accueil : la vraie mise en page en formes neutres (aucune donnée inventée), au lieu d'un spinner.
private struct FamilyHomeSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                block(height: 128)
                block(height: 132, tint: .economie)
                block(width: 180, height: 22)
                block(height: 176)
                block(width: 220, height: 22)
                block(height: 92)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollDisabled(true)
        .opacity(isPulsing ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de l'accueil")
    }

    private func block(width: CGFloat? = nil, height: CGFloat, tint: Color = .texteSecondaire) -> some View {
        RoundedRectangle(cornerRadius: height > 40 ? 24 : 8)
            .fill(tint.opacity(0.14))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .frame(height: height)
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
        .environment(\.appContext, .instant)
}

#Preview("Chargement") {
    FamilyHomeSkeleton()
        .grenierBackground()
}
