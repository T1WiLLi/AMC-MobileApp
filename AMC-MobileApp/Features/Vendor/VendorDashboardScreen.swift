import SwiftUI

/// V1 Tableau de bord vendeur (maquette `docs/maquettes/V1-tableau.png`) :
/// revenus prévus, familles servies, meilleur palier atteint, lots qui ferment bientôt et lots ouverts.
struct VendorDashboardScreen: View {
    typealias Dashboard = VendorDashboardViewModel.Dashboard
    typealias Summary = VendorDashboardViewModel.OfferSummary

    @State private var viewModel: VendorDashboardViewModel
    @State private var vendor: Vendor?
    @State private var showsInlineTitle = false
    @State private var showsNotifications = false
    @State private var showsVendorProfile = false
    @State private var showsLayoutEditor = false
    @AppStorage(DashboardSection.storageKey) private var rawLayout = ""

    private let repositories: AppRepositories
    private let vendorId: String
    private let onCreateOffer: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        repositories: AppRepositories,
        vendorId: String,
        onCreateOffer: (() -> Void)? = nil
    ) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.onCreateOffer = onCreateOffer
        _viewModel = State(initialValue: VendorDashboardViewModel(repositories: repositories, vendorId: vendorId))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashboardHeader(vendor: vendor)
                    stateContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .guidedTourScroll(.racoonette)
            .grenierScrollEdge()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 90
            } action: { _, isPastHeader in
                showsInlineTitle = isPastHeader
            }
            .grenierBackground()
            .navigationTitle(showsInlineTitle ? (vendor?.legalName ?? String(localized: "Tableau")) : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ma vitrine", systemImage: "storefront") {
                        showsVendorProfile = true
                    }
                    .guidedTourAnchor(.vendorShop, cornerRadius: 22, padding: 4)
                    .accessibilityHint("Modifie ta description, tes photos, tes produits mis en avant et tes zones desservies, comme les familles les voient.")
                }
                // B-037 : sections réorganisables du tableau (ordre, masquage, Réinitialiser).
                if viewModel.state.value != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Modifier le tableau", systemImage: "square.3.layers.3d.down.right") {
                            showsLayoutEditor = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Notifications", systemImage: "bell") {
                        showsNotifications = true
                    }
                }
            }
            .profileToolbar()
            // Racoonette : la carte d'accueil de la visite, une fois le tableau affiché.
            .guidedTourWelcome(.racoonette, isReady: { if case .idle = viewModel.state { return false }; return !viewModel.state.isLoading }())
            .portalContentReady(.vendor, when: { if case .idle = viewModel.state { return false }; return !viewModel.state.isLoading }())
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                if let onCreateOffer {
                    Button(action: onCreateOffer) {
                        Label("Créer un lot", systemImage: "plus")
                            .font(.headline)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.grenier)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .accessibilityHint("Ouvre l'éditeur de paliers pour un nouveau lot.")
                }
            }
            .sheet(isPresented: $showsVendorProfile, onDismiss: {
                Task { vendor = try? await repositories.vendors.vendor(id: vendorId) }
            }) {
                VendorProfileScreen(repositories: repositories, vendorId: vendorId)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showsLayoutEditor) {
                SectionLayoutEditor(title: String(localized: "Modifier le tableau"), sections: DashboardSection.infos, raw: $rawLayout)
            }
            .sheet(isPresented: $showsNotifications) {
                VendorNotificationsSheet(dashboard: viewModel.state.value)
                    .presentationDetents([.medium, .large])
            }
            // B-055 : premier affichage seulement ; un retour sur l'onglet rafraîchit sans repasser par le squelette.
            .task {
                guard case .idle = viewModel.state else {
                    await viewModel.refresh()
                    return
                }
                async let loadedVendor = try? repositories.vendors.vendor(id: vendorId)
                await viewModel.load()
                vendor = await loadedVendor
            }
            .refreshable {
                await viewModel.refresh()
            }
            // Retour au premier plan ou du réseau : recharge sans repasser par le squelette.
            .refreshOnForeground { await viewModel.refresh() }
        }
    }

    // MARK: - États

    private var stateContent: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                VStack(alignment: .leading, spacing: 16) {
                    DashboardLoadingBadge()
                    DashboardContent(dashboard: .placeholder, animatesHighlight: false)
                        .redacted(reason: .placeholder)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chargement du tableau de bord")
            case .empty:
                DashboardEmptyState(onCreateOffer: onCreateOffer, animates: !reduceMotion)
                    .padding(.top, 24)
            case .failed(let error):
                VStack(spacing: 4) {
                    SymbolScene(
                        center: "chart.bar.xaxis",
                        satellites: [
                            .init(symbol: "wifi.exclamationmark", tint: .grenier),
                            .init(symbol: "shippingbox.fill", tint: .texteSecondaire),
                            .init(symbol: "arrow.clockwise", tint: .grenier)
                        ],
                        size: 104,
                        animates: !reduceMotion
                    )
                    ErrorStateView(error: error, retry: { await viewModel.load() })
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            case .loaded(let dashboard):
                DashboardContent(dashboard: dashboard, animatesHighlight: !reduceMotion)
                    .grenierAnimation(.smooth, value: dashboard)
                    .transition(.opacity)
            }
        }
        // Reduce Motion : aucun effet de symbole (rebond, pulsation) sur tout le tableau.
        .symbolEffectsRemoved(reduceMotion)
    }
}

