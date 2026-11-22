import SwiftUI

/// Fiche d'un lot et choix de sa part (maquette F3), puis « Palier débloqué ! » (maquette F4).
///
/// Lit `@Environment(\.appContext)` pour les dépôts, le ménage et le groupe, et pilote `OfferDetailViewModel`.
struct OfferDetailScreen: View {
    let offerId: String
    @Environment(\.appContext) private var context
    @State private var viewModel: OfferDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                OfferDetailContent(viewModel: viewModel)
            } else {
                OfferLoadingView()
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            if viewModel == nil {
                viewModel = OfferDetailViewModel(
                    repositories: context.repositories,
                    offerId: offerId,
                    householdId: context.householdId,
                    groupId: context.groupId
                )
            }
        }
    }
}

/// Chargement de la fiche : caisse qui pulse (fixe sous Reduce Motion) et indicateur.
private struct OfferLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: GrenierSymbol.offers)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
            ProgressView("Chargement du lot…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
    }
}

// MARK: - Symboles de la fiche

/// Symboles SF de la fiche d'un lot (rendu hiérarchique, teinte Grenier).
enum OfferDetailSymbol {
    static let producer = "person.crop.square.fill"
    static let origin = "globe.americas.fill"
    static let shareUnit = "scalemass.fill"
    static let deadline = "clock.fill"
    static let deadlineClosed = "clock.badge.xmark"
    static let pickup = "mappin.and.ellipse"
    static let tags = "tag.fill"
    static let aboutSection = "list.bullet.clipboard.fill"
    static let priceSection = "dollarsign.circle.fill"
    static let groupSection = "person.3.fill"
    static let shareSection = "basket.fill"
    static let tier = "stairs"
    static let nextTier = "arrow.down.forward.circle.fill"
    static let bestTier = "crown.fill"
    static let unlocks = "sparkles"
    static let payment = "banknote.fill"
    static let verified = "checkmark.seal.fill"
    static let share = "square.and.arrow.up"
    static let cancel = "xmark.circle"

    /// Symbole du type de vendeur.
    static func vendor(_ kind: Vendor.Kind) -> String {
        switch kind {
        case .farm: "tree.fill"
        case .wholesaler: "building.2.fill"
        case .cooperative: "person.2.circle.fill"
        case .bakery: "birthday.cake.fill"
        case .other: "bag.fill"
        }
    }

    /// Symbole d'une étiquette alimentaire.
    static func tag(_ tag: DietaryTag) -> String {
        switch tag {
        case .organic: "leaf.fill"
        case .halal: "moon.stars.fill"
        case .kosher: "star.fill"
        case .vegetarian: "carrot.fill"
        case .vegan: "leaf.circle.fill"
        case .glutenFree: "allergens"
        case .local: "location.fill"
        }
    }

    /// Deux symboles d'accompagnement autour du symbole du produit dans l'en-tête.
    static func companions(for category: Product.Category) -> (String, String) {
        switch category {
        case .produce: ("leaf.fill", "basket.fill")
        case .grains: ("scalemass.fill", "leaf.fill")
        case .legumes: ("circle.hexagongrid.fill", "scalemass.fill")
        case .oils: ("flame.fill", "frying.pan.fill")
        case .flour: ("oven.fill", "scalemass.fill")
        case .canned: ("fork.knife", "archivebox.fill")
        case .eggs: ("bird.fill", "frying.pan.fill")
        case .meat: ("flame.fill", "snowflake")
        case .household: ("sparkles", "drop.fill")
        }
    }

    /// Bouton principal : réserver, part déjà réservée ou changement de quantité.
    static func reserve(myShare: Int, selected: Int) -> String {
        if myShare == 0 { return "cart.fill.badge.plus" }
        if myShare == selected { return "checkmark.circle.fill" }
        return "arrow.triangle.2.circlepath"
    }
}

// MARK: - F3 Fiche du lot

private struct OfferDetailContent: View {
    @Bindable var viewModel: OfferDetailViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize: CGFloat = 88
    @ScaledMetric(relativeTo: .largeTitle) private var heroHeight: CGFloat = 280
    @ScaledMetric(relativeTo: .body) private var rowIconWidth: CGFloat = 30
    /// Dernière célébration montrée, gardée pendant l'animation de fermeture de la feuille.
    @State private var shownCelebration: OfferDetailViewModel.TierCelebration?

