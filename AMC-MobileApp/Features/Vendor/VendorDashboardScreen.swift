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

    private let repositories: AppRepositories
    private let vendorId: String
    private let onCreateOffer: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        repositories: AppRepositories = .fake(),
        vendorId: String = FakeData.ID.fermeRive,
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
                    DashboardHeader(vendor: vendor, openOffers: viewModel.state.value?.offers.count)
                    stateContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 90
            } action: { _, isPastHeader in
                showsInlineTitle = isPastHeader
            }
            .grenierBackground()
            .navigationTitle(showsInlineTitle ? (vendor?.legalName ?? "Tableau") : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Notifications", systemImage: "bell") {
                        showsNotifications = true
                    }
                }
            }
            .profileToolbar()
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
            .sheet(isPresented: $showsNotifications) {
                VendorNotificationsSheet(dashboard: viewModel.state.value)
                    .presentationDetents([.medium, .large])
            }
            .task {
                async let loadedVendor = try? repositories.vendors.vendor(id: vendorId)
                await viewModel.load()
                vendor = await loadedVendor
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - États

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            DashboardContent(dashboard: .placeholder, animatesHighlight: false)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chargement du tableau de bord")
        case .empty:
            StateView(
                state: viewModel.state,
                empty: .init(
                    title: "Aucun lot ouvert",
                    systemImage: "shippingbox",
                    message: "Crée ton premier lot : les familles du quartier pourront s'y joindre et faire baisser le prix ensemble."
                )
            ) { _ in EmptyView() }
            .padding(.top, 40)
        case .failed:
            StateView(state: viewModel.state, retry: { await viewModel.load() }) { _ in EmptyView() }
                .padding(.top, 40)
        case .loaded(let dashboard):
            DashboardContent(dashboard: dashboard, animatesHighlight: !reduceMotion)
                .transition(.opacity)
        }
    }
}

// MARK: - En-tête

private struct DashboardHeader: View {
    let vendor: Vendor?
    let openOffers: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Espace vendeur")
                .textCase(.uppercase)
                .font(.footnote.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(Color.grenier)
            Text(vendor?.legalName ?? "Ferme du Québec")
                .font(.largeTitle.bold())
                .foregroundStyle(.texte)
                .redacted(reason: vendor == nil ? .placeholder : [])
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .contentTransition(.numericText())
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let kind = vendor.map { VendorKindText.title(for: $0.kind) } ?? "Vendeur"
        guard let openOffers else { return kind }
        return "\(kind) · \(openOffers) \(openOffers > 1 ? "lots ouverts" : "lot ouvert")"
    }
}

private enum VendorKindText {
    static func title(for kind: Vendor.Kind) -> String {
        switch kind {
        case .farm: "Ferme"
        case .wholesaler: "Grossiste"
        case .cooperative: "Coopérative"
        case .bakery: "Boulangerie"
        case .other: "Vendeur"
        }
    }
}

// MARK: - Contenu

private struct DashboardContent: View {
    let dashboard: VendorDashboardScreen.Dashboard
    let animatesHighlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatTiles(dashboard: dashboard)

            if let highlight = dashboard.highlight {
                HighlightBanner(highlight: highlight, animates: animatesHighlight)
            }

            if !dashboard.closingSoon.isEmpty {
                SectionTitle("Se termine bientôt")
                ClosingSoonCard(offers: dashboard.closingSoon)
            }