// MARK: - Scène de symboles

/// Illustration composée de SF Symbols : un symbole central dans un halo, entouré de petits satellites.
private struct SymbolScene: View {
    struct Satellite {
        var symbol: String
        var tint: Color
    }

    let center: String
    let satellites: [Satellite]
    var size: CGFloat = 104
    var animates: Bool = true

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.grenier.opacity(0.12))
            Circle()
                .strokeBorder(Color.grenier.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                .padding(-size * 0.12)
            Image(systemName: center)
                .font(.system(size: size * 0.38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.bounce, value: appeared)
            ForEach(Array(satellites.prefix(3).enumerated()), id: \.offset) { index, satellite in
                Image(systemName: satellite.symbol)
                    .font(.system(size: size * 0.15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(satellite.tint)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Color.surface, in: .circle)
                    .overlay(Circle().strokeBorder(satellite.tint.opacity(0.3), lineWidth: 1))
                    .symbolEffect(.bounce.up.byLayer, value: appeared)
                    .offset(Self.offset(index: index, radius: size * 0.56))
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.2)
        .accessibilityHidden(true)
        .onAppear { if animates { appeared.toggle() } }
    }

    /// Position des satellites : en haut à droite, à gauche, en bas à droite.
    private static func offset(index: Int, radius: CGFloat) -> CGSize {
        let angles: [Double] = [-50, 195, 55]
        let angle = angles[index % angles.count] * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

// MARK: - Chargement et état vide

private struct DashboardLoadingBadge: View {
    var body: some View {
        Label {
            Text("On compte tes parts et tes familles…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.texteSecondaire)
        } icon: {
            Image(systemName: "chart.bar.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.pulse, options: .repeating)
        }
    }
}

private struct DashboardEmptyState: View {
    let onCreateOffer: (() -> Void)?
    let animates: Bool

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 8) {
                SymbolScene(
                    center: "shippingbox",
                    satellites: [
                        .init(symbol: "plus", tint: .grenier),
                        .init(symbol: "person.2.fill", tint: .solidarite),
                        .init(symbol: "leaf.fill", tint: .economie)
                    ],
                    size: 104,
                    animates: animates
                )
                Text("Aucun lot ouvert")
                    .font(.title2.bold())
                    .foregroundStyle(.texte)
            }
        } description: {
            Text("Crée ton premier lot : les familles du quartier pourront s'y joindre et faire baisser le prix ensemble.")
        } actions: {
            if let onCreateOffer {
                Button(action: onCreateOffer) {
                    Label("Créer mon premier lot", systemImage: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.glass)
                .tint(.grenier)
            }
        }
    }
}

// MARK: - En-tête

private struct DashboardHeader: View {
    let vendor: Vendor?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    scene
                    texts
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    texts
                    Spacer(minLength: 0)
                    scene
                }
            }
        }
        .padding(.top, 4)
        .symbolEffectsRemoved(reduceMotion)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Espace vendeur", systemImage: "storefront.fill")
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.hierarchical)
                .textCase(.uppercase)
                .font(.footnote.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(Color.grenier)
            Text(vendor?.legalName ?? String(localized: "Ferme du Québec"))
                .font(.largeTitle.bold())
                .foregroundStyle(.texte)
                .redacted(reason: vendor == nil ? .placeholder : [])
                .accessibilityAddTraits(.isHeader)
            Label {
                Text(subtitle)
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: VendorKindText.symbol(for: vendor?.kind))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            // Vendeur créé depuis l'app (T-158) : tout marche déjà, l'équipe LeGrenier le vérifie en parallèle.
            if vendor?.isVerified == false {
                VerificationPendingBadge()
                    .padding(.top, 4)
            }
        }
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }

    /// Élément visuel fort de l'en-tête : le métier du vendeur entouré de ce qu'il apporte.
    private var scene: some View {
        SymbolScene(
            center: VendorKindText.symbol(for: vendor?.kind),
            satellites: [
                .init(symbol: "person.2.fill", tint: .solidarite),
                .init(symbol: "leaf.fill", tint: .economie),
                .init(symbol: "chart.line.uptrend.xyaxis", tint: .grenier)
            ],
            size: dynamicTypeSize.isAccessibilitySize ? 60 : 68,
            animates: !reduceMotion
        )
        .id(vendor?.kind)
    }

    private var subtitle: String {
        vendor.map { VendorKindText.title(for: $0.kind) } ?? String(localized: "Vendeur")
    }
}