    var body: some View {
        StateView(
            state: viewModel.state,
            empty: .init(
                title: "Lot introuvable",
                systemImage: "shippingbox.and.arrow.backward",
                message: "Ce lot n'est plus disponible. D'autres lots t'attendent dans l'onglet Lots."
            ),
            retry: { await viewModel.load() }
        ) { content in
            loaded(content)
        }
        .grenierBackground()
        .navigationTitle(viewModel.state.value?.product.name ?? String(localized: "Lot"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let content = viewModel.state.value {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(content)) {
                        Label("Partager le lot", systemImage: OfferDetailSymbol.share)
                    }
                }
            }
        }
        .task {
            await viewModel.load()
            await viewModel.observe()
        }
        .alert(
            viewModel.actionError?.title ?? "",
            isPresented: errorPresented,
            presenting: viewModel.actionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .sheet(isPresented: celebrationPresented) {
            celebrationSheet
        }
        .onChange(of: viewModel.celebration) { _, newValue in
            if let newValue { shownCelebration = newValue }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: myShareQuantity) { (old: Int?, new: Int?) -> Bool in
            guard let old, let new else { return false }
            return old != new
        }
    }

    /// Quantité réservée par le ménage, `nil` tant que le lot n'est pas chargé (déclencheur de l'haptique).
    private var myShareQuantity: Int? {
        viewModel.state.value?.myShareQuantity
    }

