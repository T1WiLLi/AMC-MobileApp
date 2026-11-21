import SwiftUI

/// Page publique d'un vendeur pour les familles (T-097, R-009) : qui il est, où il livre,
/// ce qu'il vend et les lots à rejoindre maintenant. Lecture seule, aucune donnée privée.
///
/// À pousser dans un `NavigationStack` qui enregistre `.offerDestination()` (le bouton « Rejoindre »
/// pousse une `OfferRoute`). Les dépôts viennent de `@Environment(\.appContext)`, sauf si on en passe :
///
///     NavigationLink { PublicVendorScreen(vendorId: vendor.id) } label: { … }
struct PublicVendorScreen: View {
    let vendorId: String
    /// Dépôts à utiliser ; nil = ceux de l'environnement.
    var repositories: AppRepositories?

    @Environment(\.appContext) private var context
    @State private var viewModel: PublicVendorViewModel?

    init(vendorId: String, repositories: AppRepositories? = nil) {
        self.vendorId = vendorId
        self.repositories = repositories
    }

    var body: some View {
        Group {
            if let viewModel {
                PublicVendorContent(viewModel: viewModel)
            } else {
                PublicVendorSkeleton()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = PublicVendorViewModel(vendorId: vendorId, repositories: repositories ?? context.repositories)
            }
        }
    }
}

// MARK: - Contenu

private struct PublicVendorContent: View {
    let viewModel: PublicVendorViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                PublicVendorSkeleton()
            case .failed(let error):
                ErrorStateView(error: error, retry: { await viewModel.load() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grenierBackground()
            case .empty:
                ContentUnavailableView("Producteur introuvable", systemImage: "storefront",
                                       description: Text("Ce producteur n'est plus sur Grenier."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .grenierBackground()
            case .loaded(let profile):
                PublicVendorPage(profile: profile, catalog: viewModel.catalog, openOffers: viewModel.openOffers)
                    .refreshable { await viewModel.refresh() }
            }
        }
        .navigationTitle(viewModel.profile?.name ?? String(localized: "Producteur"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile = viewModel.profile {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: String(localized: "Découvre \(profile.name) sur Grenier : des produits locaux achetés en groupe, moins cher.")) {
                        Label("Partager le producteur", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .grenierHaptic(.error, trigger: viewModel.state.error) { _, new in new != nil }
        .task { await viewModel.load() }
    }
}

private struct PublicVendorPage: View {
    let profile: PublicVendorViewModel.Profile
    let catalog: LoadState<[PublicVendorViewModel.CatalogSection]>
    let openOffers: LoadState<[PublicVendorViewModel.OpenOffer]>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VendorHero(profile: profile)
                VendorIdentity(profile: profile)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 28) {
                    if !profile.description.isEmpty {
                        AboutCard(text: profile.description)
                    }
                    if !profile.zones.isEmpty {
                        ZonesSection(zones: profile.zones)
                    }
                    OpenOffersSection(state: openOffers)
                    CatalogSectionView(state: catalog)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .grenierBackground()
    }
}

// MARK: - En-tête

/// Photo de vitrine, ou composition de symboles quand le vendeur n'en a pas.
private struct VendorHero: View {
    let profile: PublicVendorViewModel.Profile

    @ScaledMetric(relativeTo: .largeTitle) private var height: CGFloat = 220

    var body: some View {
        Group {
            if let url = profile.coverPhotoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        SymbolComposition(kind: profile.kind)
                    }
                }
            } else {
                SymbolComposition(kind: profile.kind)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .backgroundExtensionEffect()
        .accessibilityHidden(true)
    }
}

/// Illustration composée : grand symbole du type de vendeur entouré de produits.
private struct SymbolComposition: View {
    let kind: Vendor.Kind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let satellites: [(symbol: String, x: CGFloat, y: CGFloat)] = [
        ("carrot.fill", -110, -40), ("basket.fill", 110, -50), ("leaf.fill", -80, 55),
        ("shippingbox.fill", 95, 50), ("sun.max.fill", 0, -78),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.grenier.opacity(0.32), Color.economie.opacity(0.14), Color.fond],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(satellites, id: \.symbol) { item in
                Image(systemName: item.symbol)
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier.opacity(0.55))
                    .offset(x: item.x, y: item.y)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                    .opacity(appeared || reduceMotion ? 1 : 0)
            }
            Image(systemName: kind.systemImage)
                .font(.system(.largeTitle))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .frame(width: 96, height: 96)
                .background(Color.surface, in: .circle)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .symbolEffect(.bounce, value: appeared)
        }
        .onAppear {
            withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { appeared = true }
        }
    }
}