/// Badge « En vérification » : vendeur pas encore vérifié par l'équipe LeGrenier. Informatif, rien n'est bloqué.
struct VerificationPendingBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label("En vérification", systemImage: "clock.badge.checkmark.fill")
            .font(.footnote.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.pulse, options: .repeat(3), isActive: !reduceMotion)
            .foregroundStyle(Color.solidarite)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.solidarite.opacity(0.14), in: .capsule)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Profil en vérification")
            .accessibilityHint("L'équipe LeGrenier vérifie ton profil. Tu peux déjà publier des produits et des lots.")
    }
}

/// Libellé et symbole d'un type de vendeur (tableau de bord, onboarding producteur T-158).
enum VendorKindText {
    static func title(for kind: Vendor.Kind) -> String {
        switch kind {
        case .farm: String(localized: "Ferme")
        case .wholesaler: String(localized: "Grossiste")
        case .cooperative: String(localized: "Coopérative")
        case .bakery: String(localized: "Boulangerie")
        case .other: String(localized: "Vendeur")
        }
    }

    static func symbol(for kind: Vendor.Kind?) -> String {
        switch kind {
        case .farm: "carrot.fill"
        case .wholesaler: "shippingbox.fill"
        case .cooperative: "building.2.fill"
        case .bakery: "birthday.cake.fill"
        case .other, nil: "storefront.fill"
        }
    }
}

// MARK: - Contenu

/// Sections du tableau vendeur, dans l'ordre par défaut (B-037).
enum DashboardSection: String, CaseIterable {
    case stats, highlight, closingSoon, offers

    static let storageKey = "vendorDashboard.sectionLayout"

