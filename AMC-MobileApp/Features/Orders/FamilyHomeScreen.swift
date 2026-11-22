import SwiftUI

/// F1 Accueil d'une famille (maquette `docs/maquettes/F1-accueil.png`) :
/// « Bonjour Amina », économies, commandes en cours du groupe, nouveaux lots près de chez toi.
struct FamilyHomeScreen: View {
    @Environment(\.appContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Contexte de session : rechargé au retour sur l'Accueil sans groupe et au tirer-pour-rafraîchir,
    /// pour qu'un groupe rejoint ailleurs (onglet Groupes, lien d'invitation) s'affiche tout de suite.
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?
    @State private var viewModel: FamilyHomeViewModel?
    /// Identité pour laquelle `viewModel` a été créé : un autre compte (ou un autre groupe) recrée le modèle.
    @State private var loadedIdentity: String?
    @AppStorage(HomeSection.storageKey) private var rawLayout = ""
    @State private var isEditingLayout = false
    /// T-181 : en mode aîné, l'Accueil est fixe et réduit à l'essentiel (pas d'édition des sections).
    @Environment(\.isSeniorMode) private var isSeniorMode

    var body: some View {
        NavigationStack {
            Group {
                if context.isResolved && !context.hasGroup {
                    // Dans un ScrollView pour que le tirer-pour-rafraîchir marche aussi sans groupe.
                    ScrollView {
                        NoGroupView()
                            .containerRelativeFrame(.vertical)
                    }
                } else if let viewModel, !viewModel.state.isLoading, !isIdle(viewModel.state) {
                    StateView(
                        state: viewModel.state,
                        empty: .init(title: "Rien pour l'instant", systemImage: "basket",
                                     message: "L'Accueil réunit les commandes de ton groupe et les lots près de chez toi. Les producteurs en ajoutent chaque semaine : actualise pour voir les nouveautés."),
                        retry: { await viewModel.load() }
                    ) { content in
                        FamilyHomeContent(
                            content: content,
                            largeGreeting: usesInlineTitle ? title : nil,
                            isArrangingSections: isEditingLayout
                        )
                    }
                } else {
                    FamilyHomeSkeleton()
                }
            }
            .grenierBackground()
            .navigationTitle(usesInlineTitle ? String(localized: "Accueil") : title)
            .navigationBarTitleDisplayMode(usesInlineTitle ? .inline : .automatic)
            .profileToolbar()
            .toolbar {
                // B-037 : sections réorganisables (ordre, masquage, Réinitialiser).
                if viewModel?.state.value != nil, !isSeniorMode {
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
            .refreshable {
                // Le contexte d'abord : un nouveau groupe recrée le modèle de l'Accueil (task(id: identity)).
                await contextStore?.reload()
                await viewModel?.load()
            }
            // Retour depuis une fiche de lot ou depuis un autre onglet : une part réservée entre-temps
            // (et le nouveau prix) s'affiche tout de suite. `load()` garde le contenu affiché pendant le rechargement.
            .onAppear { reloadIfAlreadyLoaded() }
            // Une part réservée depuis la fiche (poussée sur cette pile ou ouverte d'un autre onglet) : on recharge
            // tout de suite, sans attendre le retour. Le zoom de la fiche ne relance pas toujours `onAppear`.
            .onChange(of: ShareActivity.shared.generation) { reloadIfAlreadyLoaded() }
        }
        // Bascule de portail : le voile attend que l'accueil ait son contenu.
        .portalContentReady(.family, when: isContentReady)
        // FB-19 : « Salut, moi c'est Noisette », avant les bulles de la visite guidée.
        .guidedTourWelcome(isReady: viewModel?.state.value != nil)
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
        if let firstName = viewModel?.state.value?.firstName, !firstName.isEmpty { return String(localized: "Bonjour \(firstName)") }
        return String(localized: "Accueil")
    }

    /// L'accueil montre autre chose que le squelette.
    private var isContentReady: Bool {
        if context.isResolved && !context.hasGroup { return true }
        guard let viewModel else { return false }
        return !viewModel.state.isLoading && !isIdle(viewModel.state)
    }

    private func isIdle(_ state: LoadState<FamilyHomeViewModel.Content>) -> Bool {
        if case .idle = state { true } else { false }
    }

    /// Recharge seulement après un premier chargement : la `.task` s'occupe du tout premier.
    private func reloadIfAlreadyLoaded() {
        if context.isResolved && !context.hasGroup {
            Task { await contextStore?.reload() }
            return
        }
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
            case .group: SectionInfo(id: section.rawValue, title: String(localized: "Mon groupe"), systemImage: GrenierSymbol.groups, tint: .grenier)
            case .savings: SectionInfo(id: section.rawValue, title: String(localized: "Économies"), systemImage: GrenierSymbol.savings, tint: .economie)
            case .orders: SectionInfo(id: section.rawValue, title: String(localized: "Commandes en cours"), systemImage: "cart.fill", tint: .grenier)
            case .offers: SectionInfo(id: section.rawValue, title: String(localized: "Nouveaux lots près de toi"), systemImage: "sparkles", tint: .solidarite)
            }
        }
    }
}

private struct FamilyHomeContent: View {
    let content: FamilyHomeViewModel.Content
    /// Salutation affichée dans le contenu (tailles d'accessibilité) : elle passe à la ligne au lieu d'être coupée.
    var largeGreeting: String?
    /// FB-21 : l'éditeur de sections est ouvert ; les sections s'inclinent en 3D derrière la feuille.
    var isArrangingSections = false