    /// Déclencheur des `symbolEffect` : constant sous Reduce Motion pour qu'aucun symbole ne bouge.
    private func effectTrigger(_ value: Int) -> Int {
        reduceMotion ? 0 : value
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionError != nil },
            set: { if !$0 { viewModel.actionError = nil } }
        )
    }

    private var celebrationPresented: Binding<Bool> {
        Binding(
            get: { viewModel.celebration != nil },
            set: { if !$0 { viewModel.dismissCelebration() } }
        )
    }

    @ViewBuilder
    private var celebrationSheet: some View {
        if let celebration = viewModel.celebration ?? shownCelebration, let content = viewModel.state.value {
            TierCelebrationView(
                celebration: celebration,
                tiers: content.offer.tiers,
                totalShares: content.offer.totalShares,
                shareUnit: content.offer.shareUnit,
                onDone: { viewModel.dismissCelebration() }
            )
        }
    }

    // MARK: Contenu

    private func loaded(_ content: OfferDetailViewModel.Content) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(content)
                VStack(alignment: .leading, spacing: 28) {
                    header(content)
                    priceSection(content)
                    aboutCard(content)
                    groupSection(content)
                    shareSection(content)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.fond,
                    in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                )
                .padding(.top, -32)
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // B-042 : barre de contrôle iOS 26. Le contenu s'arrête au-dessus d'elle (« Ton groupe » reste visible
        // en fin de défilement) et un bord net la sépare du texte qui passe dessous : rien de superposé.
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            reserveBar(content)
        }
    }

    // MARK: En-tête visuel

    /// Composition de symboles selon la catégorie : symbole du produit dans un halo, deux symboles d'accompagnement.
    private func hero(_ content: OfferDetailViewModel.Content) -> some View {
        let category = content.product.category
        let companions = OfferDetailSymbol.companions(for: category)
        return ZStack {
            LinearGradient(
                colors: [Color.grenier.opacity(0.24), Color.grenier.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .backgroundExtensionEffect()

            ZStack {
                Circle()
                    .fill(Color.grenier.opacity(0.10))
                    .frame(width: heroSymbolSize * 2.1, height: heroSymbolSize * 2.1)
                Circle()
                    .fill(Color.surface.opacity(0.7))
                    .frame(width: heroSymbolSize * 1.5, height: heroSymbolSize * 1.5)
                Image(systemName: ProductIcon.symbol(for: content.product))
                    .font(.system(size: heroSymbolSize, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .symbolEffect(.bounce, value: effectTrigger(content.myShareQuantity))
                companion(companions.0)
                    .offset(x: -heroSymbolSize * 1.0, y: -heroSymbolSize * 0.55)
                companion(companions.1)
                    .offset(x: heroSymbolSize * 1.0, y: heroSymbolSize * 0.5)
                Image(systemName: GrenierSymbol.groups)
                    .font(.system(size: heroSymbolSize * 0.24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .padding(10)
                    .background(Color.surface, in: .circle)
                    .offset(x: heroSymbolSize * 0.6, y: -heroSymbolSize * 0.62)
            }
            .padding(.top, 36)

            VStack {
                Spacer()
                Label(category.title, systemImage: ProductIcon.symbol(for: category))
                    .font(.footnote.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.surface, in: .capsule)
                    .padding(.bottom, 44)
            }
        }
        .frame(height: heroHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    private func companion(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: heroSymbolSize * 0.32, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier.opacity(0.75))
            .symbolEffect(.breathe, isActive: !reduceMotion)
    }

    private func header(_ content: OfferDetailViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("\(content.vendor.legalName) · \(content.product.origin)")
            } icon: {
                Image(systemName: OfferDetailSymbol.vendor(content.vendor.kind))
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Color.grenier)
            Text(content.product.name)
                .font(.title2.bold())
                .foregroundStyle(.texte)
                .accessibilityAddTraits(.isHeader)
            Label {
                Text("Commande groupée · plus on est, moins c'est cher")
            } icon: {
                Image(systemName: GrenierSymbol.groups)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
        }
        .accessibilityElement(children: .combine)
    }

    /// Titre de section avec son symbole (jamais de titre en texte seul).
    private func sectionHeader(_ title: String, systemImage: String, tint: Color = .grenier) -> some View {
        Label {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Prix

    private func priceSection(_ content: OfferDetailViewModel.Content) -> some View {
        let pricing = content.pricing
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 12))
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "Prix du groupe"), systemImage: OfferDetailSymbol.priceSection)
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    PriceTag(priceCents: pricing.currentPriceCents, referenceCents: pricing.groceryPriceCents)
                        .contentTransition(.numericText(value: Double(pricing.currentPriceCents)))
                    Label("prix par \(content.offer.shareUnit)", systemImage: OfferDetailSymbol.shareUnit)
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.texteSecondaire)
                        .accessibilityHidden(true)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if pricing.savingsPercent > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: GrenierSymbol.savings)
                            .font(.subheadline.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.economie)
                            .symbolEffect(.bounce, value: effectTrigger(pricing.savingsPercent))
                            .accessibilityHidden(true)
                        SavingsBadge(kind: .percent(pricing.savingsPercent))
                            .contentTransition(.numericText(value: Double(pricing.savingsPercent)))
                    }
                }
            }
            .grenierAnimation(.smooth, value: pricing.currentPriceCents)
        }
    }

    // MARK: À propos du lot

    private func aboutCard(_ content: OfferDetailViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "Le lot"), systemImage: OfferDetailSymbol.aboutSection)
            VStack(spacing: 0) {
                // Page publique du producteur (T-097, R-009).
                NavigationLink {
                    PublicVendorScreen(vendorId: content.vendor.id)
                } label: {
                    infoRow(String(localized: "Producteur"), systemImage: OfferDetailSymbol.vendor(content.vendor.kind)) {
                        HStack(spacing: 6) {
                            Text(content.vendor.legalName)
                            if content.vendor.isVerified {
                                Image(systemName: OfferDetailSymbol.verified)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.grenier)
                                    .accessibilityLabel("vérifié")
                            }
                        }
                    }
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.texteSecondaire)
                            .padding(.trailing, 16)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Voir la page du producteur")
                rowDivider
                infoRow(String(localized: "Origine"), systemImage: OfferDetailSymbol.origin) {
                    Text(content.product.origin)
                }
                rowDivider
                // B-050 : contenant, poids et valeur d'une part, lus dans `Offer.share`.
                infoRow(String(localized: "Une part"), systemImage: content.offer.share.container.systemImage) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.offer.shareUnit)
                        if let valueCents = content.offer.share.valueCents {
                            Text("Valeur \(Money.format(valueCents))")
                                .font(.subheadline)
                                .foregroundStyle(.texteSecondaire)
                        }
                    }
                }
                rowDivider
                infoRow(
                    String(localized: "Date limite"),
                    systemImage: content.isOpen ? OfferDetailSymbol.deadline : OfferDetailSymbol.deadlineClosed
                ) {
                    Text(content.isOpen ? String(localized: "Ferme \(Self.deadlineText(content.offer.deadline))") : String(localized: "Commande fermée"))
                }
                rowDivider
                infoRow(String(localized: "Point de cueillette"), systemImage: OfferDetailSymbol.pickup) {
                    Text(Self.pickupText(content.groupOrder))
                }
                if !content.product.tags.isEmpty {
                    rowDivider
                    infoRow(String(localized: "Étiquettes"), systemImage: OfferDetailSymbol.tags) {
                        tagChips(content.product.tags)
                    }
                }
            }
            .grenierCard(padding: 0)
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(Color.piste)
            .padding(.leading, 16 + rowIconWidth + 12)
    }

    private func infoRow(_ title: String, systemImage: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: rowIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
                value()
                    .font(.body)
                    .foregroundStyle(.texte)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func tagChips(_ tags: [DietaryTag]) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
        return ViewThatFits(in: .horizontal) {
            layout { ForEach(tags, id: \.self) { tagChip($0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(tags, id: \.self) { tagChip($0) } }
        }
        .padding(.top, 2)
    }

    private func tagChip(_ tag: DietaryTag) -> some View {
        Label(OfferFeedViewModel.title(of: tag), systemImage: OfferDetailSymbol.tag(tag))
            .font(.footnote.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.grenier.opacity(0.12), in: .capsule)
    }

    // MARK: Avancement du groupe

    private func groupSection(_ content: OfferDetailViewModel.Content) -> some View {
        let pricing = content.pricing
        let households = content.groupOrder?.committedHouseholds ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "Ton groupe"), systemImage: OfferDetailSymbol.groupSection)
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        progressTitle(households: households, content: content)
                        Spacer(minLength: 8)
                        tierCaption(pricing)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        progressTitle(households: households, content: content)
                        tierCaption(pricing)
                    }
                }
                TierProgressBar(
                    tiers: content.offer.tiers,
                    committedShares: content.committedShares,
                    totalShares: content.offer.totalShares
                )
                // RQ-050 (T-104) : rien tant que le rythme suffit ou que le minimum est atteint.
                if let order = content.groupOrder {
                    MinimumRiskBadge(assessment: MinimumRisk.assess(offer: content.offer, order: order))
                }
                tierHint(content)
            }
            .grenierCard()
            .grenierAnimation(.smooth, value: content.committedShares)
        }
    }

    private func progressTitle(households: Int, content: OfferDetailViewModel.Content) -> some View {
        Label {
            Text("\(FrenchPlural.count(households, "famille")) · \(FrenchPlural.count(content.committedShares, "part")) sur \(content.offer.totalShares)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(content.committedShares)))
        } icon: {
            Image(systemName: "person.2.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.bounce, value: effectTrigger(content.committedShares))
        }
        .font(.headline)
        .foregroundStyle(.texte)
    }

    private func tierCaption(_ pricing: OfferPricing) -> some View {
        Label {
            Text(pricing.tierNumber == 0 ? String(localized: "Avant le 1er palier") : String(localized: "Palier \(pricing.tierNumber) sur \(pricing.tierCount)"))
                .contentTransition(.numericText(value: Double(pricing.tierNumber)))
        } icon: {
            Image(systemName: OfferDetailSymbol.tier)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .font(.subheadline)
        .foregroundStyle(.texteSecondaire)
    }

    /// Prochaine étape du groupe : lancer la commande, parts manquantes avant le palier suivant, ou meilleur prix atteint.
    @ViewBuilder
    private func tierHint(_ content: OfferDetailViewModel.Content) -> some View {
        let pricing = content.pricing
        if content.groupOrder == nil {
            hintLabel("Ton groupe n'a pas encore lancé de commande sur ce lot.", systemImage: "person.badge.plus")
        } else if !content.isOpen {
            hintLabel("La commande est fermée : les parts ne bougent plus.", systemImage: OfferDetailSymbol.deadlineClosed)
        } else if let missing = pricing.sharesToNextTier {
            let discount = pricing.nextTierDiscountPercent ?? 0
            hintLabel(
                String(localized: "Encore \(missing) \(FrenchPlural.word(missing, "part", plural: "parts")) pour le palier suivant")
                    + (discount > 0 ? " (−\(discount) %)" : "") + ".",
                systemImage: OfferDetailSymbol.nextTier,
                tint: .economie,
                numericValue: missing
            )
        } else {
            hintLabel("Meilleur prix atteint pour tout le groupe !", systemImage: OfferDetailSymbol.bestTier)
        }
    }

    private func hintLabel(_ text: String, systemImage: String, tint: Color = .grenier, numericValue: Int = 0) -> some View {
        Label {
            Text(text)
                .contentTransition(.numericText(value: Double(numericValue)))
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline)
        .foregroundStyle(.texteSecondaire)
    }

    // MARK: Ta part

    @ViewBuilder
    private func shareSection(_ content: OfferDetailViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(String(localized: "Ta part"), systemImage: OfferDetailSymbol.shareSection)

            if content.groupOrder != nil && !content.isOpen {
                OfferSymbolScene(
                    symbol: GrenierSymbol.offers,
                    badge: "lock.circle.fill",
                    title: String(localized: "Commande fermée"),
                    message: String(localized: "Les parts sont figées. Rendez-vous à la cueillette avec ton code QR.")
                )
            }

            if viewModel.quantityOptions.isEmpty {
                OfferSymbolScene(
                    symbol: GrenierSymbol.offers,
                    badge: "xmark.circle.fill",
                    tint: .texteSecondaire,
                    title: String(localized: "Lot complet"),
                    message: String(localized: "Il ne reste plus de parts dans ce lot. Jette un œil aux autres lots de ton quartier.")
                )
            } else {
                sharePicker(content)

                if viewModel.selectedSavingsCents > 0 {
                    Label {
                        Text("Tu économises \(Text(Money.formatRounded(viewModel.selectedSavingsCents)).foregroundStyle(Color.economie).bold()) sur ta part.")
                            .contentTransition(.numericText(value: Double(viewModel.selectedSavingsCents)))
                    } icon: {
                        Image(systemName: GrenierSymbol.savings)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.economie)
                            .symbolEffect(.bounce, value: effectTrigger(viewModel.selectedQuantity))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                }
                if viewModel.selectionUnlocksTier {
                    Label {
                        Text("Ta part fait tomber le prochain palier pour tout le groupe !")
                    } icon: {
                        Image(systemName: OfferDetailSymbol.unlocks)
                            .symbolRenderingMode(.hierarchical)
                            .symbolEffect(.wiggle, value: effectTrigger(viewModel.selectedQuantity))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                    .grenierTransition(.banner)
                }
            }

            if content.myShareQuantity > 0 {
                OfferSymbolScene(
                    symbol: OfferDetailSymbol.shareSection,
                    badge: "checkmark.circle.fill",
                    tint: .economie,
                    title: String(localized: "Part réservée !"),
                    message: String(localized: "Tu as réservé \(Self.quantityLabel(content.myShareQuantity, shareUnit: content.offer.shareUnit)). Tu paies à la cueillette."),
                    trigger: content.myShareQuantity
                )
                .grenierTransition(.cardAppear)
                if content.isOpen {
                    Button(role: .destructive) {
                        Task { await viewModel.cancelShare() }
                    } label: {
                        Label("Annuler ma part", systemImage: OfferDetailSymbol.cancel)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.glass)
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .grenierAnimation(.smooth, value: viewModel.selectedQuantity)
        .grenierAnimation(.smooth, value: content.myShareQuantity)
    }

    @ViewBuilder
    private func sharePicker(_ content: OfferDetailViewModel.Content) -> some View {
        let picker = Picker("Ta part", selection: $viewModel.selectedQuantity) {
            ForEach(viewModel.quantityOptions, id: \.self) { quantity in
                Text(Self.quantityLabel(quantity, shareUnit: content.offer.shareUnit)).tag(quantity)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker
                .pickerStyle(.menu)
                .tint(Color.grenier)
        } else {
            picker
                .pickerStyle(.segmented)
                .controlSize(.large)
        }
    }

    // MARK: Barre du bas

    private func reserveBar(_ content: OfferDetailViewModel.Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        let quantity = Self.quantityLabel(viewModel.selectedQuantity, shareUnit: content.offer.shareUnit)
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.format(viewModel.selectedTotalCents))
                    .priceStyle(.title2.bold())
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(viewModel.selectedTotalCents)))
                Label("\(quantity) · payé à la cueillette", systemImage: OfferDetailSymbol.payment)
                    .font(.footnote)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.texteSecondaire)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total \(Money.format(viewModel.selectedTotalCents)) pour \(quantity), payé à la cueillette")

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }

            Button {
                Task { await viewModel.reserve() }
            } label: {
                Group {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Label {
                            // La quantité est déjà dans le résumé à gauche : le bouton reste sur une ligne.
                            Text(reserveTitle(content))
                                .lineLimit(1)
                                .fixedSize()
                        } icon: {
                            Image(systemName: OfferDetailSymbol.reserve(
                                myShare: content.myShareQuantity,
                                selected: viewModel.selectedQuantity
                            ))
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .symbolEffect(.bounce, value: effectTrigger(content.myShareQuantity))
                        }
                    }
                }
                .font(.headline)
                .frame(minHeight: 32)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.grenier)
            .disabled(!viewModel.canReserve)
            .accessibilityLabel(reserveAccessibilityTitle(content, quantity: quantity))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .grenierAnimation(.smooth, value: viewModel.selectedQuantity)
    }

    /// Libellé court du bouton : la quantité choisie est affichée dans le résumé à côté.
    private func reserveTitle(_ content: OfferDetailViewModel.Content) -> String {
        if content.myShareQuantity == 0 { return String(localized: "Réserver") }
        if content.myShareQuantity == viewModel.selectedQuantity { return String(localized: "Part réservée") }
        return String(localized: "Modifier ma part")
    }

    /// VoiceOver garde la quantité dans le libellé du bouton.
    private func reserveAccessibilityTitle(_ content: OfferDetailViewModel.Content, quantity: String) -> String {
        if content.myShareQuantity == 0 { return String(localized: "Réserver \(quantity)") }
        if content.myShareQuantity == viewModel.selectedQuantity { return String(localized: "Part réservée") }
        return String(localized: "Passer à \(quantity)")
    }

    private func shareText(_ content: OfferDetailViewModel.Content) -> String {
        String(localized: "\(content.product.name) (\(content.offer.shareUnit)) à \(Money.format(content.pricing.currentPriceCents)) avec \(content.vendor.legalName) sur LeGrenier. Plus on est de familles, plus le prix baisse !")
    }

    // MARK: Formatage

    static func deadlineText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).hour().locale(AppLanguage.formattingLocale))
    }

    /// Créneau de cueillette s'il est connu, sinon qui le choisira.
    static func pickupText(_ order: GroupOrder?) -> String {
        if let slot = order?.pickupSlots.min(by: { $0.start < $1.start }) {
            let day = slot.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.formattingLocale))
            let start = slot.start.formatted(.dateTime.hour().minute().locale(AppLanguage.formattingLocale))
            let end = slot.end.formatted(.dateTime.hour().minute().locale(AppLanguage.formattingLocale))
            return "\(day), \(start) à \(end)"
        }
        if order?.pickupPointId != nil { return String(localized: "Lieu choisi par ton groupe, horaire à venir") }
        return String(localized: "Choisi par ton groupe à la fermeture")
    }

    /// « 20 kg » pour 2 parts de « sac de 10 kg » ; sinon « 2 × caisse ».
    static func quantityLabel(_ shares: Int, shareUnit: String) -> String {
        if let match = shareUnit.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(kg|g|L|l)\b/),
           let value = Double(match.1.replacingOccurrences(of: ",", with: ".")) {
            let total = value * Double(shares)
            let number = total.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.formattingLocale))
            return "\(number) \(match.2)"
        }
        return shares == 1 ? "1 \(shareUnit)" : "\(shares) × \(shareUnit)"
    }
}