    static var infos: [SectionInfo] {
        allCases.map { section in
            switch section {
            case .stats: SectionInfo(id: section.rawValue, title: String(localized: "Chiffres clés"), systemImage: "chart.bar.fill", tint: .grenier)
            case .highlight: SectionInfo(id: section.rawValue, title: String(localized: "À la une"), systemImage: "star.fill", tint: .economie)
            case .closingSoon: SectionInfo(id: section.rawValue, title: String(localized: "Se termine bientôt"), systemImage: "hourglass", tint: .solidarite)
            case .offers: SectionInfo(id: section.rawValue, title: String(localized: "Lots ouverts"), systemImage: "shippingbox.fill", tint: .grenier)
            }
        }
    }
}

private struct DashboardContent: View {
    let dashboard: VendorDashboardScreen.Dashboard
    let animatesHighlight: Bool

    @AppStorage(DashboardSection.storageKey) private var rawLayout = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [DashboardSection] {
        SectionLayout(raw: rawLayout, defaults: DashboardSection.allCases.map(\.rawValue))
            .visible.compactMap(DashboardSection.init(rawValue:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sections, id: \.self) { section in
                view(for: section)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: sections)
    }

    @ViewBuilder
    private func view(for section: DashboardSection) -> some View {
        switch section {
        case .stats:
            StatTiles(dashboard: dashboard)
                .guidedTourAnchor(.vendorStats, padding: 8)
        case .highlight:
            if let highlight = dashboard.highlight {
                HighlightBanner(highlight: highlight, animates: animatesHighlight)
                    .grenierTransition(.banner)
            }
        case .closingSoon:
            if !dashboard.closingSoon.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle(String(localized: "Se termine bientôt"), systemImage: "hourglass", pulses: true)
                    ClosingSoonCard(offers: dashboard.closingSoon)
                }
            }
        case .offers:
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(String(localized: "Lots ouverts"), systemImage: "shippingbox.fill")
                VStack(spacing: 12) {
                    ForEach(Array(dashboard.offers.enumerated()), id: \.element.id) { index, summary in
                        VendorOfferCard(summary: summary)
                            .guidedTourAnchor(.vendorRisk, if: index == 0)
                            .grenierTransition(.cardAppear)
                    }
                }
            }
        }
    }
}

/// Titre de section avec son symbole (jamais de titre en texte seul).
private struct SectionTitle: View {
    let title: String
    let systemImage: String
    let pulses: Bool

    init(_ title: String, systemImage: String, pulses: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.pulses = pulses
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .symbolEffect(.pulse, options: .repeating, isActive: pulses)
        }
        .font(.title2.bold())
        .padding(.top, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tuiles

private struct StatTiles: View {
    let dashboard: VendorDashboardScreen.Dashboard
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                revenueTile
                sharesTile
                householdsTile
                offersTile
            }
        } else {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    revenueTile
                    sharesTile
                }
                GridRow {
                    householdsTile
                    offersTile
                }
            }
        }
    }

    private var revenueTile: some View {
        StatTile(
            title: String(localized: "Revenus prévus"),
            systemImage: "dollarsign.circle.fill",
            value: Money.formatRounded(dashboard.projectedRevenueCents),
            numericValue: Double(dashboard.projectedRevenueCents),
            accessibilityText: String(localized: "Revenus prévus : \(Money.formatRounded(dashboard.projectedRevenueCents)), selon les parts engagées.")
        )
    }

    private var sharesTile: some View {
        StatTile(
            title: String(localized: "Parts engagées"),
            systemImage: "square.stack.3d.up.fill",
            value: "\(dashboard.totalCommittedShares) / \(dashboard.totalShares)",
            numericValue: Double(dashboard.totalCommittedShares),
            progress: dashboard.totalShares > 0
                ? min(Double(dashboard.totalCommittedShares) / Double(dashboard.totalShares), 1)
                : nil,
            accessibilityText: String(localized: "\(dashboard.totalCommittedShares) parts engagées sur \(dashboard.totalShares).")
        )
    }

    private var householdsTile: some View {
        StatTile(
            title: String(localized: "Familles servies"),
            systemImage: "person.3.fill",
            value: "\(dashboard.committedHouseholds)",
            numericValue: Double(dashboard.committedHouseholds),
            accessibilityText: String(localized: "\(dashboard.committedHouseholds) familles servies, \(neighborhoodsText).")
        )
    }

    private var offersTile: some View {
        StatTile(
            title: String(localized: "Lots actifs"),
            systemImage: "shippingbox.fill",
            value: "\(dashboard.offers.count)",
            numericValue: Double(dashboard.offers.count),
            caption: dashboard.closingSoon.isEmpty ? nil : closingSoonText,
            accessibilityText: String(localized: "\(dashboard.offers.count) lots actifs, \(closingSoonText).")
        )
    }

    private var neighborhoodCount: Int {
        Set(dashboard.offers.flatMap { $0.linkedOrders.map(\.group.neighborhood) }).count
    }

    private var neighborhoodsText: String {
        neighborhoodCount > 1 ? String(localized: "dans \(neighborhoodCount) quartiers") : String(localized: "dans \(neighborhoodCount) quartier")
    }

    private var closingSoonText: String {
        let count = dashboard.closingSoon.count
        if count == 0 { return String(localized: "aucun ne ferme bientôt") }
        return String(localized: "\(count) ferme bientôt")
    }
}

