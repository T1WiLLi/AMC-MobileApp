// VendorOffersScreen.swift
// Onglet Lots du portail Vendeur : lots ouverts en cartes, tap pour modifier (V2), « Créer un lot » pour en publier un.
// Lecture via `VendorDashboardViewModel` (lots actifs, parts engagées, palier, revenu prévu).
//
// T-084 : SF Symbols partout (en-tête illustré, chiffres clés, statut, échéance, parts, revenu, actions),
// squelette de chargement, état vide et succès illustrés. Les effets de symbole sont coupés sous Reduce Motion.

import SwiftUI

struct VendorOffersScreen: View {
    enum Route: Hashable {
        case create
        case edit(offerId: String)
        /// S-08 (T-109) : « Mes disponibilités », puis un lot créé depuis l'une d'elles.
        case supplies
        case fromSupply(VendorSupply)
    }

    private let repositories: AppRepositories
    private let vendorId: String
    @State private var model: VendorDashboardViewModel
    @State private var path: [Route] = []
    /// L'éditeur ouvert l'a été par la visite de Racoonette.
    @State private var tourPushed = false
    @State private var publishedTrigger = 0
    @State private var showsPublishedBanner = false
    @Namespace private var transition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(repositories: AppRepositories, vendorId: String) {
        self.repositories = repositories
        self.vendorId = vendorId
        _model = State(initialValue: VendorDashboardViewModel(repositories: repositories, vendorId: vendorId))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .grenierBackground()
                .navigationTitle("Lots")
                .profileToolbar()
                .infoToolbarButton(.vendorOffers)
                // B-052 : « Créer un lot » en icône de barre (le bouton flottant cachait le bas de la liste),
                // « Mes produits » ouvre le catalogue du vendeur.
                .myProductsToolbar(repositories: repositories, vendorId: vendorId)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: Route.supplies) {
                            Label("Mes disponibilités", systemImage: "tray.full.fill")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Créer un lot", systemImage: "plus") {
                            path.append(.create)
                        }
                        .guidedTourAnchor(.vendorCreate, cornerRadius: 22, padding: 4)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : publishedTrigger)
                        .accessibilityHint("Ouvre l'éditeur de paliers pour un nouveau lot.")
                    }
                }
                .safeAreaInset(edge: .top) { publishedBanner }
                .navigationDestination(for: Route.self) { route in
                    editor(for: route)
                }
                .task {
                    if case .idle = model.state { await model.load() }
                }
                // FB-19 : l'étape « paliers » de Racoonette ouvre l'éditeur d'un nouveau lot, puis le referme.
                .onChange(of: GuidedTour.racoonette.currentStep, initial: true) { syncTourNavigation() }
                .sensoryFeedback(.success, trigger: publishedTrigger)
        }
    }

    /// Pousse l'éditeur de paliers pendant son étape, le retire dès qu'on en sort (ou que la visite s'arrête).
    private func syncTourNavigation() {
        if GuidedTour.racoonette.currentStep?.screen == .vendorTierEditor {
            guard path.isEmpty else { return }
            path.append(.create)
            tourPushed = true
        } else if tourPushed {
            tourPushed = false
            path.removeAll()
        }
    }

    // MARK: États

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            VendorOffersSkeleton()
        case .empty:
            VendorOffersEmptyState { path.append(.create) }
        case .failed, .loaded:
            StateView(state: model.state, retry: { await model.load() }) { dashboard in
                offerList(dashboard)
            }
        }
    }

    // MARK: Liste

    private func offerList(_ dashboard: VendorDashboardViewModel.Dashboard) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VendorOffersHero(dashboard: dashboard)
                    .padding(.bottom, 8)

                Label {
                    Text("Lots ouverts")
                } icon: {
                    Image(systemName: "square.stack.3d.up.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

                ForEach(Array(dashboard.offers.enumerated()), id: \.element.id) { index, summary in
                    NavigationLink(value: Route.edit(offerId: summary.id)) {
                        VendorOfferCard(summary: summary)
                            .matchedTransitionSource(id: summary.id, in: transition)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre l'éditeur de paliers de ce lot.")
                    .contextMenu {
                        Button {
                            path.append(.edit(offerId: summary.id))
                        } label: {
                            Label("Modifier les paliers", systemImage: "slider.horizontal.3")
                        }
                        Button {
                            path.append(.create)
                        } label: {
                            Label("Créer un autre lot", systemImage: "plus.square.on.square")
                        }
                    }
                    .grenierTransition(.cardAppear)
                    .grenierAppear(index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .guidedTourScroll(.racoonette)
        .refreshable { await model.refresh() }
    }

    /// Bandeau de succès après publication ou modification d'un lot.
    @ViewBuilder
    private var publishedBanner: some View {
        if showsPublishedBanner {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lot enregistré")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("Les groupes du quartier voient tes paliers.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : publishedTrigger)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard(padding: 14)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .grenierTransition(.banner)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func editor(for route: Route) -> some View {
        switch route {
        case .create:
            TierEditorScreen(repositories: repositories, vendorId: vendorId, onSaved: offerSaved)
        case .edit(let offerId):
            TierEditorScreen(repositories: repositories, vendorId: vendorId, offerId: offerId, onSaved: offerSaved)
                .navigationTransition(.zoom(sourceID: offerId, in: transition))
        case .supplies:
            VendorSuppliesScreen(repositories: repositories, vendorId: vendorId) { supply in
                path.append(.fromSupply(supply))
            }
        case .fromSupply(let supply):
            TierEditorScreen(repositories: repositories, vendorId: vendorId, supply: supply, onSaved: offerSaved)
        }
    }

    private func offerSaved(_ offer: Offer) {
        publishedTrigger += 1
        let trigger = publishedTrigger
        withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { showsPublishedBanner = true }
        Task {
            await model.refresh()
            try? await Task.sleep(for: .seconds(3))
            guard trigger == publishedTrigger else { return }
            withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { showsPublishedBanner = false }
        }
    }
}

// MARK: - En-tête illustré et chiffres clés

/// En-tête : composition de symboles (caisse, familles, paliers, revenu) et trois chiffres clés.
private struct VendorOffersHero: View {
    let dashboard: VendorDashboardViewModel.Dashboard

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VendorOffersHeroArt()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tes lots en vente")
                        .font(.title3.bold())
                        .foregroundStyle(.texte)
                    Text("Plus les familles s'engagent, plus le palier monte.")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            let tiles = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            tiles {
                VendorOffersStatTile(
                    symbol: GrenierSymbol.offers,
                    tint: .grenier,
                    value: Double(dashboard.offers.count),
                    valueText: "\(dashboard.offers.count)",
                    caption: FrenchPlural.word(dashboard.offers.count, String(localized: "lot ouvert"), plural: String(localized: "lots ouverts"))
                )
                VendorOffersStatTile(
                    symbol: "person.2.fill",
                    tint: .solidarite,
                    value: Double(dashboard.totalCommittedShares),
                    valueText: "\(dashboard.totalCommittedShares)/\(dashboard.totalShares)",
                    caption: FrenchPlural.word(dashboard.totalCommittedShares, String(localized: "part engagée"), plural: String(localized: "parts engagées"))
                )
                VendorOffersStatTile(
                    symbol: "dollarsign.circle.fill",
                    tint: .economie,
                    value: Double(dashboard.projectedRevenueCents),
                    valueText: Money.formatRounded(dashboard.projectedRevenueCents),
                    caption: String(localized: "revenu prévu")
                )
            }
        }
        .grenierCard()
    }
}

/// Composition de symboles : la caisse au centre, entourée des familles, des paliers et du revenu.
private struct VendorOffersHeroArt: View {
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 84
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.grenier.opacity(0.12))
            Image(systemName: GrenierSymbol.offers)
                .font(.system(size: side * 0.4))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
            satellite("person.3.fill", tint: .solidarite, angle: -50)
            satellite("chart.bar.fill", tint: .grenier, angle: 70)
            satellite("dollarsign.circle.fill", tint: .economie, angle: 190)
        }
        .frame(width: side, height: side)
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private func satellite(_ symbol: String, tint: Color, angle: Double) -> some View {
        let radius = side * 0.5
        let radians = angle * .pi / 180
        return Image(systemName: symbol)
            .font(.system(size: side * 0.16))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: side * 0.3, height: side * 0.3)
            .background(Color.surface, in: .circle)
            .offset(x: cos(radians) * radius, y: sin(radians) * radius)
    }
}