// MARK: - Scène de symboles

/// Illustration d'un état (lot fermé, lot complet, part réservée) : symbole dans un halo et pastille d'état.
private struct OfferSymbolScene: View {
    let symbol: String
    let badge: String
    var tint: Color = .grenier
    let title: String
    let message: String
    /// Change pour faire rebondir la pastille (ignoré sous Reduce Motion).
    var trigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 76

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(tint.opacity(0.12), in: .circle)
                Image(systemName: badge)
                    .font(.system(size: size * 0.32, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.onAccent, tint)
                    .background(Color.surface, in: .circle)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : trigger)
                    .offset(x: 4, y: 4)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - F4 Palier débloqué

/// Moment « Palier débloqué ! » : sceau qui rebondit, prix qui baisse en chiffres animés, haptique de succès.
/// Version locale en attendant `TierUnlockedCelebration` (T-033) dans `Core/Design/Components/`.
private struct TierCelebrationView: View {
    let celebration: OfferDetailViewModel.TierCelebration
    let tiers: [PriceTier]
    let totalShares: Int
    let shareUnit: String
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 132
    @ScaledMetric(relativeTo: .largeTitle) private var sealSize: CGFloat = 60
    @State private var displayedPriceCents: Cents?
    @State private var bounce = 0
    @State private var didAppear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                seal
                    .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Palier débloqué !")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.texte)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.texteSecondaire)
                        .multilineTextAlignment(.center)
                }

