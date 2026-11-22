import Charts
import SwiftUI

/// F6 Impact (maquette `docs/maquettes/F6-impact.png`) : tes économies, celles du quartier, le détail par produit
/// et ce que le groupe change dans les 7 sphères de Montréal (RQ-128). Branché sur `ImpactViewModel`,
/// affiché avec les composants de `Features/Impact/Components/` via `ImpactSnapshot`.
struct ImpactScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: ImpactViewModel?
    @State private var firstName = ""
    @State private var neighborhoodName = ""

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    switch viewModel.state {
                    case .idle, .loading:
                        ImpactSkeletonView()
                    case .empty:
                        ImpactIllustratedEmptyView(
                            title: "Pas encore d'impact",
                            message: "Cette page montre l'argent que tu économises et ce que ton groupe change dans le quartier. Réserve ta première part pour voir tes premiers chiffres.",
                            scene: .firstShare,
                            action: .browseOffers
                        )
                    default:
                        // Erreur (illustrée, avec Réessayer) et contenu.
                        StateView(state: viewModel.state, retry: { await load(viewModel) }) { content in
                            ImpactContentView(
                                content: content,
                                snapshot: ImpactSnapshot(content: content, firstName: firstName, neighborhoodName: neighborhoodName)
                            )
                            .refreshable { await load(viewModel) }
                        }
                    }
                } else if context.isResolved && !context.hasGroup {
                    ImpactIllustratedEmptyView(
                        title: "Pas encore d'impact",
                        message: "Rejoins un groupe de ton quartier pour voir ce que vous changez ensemble.",
                        scene: .noGroup,
                        action: .findGroup
                    )
                } else {
                    ImpactSkeletonView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Impact")
            .profileToolbar()
            .infoToolbarButton(.impact)
        }
        .task(id: context.groupId) {
            guard viewModel == nil, context.hasGroup, let groupId = context.groupId else { return }
            let model = ImpactViewModel(repositories: context.repositories, householdId: context.householdId, groupId: groupId)
            viewModel = model
            await load(model)
        }
    }

    /// Charge l'impact, le prénom et le quartier en parallèle. Rejoué par Réessayer et par l'actualisation :
    /// un premier chargement interrompu ne laisse plus « Bravo ! » sans prénom ni « Novembre à » sans quartier.
    private func load(_ model: ImpactViewModel) async {
        guard let groupId = context.groupId else { return }
        let repositories = context.repositories, userId = context.userId
        // Prénom et quartier ne sont que décoratifs : leur absence ne bloque pas l'écran.
        async let user = try? repositories.users.user(id: userId)
        async let group = try? repositories.groups.group(id: groupId)
        await model.load()
        if let user = await user {
            firstName = user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName
        }
        if let group = await group {
            neighborhoodName = group.neighborhood
        }
    }
}

// MARK: - Contenu

private struct ImpactContentView: View {
    let content: ImpactViewModel.Content
    let snapshot: ImpactSnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ImpactHeroHeader(neighborhoodName: snapshot.neighborhoodName, monthName: snapshot.currentMonthName)

                ImpactSectionTitle("Ce mois-ci", systemImage: "calendar", tint: .economie)
                ImpactSummaryCard(snapshot: snapshot)
                    .guidedTourAnchor(.impact)

                if !content.byProduct.isEmpty {
                    ImpactSectionTitle("Économies par produit", systemImage: "chart.bar.xaxis", tint: .economie)
                    ProductSavingsChart(products: content.byProduct)
                }

                ImpactSectionTitle("Ton quartier", systemImage: "mappin.and.ellipse", tint: .grenier)
                LazyVGrid(columns: columns, spacing: 12) {
                    GrenierStatTile(systemImage: "scalemass.fill", tint: .grenier, style: .card, icon: .badge,
                                    detail: Text(String(localized: "achetés en direct par \(ImpactFormat.plural(snapshot.households, "famille"))")),
                                    detailSystemImage: "person.2.fill",
                                    numericValue: snapshot.kilogramsBought) {
                        AnimatedCounter(value: snapshot.kilogramsBought, format: .integer(unit: "kg"))
                    }
                    GrenierStatTile(systemImage: "storefront.fill", tint: .economie, style: .card, icon: .badge,
                                    detail: Text(String(localized: "versés à \(ImpactFormat.plural(snapshot.producers, "producteur")) d'ici")),
                                    detailSystemImage: "tractor.fill",
                                    numericValue: Double(snapshot.paidToProducersCents)) {
                        AnimatedCounter(value: snapshot.paidToProducersCents, format: .money)
                    }
                }