            SectionTitle("Lots ouverts")
            VStack(spacing: 12) {
                ForEach(dashboard.offers) { summary in
                    VendorOfferCard(summary: summary)
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(.texte)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tuiles

private struct StatTiles: View {
    let dashboard: VendorDashboardScreen.Dashboard
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            StatTile(
                title: "Revenus prévus",
                value: Money.formatRounded(dashboard.projectedRevenueCents),
                caption: "\(dashboard.totalCommittedShares) parts sur \(dashboard.totalShares)",
                accessibilityText: "Revenus prévus : \(Money.formatRounded(dashboard.projectedRevenueCents)), pour \(dashboard.totalCommittedShares) parts engagées sur \(dashboard.totalShares)."
            )
            StatTile(
                title: "Familles servies",
                value: "\(dashboard.committedHouseholds)",
                caption: neighborhoodsText,
                accessibilityText: "\(dashboard.committedHouseholds) familles servies, \(neighborhoodsText)."
            )
        }
    }

    private var neighborhoodCount: Int {
        Set(dashboard.offers.flatMap { $0.linkedOrders.map(\.group.neighborhood) }).count
    }

    private var neighborhoodsText: String {
        neighborhoodCount > 1 ? "dans \(neighborhoodCount) quartiers" : "dans \(neighborhoodCount) quartier"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let accessibilityText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            Text(value)
                .priceStyle()
                .foregroundStyle(.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: "checkmark.seal")
                .font(.title2.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.grenier)
                .frame(width: iconSize, height: iconSize)
                .symbolEffect(.bounce, value: bounce)
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
        return "\(Money.format(tiers[highlight.tierIndex].priceCents)) le \(highlight.offer.offer.shareUnit)"
    }

    private var households: Int { highlight.order.order.committedHouseholds }

    private var detail: String {
        var text = "\(highlight.offer.title)"
        if let priceText { text += " à \(priceText)" }
        text += " pour \(households) \(households > 1 ? "familles" : "famille")."
        return text
    }

    private var message: AttributedString {
        var bold = AttributedString("Palier \(highlight.tierNumber) atteint")
        bold.inlinePresentationIntent = .stronglyEmphasized
        return bold + AttributedString(" à \(highlight.groupName) : \(detail)")
    }

    private var plainMessage: String {
        "Palier \(highlight.tierNumber) atteint à \(highlight.groupName) : \(detail)"
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
                Text("Ferme \(VendorDeadline.relative(summary.offer.deadline)) · \(remainingText)")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.title), ferme \(VendorDeadline.relative(summary.offer.deadline)), \(remainingText).")
    }

    private var remainingText: String {
        let remaining = max(summary.totalShares - summary.committedShares, 0)
        if remaining == 0 { return "complet" }
        return "encore \(remaining) \(remaining > 1 ? "parts" : "part")"
    }
}

private enum VendorDeadline {
    static let locale = Locale(identifier: "fr_CA")

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
            Text(placeText)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
            Text("Ferme \(VendorDeadline.weekday(summary.offer.deadline))")
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var tierBadge: some View {
        if let number = summary.bestTierNumber {
            Text("Palier \(number)")
                .font(.footnote.bold())
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.grenier, in: .capsule)
                .fixedSize()
        } else {
            Text("En attente")
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
            Text(progressText)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .monospacedDigit()
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                Text(Money.formatRounded(summary.projectedRevenueCents))
                    .priceStyle(.priceCompact)
                    .foregroundStyle(.texte)
                    .contentTransition(.numericText(value: Double(summary.projectedRevenueCents)))
                Text("prévus")
                    .font(.caption)
                    .foregroundStyle(.texteSecondaire)
            }
        }
    }

    private var placeText: String {
        guard let first = summary.linkedOrders.first else { return "Aucun groupe encore" }
        let others = summary.linkedOrders.count - 1
        return others > 0 ? "\(first.group.name) +\(others)" : first.group.name
    }

    private var progressText: String {
        let households = summary.committedHouseholds
        if households == 0 { return "Aucune famille encore · \(summary.totalShares) parts" }
        return "\(households) \(households > 1 ? "familles" : "famille") · \(summary.committedShares) parts sur \(summary.totalShares)"
    }

    private var accessibilityText: String {
        var parts = [summary.title]
        if let number = summary.bestTierNumber {
            parts.append("palier \(number) atteint")
        } else {
            parts.append("aucun palier atteint")
        }
        parts.append(progressText)
        parts.append("\(Money.formatRounded(summary.projectedRevenueCents)) prévus")
        parts.append("\(placeText), ferme \(VendorDeadline.weekday(summary.offer.deadline))")
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
                        "Rien de neuf",
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
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var items: [(symbol: String, text: String)] {
        guard let dashboard else { return [] }
        var result: [(symbol: String, text: String)] = []
        if let highlight = dashboard.highlight {
            result.append(("checkmark.seal.fill", "Palier \(highlight.tierNumber) atteint à \(highlight.groupName) pour \(highlight.offer.title)."))
        }
        for summary in dashboard.closingSoon {
            result.append(("clock.fill", "\(summary.title) ferme \(VendorDeadline.relative(summary.offer.deadline))."))
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
    VendorDashboardScreen(onCreateOffer: {})
}

#Preview("Sombre") {
    VendorDashboardScreen(onCreateOffer: {})
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    VendorDashboardScreen(onCreateOffer: {})
        .dynamicTypeSize(.accessibility5)
}

#Preview("Vide") {
    VendorDashboardScreen(vendorId: "vendeur-sans-lot", onCreateOffer: {})
}

#Preview("Erreur") {
    VendorDashboardScreen(repositories: .fake(behavior: .failing()))
}