/// Tuile d'un chiffre clé : symbole teinté, valeur animée, légende.
private struct VendorOffersStatTile: View {
    let symbol: String
    let tint: Color
    let value: Double
    let valueText: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            Text(valueText)
                .priceStyle(.headline)
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: value))
                .grenierAnimation(.smooth, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Carte d'un lot (côté vendeur)

/// Un lot ouvert : produit, statut, échéance, palier atteint, barre de paliers, parts engagées et revenu prévu.
private struct VendorOfferCard: View {
    let summary: VendorDashboardViewModel.OfferSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let header = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            header {
                if let product = summary.product {
                    ProductIcon(category: product.category)
                } else {
                    Image(systemName: GrenierSymbol.offers)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .frame(width: 52, height: 52)
                        .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.title) · \(summary.offer.displayShareUnit)")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    deadlineLabel
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                    statusBadge
                    tierBadge
                }
            }

            TierProgressBar(
                tiers: summary.offer.tiers,
                committedShares: summary.committedShares,
                totalShares: summary.totalShares,
                compact: true
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    progressLabel
                    Spacer()
                    revenueLabel
                }
                VStack(alignment: .leading, spacing: 6) {
                    progressLabel
                    revenueLabel
                }
            }

            Divider()

            HStack {
                Label("Modifier les paliers", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.grenier)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.texteSecondaire)
            }
            .symbolRenderingMode(.hierarchical)
        }
        .grenierCard()
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    // MARK: Statut et échéance

    private var statusBadge: some View {
        Label("Actif", systemImage: "dot.radiowaves.left.and.right")
            .font(.caption.bold())
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.economie)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.economie.opacity(0.12), in: .capsule)
            .accessibilityLabel("Statut : actif")
    }

    private var deadlineLabel: some View {
        Label {
            Text(summary.isClosingSoon ? String(localized: "ferme bientôt · \(deadlineText)") : String(localized: "ferme \(deadlineText)"))
        } icon: {
            Image(systemName: summary.isClosingSoon ? "hourglass" : "calendar.badge.clock")
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: summary.isClosingSoon && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline)
        .foregroundStyle(summary.isClosingSoon ? Color.grenier : Color.texteSecondaire)
    }

    @ViewBuilder
    private var tierBadge: some View {
        if let number = summary.bestTierNumber {
            Label("Palier \(number)", systemImage: "checkmark.seal.fill")
                .font(.caption.bold())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : number)
                .contentTransition(.numericText(value: Double(number)))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.grenier.opacity(0.12), in: .capsule)
        } else {
            Label("\(summary.offer.tiers.count) paliers", systemImage: "stairs")
                .font(.caption.bold())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texteSecondaire)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.piste, in: .capsule)
        }
    }

    // MARK: Chiffres

    private var progressLabel: some View {
        Label {
            Text("\(FrenchPlural.count(summary.committedHouseholds, "famille")) · \(summary.committedShares) parts sur \(summary.totalShares)")
                .contentTransition(.numericText(value: Double(summary.committedShares)))
        } icon: {
            Image(systemName: "person.2.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.solidarite)
        }
        .font(.subheadline)
        .foregroundStyle(.texteSecondaire)
        .monospacedDigit()
        .grenierAnimation(.smooth, value: summary.committedShares)
    }

    private var revenueLabel: some View {
        Label {
            Text(Money.formatRounded(summary.projectedRevenueCents))
                .priceStyle(.priceCompact)
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: Double(summary.projectedRevenueCents)))
        } icon: {
            Image(systemName: "dollarsign.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.economie)
        }
        .grenierAnimation(.smooth, value: summary.projectedRevenueCents)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Revenu prévu \(Money.formatRounded(summary.projectedRevenueCents))")
    }

    private var deadlineText: String {
        summary.offer.deadline.formatted(.dateTime.weekday(.wide).hour().locale(AppLanguage.formattingLocale))
    }
}