                priceCard
                shareCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            LinearGradient(colors: [Color.grenier.opacity(0.16), Color.fond], startPoint: .top, endPoint: .center)
                .background(Color.fond)
                .ignoresSafeArea()
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onDone) {
                Label("Voir ma part", systemImage: OfferDetailSymbol.shareSection)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.grenier)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: didAppear)
        .onAppear(perform: start)
    }

    /// Sceau entouré d'étincelles : elles rebondissent avec lui (immobiles sous Reduce Motion).
    private var seal: some View {
        ZStack {
            Image(systemName: celebration.isLastTier ? OfferDetailSymbol.bestTier : "checkmark.seal.fill")
                .font(.system(size: sealSize, weight: .semibold))
                .foregroundStyle(Color.onAccent)
                .symbolEffect(.bounce, value: bounce)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.grenier, in: .circle)
                .shadow(color: Color.grenier.opacity(0.3), radius: 16, y: 8)
            sparkle("sparkle", size: 0.26)
                .offset(x: -badgeSize * 0.62, y: -badgeSize * 0.38)
            sparkle("sparkles", size: 0.22)
                .offset(x: badgeSize * 0.64, y: -badgeSize * 0.28)
            sparkle(GrenierSymbol.savings, size: 0.2, tint: .economie)
                .offset(x: badgeSize * 0.56, y: badgeSize * 0.42)
            sparkle(GrenierSymbol.groups, size: 0.18)
                .offset(x: -badgeSize * 0.58, y: badgeSize * 0.4)
        }
        .accessibilityHidden(true)
    }

    private func sparkle(_ symbol: String, size: CGFloat, tint: Color = .grenier) -> some View {
        Image(systemName: symbol)
            .font(.system(size: badgeSize * size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: bounce)
    }

    private var subtitle: String {
        if celebration.isLastTier {
            return String(localized: "Ta part fait tomber le dernier palier. Le meilleur prix vaut pour tout le groupe.")
        }
        return String(localized: "Ta part fait passer le groupe au palier \(celebration.tierNumber) sur \(celebration.tierCount). Le prix baisse pour tout le monde.")
    }

    private var priceCard: some View {
        let price = displayedPriceCents ?? celebration.previousPriceCents
        return VStack(spacing: 16) {
            Label {
                Text("Nouveau prix par \(shareUnit)")
            } icon: {
                Image(systemName: OfferDetailSymbol.priceSection)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.texteSecondaire)
            .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { priceChange(price) }
                VStack(spacing: 4) { priceChange(price) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Le prix passe de \(Money.format(celebration.previousPriceCents)) à \(Money.format(celebration.newPriceCents)) le \(shareUnit)")

            TierProgressBar(tiers: tiers, committedShares: celebration.committedShares, totalShares: totalShares)

            Label {
                Text("Palier \(celebration.tierNumber) sur \(celebration.tierCount) · \(FrenchPlural.count(celebration.committedShares, "part"))")
                    .monospacedDigit()
            } icon: {
                Image(systemName: OfferDetailSymbol.tier)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            .font(.footnote)
            .foregroundStyle(.texteSecondaire)
        }
        .grenierCard(padding: 20)
    }

    @ViewBuilder
    private func priceChange(_ price: Cents) -> some View {
        Text(Money.format(celebration.previousPriceCents))
            .priceStyle(.title3.bold())
            .strikethrough()
            .foregroundStyle(.texteSecondaire)
        Image(systemName: "arrow.right.circle.fill")
            .font(.headline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.economie)
        Text(Money.format(price))
            .priceStyle(.largeTitle.bold())
            .foregroundStyle(Color.grenier)
            .contentTransition(.numericText(value: Double(price)))
    }

    private var shareCard: some View {
        VStack(spacing: 0) {
            row(title: String(localized: "Ta part"), systemImage: OfferDetailSymbol.shareSection) {
                Text("\(OfferDetailContent.quantityLabel(celebration.myQuantity, shareUnit: shareUnit)) · \(Money.format(celebration.myTotalCents))")
                    .font(.headline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(celebration.myTotalCents)))
            }
            if celebration.mySavingsCents > 0 {
                Divider().overlay(Color.piste)
                row(title: String(localized: "Tu économises"), systemImage: GrenierSymbol.savings, tint: .economie) {
                    SavingsBadge(kind: .amount(celebration.mySavingsCents))
                        .contentTransition(.numericText(value: Double(celebration.mySavingsCents)))
                }
            }
        }
        .grenierCard(padding: 0)
    }

    private func row(
        title: String,
        systemImage: String,
        tint: Color = .grenier,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center))
        return layout {
            Label {
                Text(title)
                    .foregroundStyle(.texte)
            } icon: {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            .font(.body)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    private func start() {
        guard !didAppear else { return }
        didAppear = true
        AccessibilityNotification.Announcement(
            String(localized: "Palier débloqué ! Le prix passe de \(Money.format(celebration.previousPriceCents)) à \(Money.format(celebration.newPriceCents)) le \(shareUnit).")
        ).post()
        if reduceMotion {
            displayedPriceCents = celebration.newPriceCents
            return
        }
        displayedPriceCents = celebration.previousPriceCents
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            bounce += 1
            withAnimation(.smooth(duration: 0.8)) {
                displayedPriceCents = celebration.newPriceCents
            }
        }
    }
}

// MARK: - Previews

#Preview("Fiche clair") {
    NavigationStack {
        OfferDetailScreen(offerId: FakeData.ID.potatoOffer)
    }
    .environment(\.appContext, .instant)
}