private struct StatTile: View {
    let title: String
    let systemImage: String
    let value: String
    let numericValue: Double
    var caption: String?
    var progress: Double?
    let accessibilityText: String

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: iconSize, height: iconSize)
                .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 12))
                .symbolEffect(.bounce, value: numericValue)
                .padding(.bottom, 2)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            Text(value)
                .priceStyle()
                .foregroundStyle(.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: numericValue))
            if let progress {
                ProgressView(value: progress)
                    .tint(.grenier)
            }
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Bandeau du meilleur palier

private struct HighlightBanner: View {
    let highlight: VendorDashboardViewModel.Highlight
    let animates: Bool

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 32
    @State private var bounce = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .offset(x: 8, y: -6)
                        .symbolEffect(.bounce.up, value: bounce)
                }
                .symbolEffect(.bounce, value: bounce)
                .symbolEffect(.bounce, value: highlight.tierNumber)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.texte)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plainMessage)
        .onAppear { if animates { bounce.toggle() } }
    }

    private var priceText: String? {
        let tiers = highlight.offer.offer.sortedTiers
        guard tiers.indices.contains(highlight.tierIndex) else { return nil }
        return String(localized: "\(Money.format(tiers[highlight.tierIndex].priceCents)) le \(highlight.offer.offer.displayShareUnit)")
    }

    private var households: Int { highlight.order.order.committedHouseholds }

    private var detail: String {
        if let priceText {
            return String(localized: "\(highlight.offer.title) à \(priceText) pour \(households) \(FrenchPlural.word(households, "famille", plural: "familles")).")
        }
        return String(localized: "\(highlight.offer.title) pour \(households) \(FrenchPlural.word(households, "famille", plural: "familles")).")
    }

    private var message: AttributedString {
        var bold = AttributedString(String(localized: "Palier \(highlight.tierNumber) atteint"))
        bold.inlinePresentationIntent = .stronglyEmphasized
        return bold + AttributedString(" · \(highlight.offer.title)")
    }

    private var plainMessage: String {
        String(localized: "Palier \(highlight.tierNumber) atteint à \(highlight.groupName) : \(detail)")
    }
}

// MARK: - Se termine bientôt

private struct ClosingSoonCard: View {
    let offers: [VendorDashboardScreen.Summary]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(offers.enumerated()), id: \.element.id) { index, summary in
                if index > 0 {
                    Divider().overlay(Color.piste)
                        .padding(.vertical, 12)
                }
                ClosingSoonRow(summary: summary)
            }
        }
        .grenierCard()
    }
}