                ImpactSectionTitle("Les 7 sphères de Montréal", systemImage: "building.2.fill", tint: .grenier)
                Label {
                    Text("Chaque achat groupé fait avancer ta ville.")
                } icon: {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .padding(.horizontal, 4)
                SphereImpactGrid(snapshot: snapshot)

                // RQ-093 (T-114) : classement solidaire des arrondissements (section autonome).
                SolidarityLeaderboardSection()

                ImpactThanksFooter(households: snapshot.households)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .grenierScrollEdge()
        .symbolEffectsRemoved(reduceMotion)
    }
}

/// Titre de section : toujours un symbole teinté devant le texte.
private struct ImpactSectionTitle: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.texte)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.title2.bold())
        .padding(.top, 12)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - En-tête et illustrations

/// Petite scène de symboles : un symbole central qui respire, entouré de satellites qui rebondissent à l'apparition.
/// Un satellite (ou le centre) peut montrer une photo ronde à la place du symbole (T-186, crédits dans `docs/credits.md`).
/// Décorative (cachée à VoiceOver), immobile sous Reduce Motion et dans les captures.
private struct ImpactSymbolScene: View {
    struct Satellite: Hashable {
        let symbol: String
        let tint: Color
        /// Nom d'un asset photo ; sans photo, le symbole s'affiche.
        var photo: String? = nil
    }

