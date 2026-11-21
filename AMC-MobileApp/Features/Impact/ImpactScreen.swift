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
                    StateView(
                        state: viewModel.state,
                        empty: .init(title: "Pas encore d'impact", systemImage: GrenierSymbol.impact,
                                     message: "Réserve ta première part : tes économies apparaîtront ici."),
                        retry: { await viewModel.load() }
                    ) { content in
                        ImpactContentView(
                            content: content,
                            snapshot: ImpactSnapshot(content: content, firstName: firstName, neighborhoodName: neighborhoodName)
                        )
                        .refreshable { await viewModel.load() }
                    }
                } else if context.groupId == nil {
                    ContentUnavailableView(
                        "Pas encore d'impact",
                        systemImage: GrenierSymbol.groups,
                        description: Text("Rejoins un groupe de ton quartier pour voir ce que vous changez ensemble.")
                    )
                } else {
                    ProgressView("Chargement…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !snapshot.neighborhoodName.isEmpty {
                    Text("\(snapshot.neighborhoodName) · \(snapshot.currentMonthName)")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .padding(.horizontal, 4)
                }

                ImpactSummaryCard(snapshot: snapshot)

                if !content.byProduct.isEmpty {
                    ImpactSectionTitle("Économies par produit")
                    ProductSavingsChart(products: content.byProduct)
                }

                ImpactSectionTitle("Ton quartier")
                LazyVGrid(columns: columns, spacing: 12) {
                    ImpactStatTile(symbol: "scalemass.fill", tint: .grenier,
                                   value: AnimatedCounter(value: snapshot.kilogramsBought, format: .integer(unit: "kg")),
                                   caption: "achetés en direct par \(ImpactFormat.plural(snapshot.households, "famille"))")
                    ImpactStatTile(symbol: "storefront.fill", tint: .economie,
                                   value: AnimatedCounter(value: snapshot.paidToProducersCents, format: .money),
                                   caption: "versés à \(ImpactFormat.plural(snapshot.producers, "producteur")) d'ici")
                }

                ImpactSectionTitle("Les 7 sphères de Montréal")
                Text("Chaque achat groupé fait avancer ta ville.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .padding(.horizontal, 4)
                SphereImpactGrid(snapshot: snapshot)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct ImpactSectionTitle: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(.texte)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            value
                .priceStyle(.title.bold())
                .foregroundStyle(.texte)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .grenierCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Graphique par produit

/// Économies du quartier par produit (le modèle n'a pas de série mensuelle pour `SavingsChart`).
private struct ProductSavingsChart: View {
    let products: [ImpactViewModel.ProductImpact]
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 44

    var body: some View {
        Chart(products) { item in
            BarMark(
                x: .value("Économie", Double(item.savingsCents) / 100),
                y: .value("Produit", item.product.name)
            )
            .foregroundStyle(item.id == products.first?.id ? Color.economie : Color.economie.opacity(0.35))
            .clipShape(.rect(cornerRadius: 8))
            .annotation(position: .trailing, alignment: .leading) {
                Text(Money.formatRounded(item.savingsCents))
                    .font(.caption.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.economie)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.subheadline).foregroundStyle(.texte)
            }
        }
        .chartXScale(domain: 0...(maxSavings * 1.3))
        .frame(height: CGFloat(products.count) * barHeight + 16)
        .accessibilityChartDescriptor(ProductSavingsDescriptor(products: products))
        .grenierCard()
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