#Preview("Fiche sombre") {
    NavigationStack {
        OfferDetailScreen(offerId: FakeData.ID.potatoOffer)
    }
    .environment(\.appContext, .instant)
    .preferredColorScheme(.dark)
}

#Preview("Scènes d'état") {
    ScrollView {
        VStack(spacing: 16) {
            OfferSymbolScene(symbol: OfferDetailSymbol.shareSection, badge: "checkmark.circle.fill", tint: .economie,
                             title: "Part réservée !", message: "Tu as réservé 20 kg. Tu paies à la cueillette.")
            OfferSymbolScene(symbol: GrenierSymbol.offers, badge: "lock.circle.fill",
                             title: "Commande fermée", message: "Les parts sont figées.")
            OfferSymbolScene(symbol: GrenierSymbol.offers, badge: "xmark.circle.fill", tint: .texteSecondaire,
                             title: "Lot complet", message: "Il ne reste plus de parts dans ce lot.")
        }
        .padding()
    }
    .grenierBackground()
}

#Preview("Palier clair") {
    TierCelebrationView(
        celebration: .init(tierNumber: 2, tierCount: 3, previousPriceCents: 1_150, newPriceCents: 990,
                           committedShares: 21, myQuantity: 2, myTotalCents: 1_980, mySavingsCents: 1_218),
        tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                PriceTier(minShares: 30, priceCents: 850)],
        totalShares: 40,
        shareUnit: "sac de 10 kg",
        onDone: {}
    )
}

#Preview("Palier sombre") {
    TierCelebrationView(
        celebration: .init(tierNumber: 3, tierCount: 3, previousPriceCents: 990, newPriceCents: 850,
                           committedShares: 31, myQuantity: 1, myTotalCents: 850, mySavingsCents: 749),
        tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                PriceTier(minShares: 30, priceCents: 850)],
        totalShares: 40,
        shareUnit: "sac de 10 kg",
        onDone: {}
    )
    .preferredColorScheme(.dark)
}