private struct VendorIdentity: View {
    let profile: PublicVendorViewModel.Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(profile.name)
                .font(.largeTitle.bold())
                .foregroundStyle(.texte)
            FlowLayout(spacing: 8) {
                Pill(title: profile.kind.title, systemImage: profile.kind.systemImage, tint: .grenier)
                if profile.isVerified {
                    Pill(title: String(localized: "Vérifié"), systemImage: "checkmark.seal.fill", tint: .economie)
                        .accessibilityLabel("Producteur vérifié par Grenier")
                }
                if let rating = profile.averageRating {
                    let text = rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_CA")))
                    Pill(title: "\(text) / 5", systemImage: "star.fill", tint: .orange)
                        .accessibilityLabel("Note moyenne \(text) sur 5")
                } else {
                    Pill(title: String(localized: "Nouveau"), systemImage: "sparkles", tint: .solidarite)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct Pill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

// MARK: - Sections

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.texte)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.grenier, in: .capsule)
                    .accessibilityLabel(FrenchPlural.count(count, String(localized: "élément")))
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct AboutCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "À propos"), systemImage: "text.quote")
            Text(text)
                .font(.body)
                .foregroundStyle(.texte)
                .frame(maxWidth: .infinity, alignment: .leading)
                .grenierCard()
        }
    }
}

private struct ZonesSection: View {
    let zones: [PublicVendorViewModel.Zone]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Livre dans"), systemImage: "map.fill")
            FlowLayout(spacing: 8) {
                ForEach(zones) { zone in
                    Label(zone.label, systemImage: "mappin.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(Color.surface, in: .capsule)
                        .accessibilityLabel("Zone desservie : \(zone.label)")
                }
            }
        }
    }
}

private struct OpenOffersSection: View {
    let state: LoadState<[PublicVendorViewModel.OpenOffer]>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Lots en cours"), systemImage: GrenierSymbol.offers, count: state.value?.count)
            switch state {
            case .loaded(let offers):
                ForEach(Array(offers.enumerated()), id: \.element.id) { index, item in
                    OpenOfferCard(item: item, isPrimary: index == 0)
                }
            case .empty:
                ContentUnavailableView {
                    ComposedSymbol(main: "calendar.badge.clock", badge: "shippingbox.fill")
                    Text("Aucun lot ouvert")
                } description: {
                    Text("Ce producteur n'a pas de lot en cours. Reviens bientôt : les nouveaux lots arrivent chaque semaine.")
                }
                .frame(maxWidth: .infinity)
                .grenierCard()
            default:
                EmptyView()
            }
        }
    }
}

private struct OpenOfferCard: View {
    let item: PublicVendorViewModel.OpenOffer
    /// Le lot le plus urgent porte la seule action principale de l'écran.
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ProductIcon(category: item.product.category)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.product.name) · \(item.offer.shareUnit)")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Label(deadlineText, systemImage: "clock.fill")
                        .font(.subheadline)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.texteSecondaire)
                }
                Spacer(minLength: 8)
                if item.maxSavingsPercent > 0 {
                    SavingsBadge(kind: .percent(item.maxSavingsPercent), compact: true)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                if let best = item.bestPriceCents {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("dès")
                            .font(.caption)
                            .foregroundStyle(.texteSecondaire)
                        Text(Money.format(best))
                            .priceStyle(.priceCompact)
                            .foregroundStyle(.texte)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("À partir de \(Money.format(best)) la part")
                }
                Spacer(minLength: 8)
                joinButton
            }
        }
        .grenierCard()
        .contextMenu {
            NavigationLink(value: item.route) {
                Label("Voir le lot", systemImage: "shippingbox")
            }
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        let link = NavigationLink(value: item.route) {
            Label("Rejoindre", systemImage: "person.badge.plus")
                .font(.headline)
                .frame(minHeight: 32)
        }
        .accessibilityHint("Ouvre le lot \(item.product.name) pour choisir ta part")
        if isPrimary {
            link.buttonStyle(.glassProminent)
        } else {
            link.buttonStyle(.glass).tint(.grenier)
        }
    }

    private var deadlineText: String {
        let relative = item.offer.deadline.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_CA")))
        return String(localized: "Clôture \(relative)")
    }
}