    @AppStorage(HomeSection.storageKey) private var rawLayout = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSeniorMode) private var isSeniorMode
    @Environment(\.appContext) private var context
    @Environment(SessionContextStore.self) private var contextStore: SessionContextStore?
    /// Groupes du ménage : à partir de deux, l'Accueil propose de changer de groupe actif.
    @State private var householdGroups: [NeighborhoodGroup] = []
    /// Type de produit choisi dans « Nouveaux lots près de toi » (nil : tous).
    @State private var offerCategory: Product.Category?
    /// La liste des nouveaux lots est dépliée au-delà des premiers.
    @State private var showsAllOffers = false

    private var sections: [HomeSection] {
        let chosen = SectionLayout(raw: rawLayout, defaults: HomeSection.allCases.map(\.rawValue))
            .visible.compactMap(HomeSection.init(rawValue:))
        // T-181 : mode aîné = ma commande et mon groupe seulement.
        return SeniorMode.visibleHomeSections(chosen, isSenior: isSeniorMode)
    }

    var body: some View {
        ScrollViewReader { scroller in
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
                            .id(section)
                            .cascadeAppear(index)
                            .sectionArrangeTilt(isArrangingSections)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(reduceMotion ? nil : .smooth, value: sections)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            // FB-19 : les deux étapes de l'Accueil montrent les nouveaux lots ; on les amène à l'écran.
            .onChange(of: GuidedTour.shared.currentStep, initial: true) { _, step in
                guard step?.screen == .home, sections.contains(.offers) else { return }
                withAnimation(reduceMotion ? nil : .smooth) {
                    scroller.scrollTo(HomeSection.offers, anchor: UnitPoint(x: 0.5, y: 0.25))
                }
            }
        }
        // Pendant le réarrangement, l'Accueil n'est qu'un aperçu : pas de toucher par erreur sur une carte inclinée.
        .allowsHitTesting(!isArrangingSections)
        .grenierScrollEdge()
        .task(id: "\(context.householdId)|\(content.group.id)") {
            guard !context.householdId.isEmpty else { return }
            if let groups = try? await context.repositories.groups.groups(ofHousehold: context.householdId) {
                householdGroups = groups
            }
        }
        // Rechargement qui change les économies : retour haptique, le montant défile à l'écran.
        .grenierHaptic(.success, trigger: content.savedCents)
    }