private struct ClosingSoonRow: View {
    let summary: VendorDashboardScreen.Summary
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: iconSize, height: iconSize)
                .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.headline)
                    .foregroundStyle(.texte)
                MetaLabel(String(localized: "Ferme \(VendorDeadline.relative(summary.offer.deadline))"), systemImage: "calendar.badge.clock")
                MetaLabel(remainingText, systemImage: isFull ? "checkmark.circle.fill" : "person.badge.plus")
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.title), ferme \(VendorDeadline.relative(summary.offer.deadline)), \(remainingText).")
    }

    private var isFull: Bool { summary.committedShares >= summary.totalShares }

    private var remainingText: String {
        let remaining = max(summary.totalShares - summary.committedShares, 0)
        if remaining == 0 { return String(localized: "complet") }
        return String(localized: "encore \(remaining) \(FrenchPlural.word(remaining, "part", plural: "parts"))")
    }
}

/// Petite info secondaire avec son symbole : « 📅 Ferme samedi 14 h ».
private struct MetaLabel: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text)
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.subheadline)
        .foregroundStyle(.texteSecondaire)
    }
}

private enum VendorDeadline {
    static var locale: Locale { AppLanguage.formattingLocale }

    /// « dans 2 jours »
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(locale))
    }

    /// « samedi 14 h »
    static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).hour().locale(locale))
    }
}

// MARK: - Carte d'un lot côté vendeur

private struct VendorOfferCard: View {
    let summary: VendorDashboardScreen.Summary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            TierProgressBar(
                tiers: summary.offer.tiers,
                committedShares: summary.committedShares,
                totalShares: summary.totalShares,
                compact: true
            )

            // RQ-050 (T-104) : la commande de groupe la plus en retard sur le minimum de lancement.
            if let minimumRisk {
                MinimumRiskBadge(assessment: minimumRisk, compact: true)
            }