// MARK: - Chargement, état vide

/// Squelette de chargement : en-tête et cartes en `.placeholder`.
private struct VendorOffersSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Tes lots en vente", systemImage: GrenierSymbol.offers)
                        .font(.title3.bold())
                    Text("Plus les familles s'engagent, plus le palier monte.")
                        .font(.subheadline)
                    HStack {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16).fill(Color.piste).frame(height: 72)
                        }
                    }
                }
                .grenierCard()
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Riz basmati · sac de 10 kg", systemImage: "shippingbox.fill")
                            .font(.headline)
                        Label("ferme vendredi 17 h", systemImage: "calendar.badge.clock")
                            .font(.subheadline)
                        Capsule().fill(Color.piste).frame(height: 6)
                        Text("12 familles · 24 parts sur 40 · 480 $")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .grenierCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .redacted(reason: .placeholder)
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des lots")
    }
}

/// État vide illustré : caisse vide entourée de paliers et de familles, et l'action utile.
private struct VendorOffersEmptyState: View {
    let create: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.grenier.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 52))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.economie)
                        .background(Color.fond, in: .circle)
                        .offset(x: 42, y: 38)
                        .symbolEffect(.wiggle, options: .nonRepeating, isActive: !reduceMotion)
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.solidarite)
                        .offset(x: -48, y: -36)
                }
                .accessibilityHidden(true)
                Text("Aucun lot ouvert")
            }
        } description: {
            Text("Crée ton premier lot : fixe tes paliers, les groupes du quartier font baisser le prix.")
        } actions: {
            Button(action: create) {
                Label("Créer mon premier lot", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
    }
}

#Preview("Clair") {
    VendorOffersScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
}

#Preview("Sombre") {
    VendorOffersScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorOffersScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Hors ligne") {
    VendorOffersScreen(repositories: .fake(behavior: .failing(.offline)), vendorId: FakeData.ID.fermeRive)
}

#Preview("Vide") {
    VendorOffersEmptyState {}
}

#Preview("Chargement") {
    VendorOffersSkeleton()
        .grenierBackground()
}