    let center: String
    let tint: Color
    let satellites: [Satellite]
    /// Photo du centre, à la place du symbole `center`.
    var centerPhoto: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.impactAnimatesOnAppear) private var animatesOnAppear
    @ScaledMetric(relativeTo: .largeTitle) private var scaledSide: CGFloat = 150
    @State private var appeared = false

    /// Plafonnée pour qu'en AX5 la scène ne prenne pas tout l'écran.
    private var side: CGFloat { min(scaledSide, 220) }
    private var animates: Bool { !reduceMotion && animatesOnAppear }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.10))
            Circle()
                .strokeBorder(tint.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                .padding(side * 0.12)
            if let centerPhoto {
                Image(centerPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side * 0.46, height: side * 0.46)
                    .clipShape(.circle)
                    .overlay(Circle().strokeBorder(Color.surface, lineWidth: 3))
                    .shadow(color: tint.opacity(0.25), radius: 6, y: 2)
            } else {
                Image(systemName: center)
                    .font(.system(size: side * 0.32, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .symbolEffect(.breathe, isActive: animates)
            }
            ForEach(Array(satellites.enumerated()), id: \.offset) { index, satellite in
                satelliteView(satellite, index: index)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task {
            guard animates else { return }
            try? await Task.sleep(for: .milliseconds(300))
            appeared = true
        }
    }

    private func satelliteView(_ satellite: Satellite, index: Int) -> some View {
        let angle = Angle.degrees(-90 + Double(index) * 360 / Double(max(satellites.count, 1)))
        let radius = side * 0.44
        return satelliteContent(satellite)
            .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
    }

    @ViewBuilder private func satelliteContent(_ satellite: Satellite) -> some View {
        if let photo = satellite.photo {
            // Une photo ne rebondit pas comme un symbole : elle grossit doucement à l'apparition.
            Image(photo)
                .resizable()
                .scaledToFill()
                .frame(width: side * 0.26, height: side * 0.26)
                .clipShape(.circle)
                .overlay(Circle().strokeBorder(Color.surface, lineWidth: 2))
                .overlay(Circle().strokeBorder(satellite.tint.opacity(0.35)).padding(-1))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .scaleEffect(animates && !appeared ? 0.7 : 1)
                .animation(.spring(duration: 0.5, bounce: 0.4), value: appeared)
        } else {
            Image(systemName: satellite.symbol)
                .font(.system(size: side * 0.12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(satellite.tint)
                .symbolEffect(.bounce, options: .speed(0.8), value: appeared)
                .frame(width: side * 0.24, height: side * 0.24)
                .background(Color.surface, in: .circle)
                .overlay(Circle().strokeBorder(satellite.tint.opacity(0.25)))
        }
    }
}

/// Élément fort en tête d'écran : la feuille d'impact entourée des sphères (panier, ferme, entraide, quartier…).
private struct ImpactHeroHeader: View {
    let neighborhoodName: String
    let monthName: String

    private var title: String {
        neighborhoodName.isEmpty ? String(localized: "Ensemble, on change ton quartier") : String(localized: "Ensemble, on change \(neighborhoodName)")
    }

    private var capitalizedMonth: String {
        guard let first = monthName.first else { return monthName }
        return first.uppercased() + monthName.dropFirst()
    }

    var body: some View {
        VStack(spacing: 14) {
            ImpactSymbolScene(
                center: GrenierSymbol.impact,
                tint: .economie,
                satellites: [
                    .init(symbol: "basket.fill", tint: .economie, photo: "ImpactPanier"),
                    .init(symbol: "storefront.fill", tint: .grenier, photo: "IntroSolution"),
                    .init(symbol: GrenierSymbol.solidarity, tint: .solidarite, photo: "ImpactPartage"),
                    .init(symbol: GrenierSymbol.groups, tint: .grenier, photo: "ImpactBasilic"),
                    .init(symbol: "figure.walk", tint: .grenier, photo: "ImpactFilet"),
                    .init(symbol: "carrot.fill", tint: .economie, photo: "ImpactCarottes")
                ],
                centerPhoto: "ImpactSacs"
            )
            .padding(.top, 8)

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.texte)
                .multilineTextAlignment(.center)

            if !monthName.isEmpty {
                Label {
                    Text(capitalizedMonth)
                } icon: {
                    Image(systemName: "calendar")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.economie)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.texteSecondaire)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Fin de page (état de succès) : un sceau qui rebondit et un merci.
private struct ImpactThanksFooter: View {
    let households: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.economie)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            Label {
                Text(households > 1
                     ? String(localized: "Merci : \(ImpactFormat.plural(households, "famille")) font ça avec toi.")
                     : String(localized: "Merci : chaque part compte."))
            } icon: {
                Image(systemName: GrenierSymbol.solidarity)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.solidarite)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.texteSecondaire)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear { appeared = true }
    }
}

/// État vide illustré : une scène de symboles et une explication.
private struct ImpactIllustratedEmptyView: View {
    enum Scene {
        /// Groupe rejoint mais aucune part : un panier vide entouré de ce qu'il pourrait contenir.
        case firstShare
        /// Pas encore de groupe : le quartier entouré de ses voisins.
        case noGroup
    }

    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let scene: Scene
    /// Prochaine étape proposée (rejoindre un groupe, voir les lots).
    var action: FamilyCallToAction.Destination?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                illustration
            }
        } description: {
            Text(message)
        } actions: {
            if let action {
                FamilyCallToAction(destination: action)
            }
        }
        .symbolEffectsRemoved(reduceMotion)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var illustration: some View {
        switch scene {
        case .firstShare:
            ImpactSymbolScene(center: "basket", tint: .economie, satellites: [
                .init(symbol: "carrot.fill", tint: .economie),
                .init(symbol: GrenierSymbol.impact, tint: .economie),
                .init(symbol: "storefront.fill", tint: .grenier),
                .init(symbol: GrenierSymbol.solidarity, tint: .solidarite)
            ])
        case .noGroup:
            ImpactSymbolScene(center: GrenierSymbol.groups, tint: .grenier, satellites: [
                .init(symbol: GrenierSymbol.home, tint: .grenier),
                .init(symbol: GrenierSymbol.impact, tint: .economie),
                .init(symbol: "mappin.and.ellipse", tint: .grenier),
                .init(symbol: GrenierSymbol.solidarity, tint: .solidarite)
            ])
        }
    }
}

/// Chargement : la vraie mise en page en squelette, plutôt qu'un spinner seul.
private struct ImpactSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ImpactSummaryCard(snapshot: .demo)
                SphereImpactGrid(snapshot: .demo)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .redacted(reason: .placeholder)
        .environment(\.impactAnimatesOnAppear, false)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de ton impact")
    }
}