    @ViewBuilder
    private func view(for section: HomeSection) -> some View {
        switch section {
        case .group:
            VStack(alignment: .leading, spacing: 8) {
                GroupBanner(
                    group: content.group,
                    orderCount: content.currentOrders.count,
                    newOfferCount: content.newOffers.count
                )
                if householdGroups.count > 1 {
                    ActiveGroupMenu(groups: householdGroups, activeGroupId: content.group.id) { groupId in
                        contextStore?.selectGroup(groupId)
                    }
                }
            }
        case .savings:
            SavingsCard(savedCents: content.savedCents, isLaunched: content.launchedSavedCents > 0, orderCount: content.myOrders.count)
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
                    isSeniorMode ? (SeniorMode.plainTitle(for: .orders) ?? "")
                        : mine.count > 1 ? String(localized: "Tes commandes en cours") : String(localized: "Ta commande en cours"),
                    systemImage: "cart.fill",
                    info: .tiers
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

            if !others.isEmpty, !isSeniorMode {
                VStack(alignment: .leading, spacing: 12) {
                    GrenierSectionHeader(String(localized: "Commandes ouvertes de \(content.group.name)"), systemImage: GrenierSymbol.groups)
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
        let categories = content.newOffers.map(\.product.category)
        // Une catégorie choisie qui n'a plus de lot (après un rechargement) retombe sur « Tous ».
        let category = offerCategory.flatMap { categories.contains($0) ? $0 : nil }
        let filtered = HomeOfferFilter.filter(content.newOffers, category: category)
        let visibleCount = HomeOfferFilter.visibleCount(total: filtered.count, isExpanded: showsAllOffers)
        return VStack(alignment: .leading, spacing: 12) {
            GrenierSectionHeader(String(localized: "Nouveaux lots près de toi"), systemImage: "sparkles", info: .offers)
                .guidedTourAnchor(.nearbyOffers)
            if content.newOffers.isEmpty {
                NoNewOfferCard()
            } else {
                if HomeOfferFilter.showsChips(categories) {
                    OfferCategoryChips(
                        counts: HomeOfferFilter.categoryCounts(categories),
                        total: content.newOffers.count,
                        selection: category,
                        reduceMotion: reduceMotion
                    ) { newValue in
                        withAnimation(reduceMotion ? nil : .smooth) {
                            offerCategory = newValue
                            showsAllOffers = false
                        }
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(filtered.prefix(visibleCount).enumerated()), id: \.element.id) { index, summary in
                        if index > 0 {
                            Divider().overlay(Color.piste).padding(.leading, 16)
                        }
                        NavigationLink(value: OfferRoute(offerId: summary.offer.id)) {
                            NewOfferRow(summary: summary)
                                .grenierZoomSource(OfferRoute(offerId: summary.offer.id))
                        }
                        .modifier(TourAnchorIfFirst(isFirst: index == 0))
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .background(Color.surface, in: .rect(cornerRadius: 24))
                if filtered.count > HomeOfferFilter.collapsedLimit {
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth) { showsAllOffers.toggle() }
                    } label: {
                        Label(
                            showsAllOffers
                                ? String(localized: "Voir moins de lots")
                                : String(localized: "Voir les \(filtered.count - visibleCount) autres lots"),
                            systemImage: showsAllOffers ? "chevron.up" : "chevron.down"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .tint(.grenier)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: offerCategory)
    }
}

/// Puces « Tous · Céréales · Œufs… » au-dessus des nouveaux lots, avec le nombre de lots de chaque type.
private struct OfferCategoryChips: View {
    let counts: [(category: Product.Category, count: Int)]
    let total: Int
    let selection: Product.Category?
    let reduceMotion: Bool
    let select: (Product.Category?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: String(localized: "Tous"), systemImage: "square.grid.2x2.fill", count: total, value: nil)
                    ForEach(counts, id: \.category) { item in
                        chip(title: item.category.title, systemImage: ProductIcon.symbol(for: item.category),
                             count: item.count, value: item.category)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filtrer par type de produit")
    }

    private func chip(title: String, systemImage: String, count: Int, value: Product.Category?) -> some View {
        let isOn = selection == value
        return Button { select(value) } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isOn)
                Text(title)
                Text(count, format: .number)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .background(isOn ? Color.onAccent.opacity(0.25) : Color.grenier.opacity(0.15), in: .capsule)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? Color.onAccent : Color.texte)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.grenier).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - En-tête du groupe

/// « Changer de groupe » : le ménage fait partie de plusieurs groupes ; l'Accueil, la Cueillette et les lots
/// suivent le groupe actif (mémorisé par `SessionContextStore.selectGroup`).
private struct ActiveGroupMenu: View {
    let groups: [NeighborhoodGroup]
    let activeGroupId: String
    let select: (String) -> Void

    var body: some View {
        Menu {
            Picker("Groupe actif", selection: Binding(get: { activeGroupId }, set: { select($0) })) {
                ForEach(groups) { group in
                    Label {
                        Text(group.name)
                        Text(FrenchPlural.count(group.householdCount, "famille"))
                    } icon: {
                        Image(systemName: GrenierSymbol.groups)
                    }
                    .tag(group.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Changer de groupe (\(groups.count))", systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .tint(.grenier)
        .sensoryFeedback(.selection, trigger: activeGroupId)
        .accessibilityHint("Choisis le groupe affiché sur l'Accueil")
    }
}

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
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            headerLayout {
                GrenierIconTile(systemImage: GrenierSymbol.groups, side: min(tileSide, 80), font: .title2)
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

    /// Trois tuiles de même largeur, alignées sur une ligne ; empilées aux tailles d'accessibilité.
    private var chips: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
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
                label: FrenchPlural.word(newOfferCount, String(localized: "nouveau lot"), plural: String(localized: "nouveaux lots")),
                systemImage: "shippingbox.fill",
                tint: .economie
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Pastille « 24 familles » : icône teintée, chiffre arrondi, mot.
private struct StatChip: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(value, format: .number)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                    .foregroundStyle(Color.texte)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.texteSecondaire)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Même hauteur pour les trois tuiles, même si un libellé passe sur deux lignes.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Une commande en cours : `OfferCard` (qui porte déjà l'incitation au prochain palier) + ta part, poussée vers la fiche du lot.
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
                    committedHouseholds: summary.committedHouseholds,
                    // Ma part vit dans la carte, en pastille courte « ✓ 1 part ».
                    myShareQuantity: summary.hasMyShare ? summary.myShareQuantity : 0
                )
                // La fiche du lot sort de la carte en zoom (T-123).
                .grenierZoomSource(OfferRoute(offerId: summary.offer.id))
            }
        }
        .pressable()
        .accessibilityHint("Ouvre la fiche du lot.")
    }
}

/// Ligne d'un nouveau lot dans la liste groupée.
private struct NewOfferRow: View {
    let summary: OfferSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = isStacked
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
                Label(summary.offer.displayShareUnit, systemImage: "scalemass.fill")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .symbolRenderingMode(.hierarchical)
            }
            if !isStacked { Spacer(minLength: 8) }
            VStack(alignment: isStacked ? .leading : .trailing, spacing: 4) {
                Text(Money.format(summary.pricing.currentPriceCents))
                    .priceStyle(.headline)
                    .foregroundStyle(.texte)
                if summary.pricing.savingsPercent > 0 {
                    SavingsBadge(kind: .percent(summary.pricing.savingsPercent), compact: true)
                }
            }
            if !isStacked {
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

    /// Dès xxxLarge, le prix passe sous le texte : côte à côte, le nom et le vendeur se coupaient mot par mot.
    private var isStacked: Bool { dynamicTypeSize >= .xxxLarge }
}

/// Carte Economie : « 48 $ économisés » (maquette F1).
private struct SavingsCard: View {
    let savedCents: Cents
    /// Faux tant qu'aucune commande n'est lancée : le montant est une estimation, pas une économie réalisée.
    let isLaunched: Bool
    let orderCount: Int

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "banknote.fill")
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
                    .grenierIconCircle(Color.onAccent, side: iconSize, opacity: 0.18)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : hasAppeared)
                    .symbolEffect(.bounce, options: .nonRepeating, value: savedCents)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.onAccent)
        .padding(20)
        .background(Color.economie, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(Money.formatRounded(savedCents)), \(detail)")
        .onAppear { hasAppeared = true }
    }

    private var title: String {
        isLaunched ? String(localized: "Économisé avec ton groupe") : String(localized: "Tu économiseras avec ton groupe")
    }

    private var detail: String {
        if orderCount == 0 { return String(localized: "vs l'épicerie du coin") }
        return String(localized: "sur \(orderCount) \(FrenchPlural.word(orderCount, "commande", plural: "commandes")), vs l'épicerie du coin")
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

/// FB-19 : le premier lot de la liste porte l'étape « Réserve ta part » de la visite guidée.
private struct TourAnchorIfFirst: ViewModifier {
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst {
            content.guidedTourAnchor(.reserveShare)
        } else {
            content
        }
    }
}