private struct CatalogSectionView: View {
    let state: LoadState<[PublicVendorViewModel.CatalogSection]>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Catalogue"), systemImage: "basket.fill",
                          count: state.value?.reduce(0) { $0 + $1.products.count })
            switch state {
            case .loaded(let sections):
                ForEach(sections) { section in
                    CategoryCard(section: section)
                }
            case .empty:
                ContentUnavailableView {
                    ComposedSymbol(main: "basket", badge: "sparkles")
                    Text("Catalogue en préparation")
                } description: {
                    Text("Ce producteur n'a pas encore ajouté ses produits.")
                }
                .frame(maxWidth: .infinity)
                .grenierCard()
            default:
                EmptyView()
            }
        }
    }
}

private struct CategoryCard: View {
    let section: PublicVendorViewModel.CatalogSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(section.title, systemImage: ProductIcon.symbol(for: section.category))
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
                .accessibilityAddTraits(.isHeader)
            ForEach(section.products) { product in
                if product.id != section.products.first?.id { Divider() }
                ProductRow(product: product)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(product.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.texte)
            FlowLayout(spacing: 12) {
                Label(product.unit, systemImage: "scalemass.fill")
                Label(product.origin, systemImage: "mappin")
                ForEach(product.tags, id: \.self) { tag in
                    Label(tag.publicTitle, systemImage: tag.publicSymbol)
                }
            }
            .font(.caption)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.texteSecondaire)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Icône d'état vide composée : un symbole principal et un petit badge.
private struct ComposedSymbol: View {
    let main: String
    let badge: String

    var body: some View {
        Image(systemName: main)
            .font(.largeTitle)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.grenier)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: badge)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.economie)
                    .padding(4)
                    .background(Color.surface, in: .circle)
                    .offset(x: 12, y: 8)
            }
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }
}

private extension DietaryTag {
    var publicTitle: String {
        switch self {
        case .organic: String(localized: "Bio")
        case .halal: String(localized: "Halal")
        case .kosher: String(localized: "Casher")
        case .vegetarian: String(localized: "Végétarien")
        case .vegan: String(localized: "Végane")
        case .glutenFree: String(localized: "Sans gluten")
        case .local: String(localized: "Local")
        }
    }

    var publicSymbol: String {
        switch self {
        case .organic: "leaf.fill"
        case .halal, .kosher: "checkmark.circle.fill"
        case .vegetarian, .vegan: "carrot.fill"
        case .glutenFree: "xmark.circle.fill"
        case .local: "location.fill"
        }
    }
}

// MARK: - Chargement

/// Squelette de la page pendant le premier chargement.
private struct PublicVendorSkeleton: View {
    var body: some View {
        PublicVendorPage(
            profile: .init(id: "skeleton", name: "Ferme du quartier", kind: .farm,
                           description: String(localized: "Une courte description du producteur, de ses cultures et de sa région."),
                           coverPhotoURL: nil, zones: [.init(id: "a", label: "Saint-Michel"), .init(id: "b", label: "Hochelaga")],
                           averageRating: 4.5, isVerified: true),
            catalog: .loaded([
                .init(category: .produce, products: [
                    Product(id: "skeleton-p", vendorId: "skeleton", name: "Pommes de terre", category: .produce,
                            unit: "sac de 10 kg", origin: "Québec", tags: [], photoURL: nil, referenceGroceryPriceCents: 0),
                ]),
            ]),
            openOffers: .empty
        )
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityLabel("Chargement du producteur")
    }
}

// MARK: - Mise en page en lignes

/// Place les éléments en lignes, avec retour à la ligne (pastilles, zones, étiquettes).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: maxWidth, height: nil))
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Previews

#Preview("Ferme Bio-Rive") {
    NavigationStack {
        PublicVendorScreen(vendorId: FakeData.ID.fermeRive, repositories: .fake())
            .offerDestination()
    }
}

#Preview("Les Moulins du Nord, sombre") {
    NavigationStack {
        PublicVendorScreen(vendorId: FakeData.ID.moulinsDuNord, repositories: .fake())
            .offerDestination()
    }
    .preferredColorScheme(.dark)
}

#Preview("Catalogue vide") {
    var data = FakeData.montreal
    data.products.removeAll { $0.vendorId == FakeData.ID.moulinsDuNord }
    data.offers.removeAll { $0.vendorId == FakeData.ID.moulinsDuNord }
    return NavigationStack {
        PublicVendorScreen(vendorId: FakeData.ID.moulinsDuNord, repositories: .fake(data: data))
    }
}

#Preview("Hors ligne") {
    NavigationStack {
        PublicVendorScreen(vendorId: FakeData.ID.fermeRive, repositories: .fake(behavior: .failing(.offline)))
    }
}

#Preview("Chargement") {
    NavigationStack { PublicVendorSkeleton() }
}