// MARK: - Graphique par produit

/// Économies du quartier par produit (le modèle n'a pas de série mensuelle pour `SavingsChart`).
private struct ProductSavingsChart: View {
    let products: [ImpactViewModel.ProductImpact]
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Ce que le quartier a économisé par rapport à l'épicerie")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "cart.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.economie)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)

            chart
        }
        .grenierCard()
    }

    /// Une ligne par produit : nom et montant sur la même ligne, barre en dessous.
    /// (Swift Charts décalait les libellés longs de l'axe Y par rapport à leur barre sur iPhone.)
    private var chart: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(products) { item in
                ProductSavingsRow(
                    name: item.product.name,
                    symbol: ProductIcon.symbol(for: item.product),
                    savingsCents: item.savingsCents,
                    fraction: Double(item.savingsCents) / 100 / maxSavings,
                    isTop: item.id == products.first?.id,
                    barHeight: barHeight
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityChartDescriptor(ProductSavingsDescriptor(products: products))
    }

    private var maxSavings: Double {
        max(1, Double(products.map(\.savingsCents).max() ?? 0) / 100)
    }
}

private struct ProductSavingsRow: View {
    let name: String
    let symbol: String
    let savingsCents: Cents
    /// Longueur de la barre, de 0 à 1 (1 = produit qui fait le plus économiser).
    let fraction: Double
    let isTop: Bool
    let barHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text(name)
                        .foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.grenier)
                }
                .font(.subheadline)
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                    Text(Money.formatRounded(savingsCents))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                }
                .font(.caption.bold())
                .foregroundStyle(.economie)
                .fixedSize()
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(isTop ? Color.economie : Color.economie.opacity(0.35))
                    .frame(width: max(barHeight, proxy.size.width * (isShown ? fraction : 0)))
            }
            .frame(height: barHeight)
            .background(Color.economie.opacity(0.08), in: .capsule)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { isShown = true }
        }
    }
}

/// Description audio du graphique pour VoiceOver (Audio Graphs).
private struct ProductSavingsDescriptor: AXChartDescriptorRepresentable {
    let products: [ImpactViewModel.ProductImpact]

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxValue = max(1, Double(products.map(\.savingsCents).max() ?? 0) / 100)
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Produit"), categoryOrder: products.map(\.product.name))
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Économie du quartier"), range: 0...maxValue, gridlinePositions: []) {
            Money.formatRounded(Cents(($0 * 100).rounded()))
        }
        let series = AXDataSeriesDescriptor(name: String(localized: "Économies par produit"), isContinuous: false, dataPoints: products.map {
            AXDataPoint(x: $0.product.name, y: Double($0.savingsCents) / 100)
        })
        return AXChartDescriptor(title: String(localized: "Économies du quartier par produit"),
                                 summary: String(localized: "Économie par rapport à l'épicerie, du produit qui fait économiser le plus au moins."),
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

// MARK: - Previews

/// Réserve la part d'Amina avant d'afficher l'écran, pour que « Tes économies » ne soit pas à 0.
private struct ImpactPreviewHost: View {
    @State private var isReady = false

    var body: some View {
        if isReady {
            ImpactScreen()
        } else {
            ProgressView().task {
                _ = try? await AppContext.instant.repositories.groupOrders.setShare(
                    quantity: 2, householdId: FakeData.ID.aminaHousehold, groupOrderId: FakeData.ID.potatoOrder
                )
                isReady = true
            }
        }
    }
}

#Preview("Clair") {
    ImpactPreviewHost()
        .environment(\.appContext, .instant)
}

#Preview("Sombre") {
    ImpactPreviewHost()
        .environment(\.appContext, .instant)
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ImpactPreviewHost()
        .environment(\.appContext, .instant)
        .environment(\.impactAnimatesOnAppear, false)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Chargement") {
    ImpactSkeletonView()
        .grenierBackground()
}

#Preview("Vide") {
    ImpactIllustratedEmptyView(title: "Pas encore d'impact",
                               message: "Réserve ta première part : tes économies apparaîtront ici.",
                               scene: .firstShare)
        .grenierBackground()
}