            footer
        }
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    icon
                    Spacer(minLength: 8)
                    tierBadge
                }
                titles
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                icon
                titles
                Spacer(minLength: 8)
                tierBadge
            }
        }
    }

    private var icon: some View {
        ProductIcon(category: summary.product?.category ?? .grains)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .font(.headline)
                .foregroundStyle(.texte)
            MetaLabel(placeText, systemImage: summary.linkedOrders.isEmpty ? "person.2.slash" : "person.3.fill")
            MetaLabel(String(localized: "Ferme \(VendorDeadline.weekday(summary.offer.deadline))"), systemImage: "calendar.badge.clock")
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var tierBadge: some View {
        if let number = summary.bestTierNumber {
            Label {
                Text("Palier \(number)")
                    .contentTransition(.numericText(value: Double(number)))
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .symbolEffect(.bounce, value: number)
            }
            .font(.footnote.bold())
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.grenier, in: .capsule)
            .fixedSize()
        } else {
            Label {
                Text("En attente")
            } icon: {
                Image(systemName: "hourglass")
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.texteSecondaire)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.piste, in: .capsule)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var footer: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center))
        layout {
            MetaLabel(progressText, systemImage: summary.committedHouseholds == 0 ? "person.crop.circle.badge.questionmark" : "person.2.fill")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                Text(Money.formatRounded(summary.projectedRevenueCents))
                    .priceStyle(.priceCompact)
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(summary.projectedRevenueCents)))
                Label("prévus", systemImage: "chart.line.uptrend.xyaxis")
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
            }
        }
    }

    private var placeText: String {
        guard let first = summary.linkedOrders.first else { return String(localized: "Aucun groupe encore") }
        let others = summary.linkedOrders.count - 1
        return others > 0 ? "\(first.group.name) +\(others)" : first.group.name
    }

    private var progressText: String {
        let households = summary.committedHouseholds
        if households == 0 { return String(localized: "Aucune famille encore · \(summary.totalShares) parts") }
        return FrenchPlural.count(households, "famille")
    }

    /// Pire risque parmi les commandes du lot (niveau, puis parts manquantes) ; nil sans commande.
    private var minimumRisk: MinimumRisk.Assessment? {
        summary.linkedOrders
            .map { MinimumRisk.assess(offer: summary.offer, order: $0.order) }
            .max { ($0.level, $0.missingShares) < ($1.level, $1.missingShares) }
    }

    private var accessibilityText: String {
        var parts = [summary.title]
        if let number = summary.bestTierNumber {
            parts.append(String(localized: "palier \(number) atteint"))
        } else {
            parts.append(String(localized: "aucun palier atteint"))
        }
        let households = summary.committedHouseholds
        parts.append(households == 0
            ? progressText
            : String(localized: "\(households) \(FrenchPlural.word(households, "famille", plural: "familles")) · \(summary.committedShares) parts sur \(summary.totalShares)"))
        if let message = minimumRisk?.message { parts.append(message) }
        parts.append(String(localized: "\(Money.formatRounded(summary.projectedRevenueCents)) prévus"))
        parts.append(String(localized: "\(placeText), ferme \(VendorDeadline.weekday(summary.offer.deadline))"))
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - Notifications

private struct VendorNotificationsSheet: View {
    let dashboard: VendorDashboardScreen.Dashboard?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Rien de neuf"),
                        systemImage: "bell.slash",
                        description: Text("Tu seras averti dès qu'un groupe franchit un palier.")
                    )
                } else {
                    List(items, id: \.text) { item in
                        Label {
                            Text(item.text)
                                .foregroundStyle(.texte)
                        } icon: {
                            Image(systemName: item.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.grenier)
                        }
                        .listRowBackground(Color.surface)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .grenierBackground()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private var items: [(symbol: String, text: String)] {
        guard let dashboard else { return [] }
        var result: [(symbol: String, text: String)] = []
        if let highlight = dashboard.highlight {
            result.append(("checkmark.seal.fill", String(localized: "Palier \(highlight.tierNumber) atteint à \(highlight.groupName) pour \(highlight.offer.title).")))
        }
        for summary in dashboard.closingSoon {
            result.append(("clock.fill", String(localized: "\(summary.title) ferme \(VendorDeadline.relative(summary.offer.deadline)).")))
        }
        return result
    }
}

// MARK: - Contenu de chargement (redacted)

private extension VendorDashboardViewModel.Dashboard {
    /// Forme du tableau de bord pendant le chargement, affichée en `.redacted(reason: .placeholder)`.
    static let placeholder: Self = {
        let deadline = Date.now.addingTimeInterval(2 * 86_400)
        let tiers = [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990), PriceTier(minShares: 30, priceCents: 850)]
        let offers = (0..<2).map { index in
            Offer(id: "placeholder-\(index)", vendorId: "", productId: "", totalShares: 40, shareUnit: "sac de 10 kg",
                  tiers: tiers, minimumSharesToLaunch: 10, deadline: deadline, zones: [], status: .active)
        }
        let summaries = offers.map { offer in
            VendorDashboardViewModel.OfferSummary(
                offer: offer, product: nil, linkedOrders: [], committedShares: 19, committedHouseholds: 11,
                bestTierIndex: 0, projectedRevenueCents: 21_850, isClosingSoon: false
            )
        }
        return .init(offers: summaries)
    }()
}

// MARK: - Previews

#Preview("Clair") {
    VendorDashboardScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive, onCreateOffer: {})
}

#Preview("Sombre") {
    VendorDashboardScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive, onCreateOffer: {})
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorDashboardScreen(repositories: .fake(), vendorId: FakeData.ID.fermeRive, onCreateOffer: {})
        .dynamicTypeSize(.accessibility5)
}

#Preview("Vide") {
    VendorDashboardScreen(repositories: .fake(), vendorId: "vendeur-sans-lot", onCreateOffer: {})
}

#Preview("Erreur") {
    VendorDashboardScreen(repositories: .fake(behavior: .failing()), vendorId: FakeData.ID.fermeRive)
}
