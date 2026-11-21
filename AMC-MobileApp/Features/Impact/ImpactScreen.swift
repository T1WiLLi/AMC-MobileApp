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
                            message: "Réserve ta première part : tes économies apparaîtront ici.",
                            scene: .firstShare
                        )
                    default:
                        // Erreur (illustrée, avec Réessayer) et contenu.
                        StateView(state: viewModel.state, retry: { await viewModel.load() }) { content in
                            ImpactContentView(
                                content: content,
                                snapshot: ImpactSnapshot(content: content, firstName: firstName, neighborhoodName: neighborhoodName)
                            )
                            .refreshable { await viewModel.load() }
                        }
                    }
                } else if context.groupId == nil {
                    ImpactIllustratedEmptyView(
                        title: "Pas encore d'impact",
                        message: "Rejoins un groupe de ton quartier pour voir ce que vous changez ensemble.",
                        scene: .noGroup
                    )
                } else {
                    ImpactSkeletonView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .grenierBackground()
            .navigationTitle("Impact")
            .profileToolbar()
        }
        .task {
            guard viewModel == nil, let groupId = context.groupId else { return }
            let repositories = context.repositories
            let model = ImpactViewModel(repositories: repositories, householdId: context.householdId, groupId: groupId)
            viewModel = model
            // Prénom et quartier ne sont que décoratifs : leur absence ne bloque pas l'écran.
            if let user = try? await repositories.users.user(id: context.userId) {
                firstName = user.displayName.split(separator: " ").first.map(String.init) ?? user.displayName
            }
            if let group = try? await repositories.groups.group(id: groupId) {
                neighborhoodName = group.neighborhood
            }
            await model.load()
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

                if !content.byProduct.isEmpty {
                    ImpactSectionTitle("Économies par produit", systemImage: "chart.bar.xaxis", tint: .economie)
                    ProductSavingsChart(products: content.byProduct)
                }

                ImpactSectionTitle("Ton quartier", systemImage: "mappin.and.ellipse", tint: .grenier)
                LazyVGrid(columns: columns, spacing: 12) {
                    ImpactStatTile(symbol: "scalemass.fill", tint: .grenier,
                                   value: AnimatedCounter(value: snapshot.kilogramsBought, format: .integer(unit: "kg")),
                                   caption: "achetés en direct par \(ImpactFormat.plural(snapshot.households, "famille"))",
                                   captionSymbol: "person.2.fill",
                                   trigger: snapshot.kilogramsBought)
                    ImpactStatTile(symbol: "storefront.fill", tint: .economie,
                                   value: AnimatedCounter(value: snapshot.paidToProducersCents, format: .money),
                                   caption: "versés à \(ImpactFormat.plural(snapshot.producers, "producteur")) d'ici",
                                   captionSymbol: "tractor.fill",
                                   trigger: Double(snapshot.paidToProducersCents))
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
        .scrollEdgeEffectStyle(.soft, for: .top)
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

private struct ImpactStatTile: View {
    let symbol: String
    let tint: Color
    let value: AnimatedCounter
    let caption: String
    let captionSymbol: String
    /// Valeur affichée : le symbole rebondit quand elle change.
    let trigger: Double

    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: trigger)
                .frame(width: iconSide, height: iconSide)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            value
                .priceStyle(.title.bold())
                .foregroundStyle(.texte)
            Label {
                Text(caption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: captionSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - En-tête et illustrations

/// Petite scène de symboles : un symbole central qui respire, entouré de satellites qui rebondissent à l'apparition.
/// Décorative (cachée à VoiceOver), immobile sous Reduce Motion et dans les captures.
private struct ImpactSymbolScene: View {
    struct Satellite: Hashable {
        let symbol: String
        let tint: Color
    }

    let center: String
    let tint: Color
    let satellites: [Satellite]

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
            Image(systemName: center)
                .font(.system(size: side * 0.32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.breathe, isActive: animates)
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
        return Image(systemName: satellite.symbol)
            .font(.system(size: side * 0.12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(satellite.tint)
            .symbolEffect(.bounce, options: .speed(0.8), value: appeared)
            .frame(width: side * 0.24, height: side * 0.24)
            .background(Color.surface, in: .circle)
            .overlay(Circle().strokeBorder(satellite.tint.opacity(0.25)))
            .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
    }
}

/// Élément fort en tête d'écran : la feuille d'impact entourée des sphères (panier, ferme, entraide, quartier…).
private struct ImpactHeroHeader: View {
    let neighborhoodName: String
    let monthName: String

    private var title: String {
        neighborhoodName.isEmpty ? "Ensemble, on change ton quartier" : "Ensemble, on change \(neighborhoodName)"
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
                    .init(symbol: "basket.fill", tint: .economie),
                    .init(symbol: "storefront.fill", tint: .grenier),
                    .init(symbol: GrenierSymbol.solidarity, tint: .solidarite),
                    .init(symbol: GrenierSymbol.groups, tint: .grenier),
                    .init(symbol: "figure.walk", tint: .grenier),
                    .init(symbol: "carrot.fill", tint: .economie)
                ]
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
                     ? "Merci : \(ImpactFormat.plural(households, "famille")) font ça avec toi."
                     : "Merci : chaque part compte.")
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
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 44

    /// Symbole du produit (même catalogue que `ProductIcon`), retrouvé par son nom sur l'axe.
    private var symbolsByName: [String: String] {
        Dictionary(products.map { ($0.product.name, ProductIcon.symbol(for: $0.product.category)) },
                   uniquingKeysWith: { first, _ in first })
    }

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

    private var chart: some View {
        Chart(products) { item in
            BarMark(
                x: .value("Économie", Double(item.savingsCents) / 100),
                y: .value("Produit", item.product.name)
            )
            .foregroundStyle(item.id == products.first?.id ? Color.economie : Color.economie.opacity(0.35))
            .clipShape(.rect(cornerRadius: 8))
            .annotation(position: .trailing, alignment: .leading) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                    Text(Money.formatRounded(item.savingsCents))
                        .fontDesign(.rounded)
                }
                .font(.caption.bold())
                .foregroundStyle(.economie)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        axisLabel(name)
                    }
                }
            }
        }
        .chartXScale(domain: 0...(maxSavings * 1.4))
        .frame(height: CGFloat(products.count) * barHeight + 16)
        .accessibilityChartDescriptor(ProductSavingsDescriptor(products: products))
    }

    private func axisLabel(_ name: String) -> some View {
        Label {
            Text(name)
        } icon: {
            Image(systemName: symbolsByName[name] ?? GrenierSymbol.offers)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.grenier)
        }
        .font(.subheadline)
        .foregroundStyle(Color.texte)
    }

    private var maxSavings: Double {
        max(1, Double(products.map(\.savingsCents).max() ?? 0) / 100)
    }
}

/// Description audio du graphique pour VoiceOver (Audio Graphs).
private struct ProductSavingsDescriptor: AXChartDescriptorRepresentable {
    let products: [ImpactViewModel.ProductImpact]

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxValue = max(1, Double(products.map(\.savingsCents).max() ?? 0) / 100)
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Produit", categoryOrder: products.map(\.product.name))
        let yAxis = AXNumericDataAxisDescriptor(title: "Économie du quartier", range: 0...maxValue, gridlinePositions: []) {
            Money.formatRounded(Cents(($0 * 100).rounded()))
        }
        let series = AXDataSeriesDescriptor(name: "Économies par produit", isContinuous: false, dataPoints: products.map {
            AXDataPoint(x: $0.product.name, y: Double($0.savingsCents) / 100)
        })
        return AXChartDescriptor(title: "Économies du quartier par produit",
                                 summary: "Économie par rapport à l'épicerie, du produit qui fait économiser le plus au moins.",
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
