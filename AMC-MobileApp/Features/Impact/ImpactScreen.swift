import Charts
import SwiftUI

/// F6 Impact (maquette `docs/maquettes/F6-impact.png`) : tes économies, celles du quartier, le détail par produit
/// et ce que le groupe change dans les 7 sphères de Montréal (RQ-128). Branché sur `ImpactViewModel`.
struct ImpactScreen: View {
    @Environment(\.appContext) private var context
    @State private var viewModel: ImpactViewModel?

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
                        ImpactContentView(content: content)
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
            let model = ImpactViewModel(repositories: context.repositories, householdId: context.householdId, groupId: groupId)
            viewModel = model
            await model.load()
        }
    }
}

// MARK: - Contenu

private struct ImpactContentView: View {
    let content: ImpactViewModel.Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ce que ton groupe change à Montréal")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .padding(.horizontal, 4)

                MySavingsCard(content: content)

                SectionTitle("Ton quartier")
                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(symbol: GrenierSymbol.savings, tint: .economie,
                             value: Money.formatRounded(content.neighborhoodSavingsCents),
                             caption: "économisés par \(content.householdCount) familles")
                    StatTile(symbol: "scalemass.fill", tint: .grenier,
                             value: ImpactFormat.weight(content.totalKilograms),
                             caption: "achetés en direct aux producteurs")
                }

                if !content.byProduct.isEmpty {
                    SectionTitle("Économies par produit")
                    ProductSavingsChart(products: content.byProduct)
                }

                SectionTitle("Les 7 sphères de Montréal")
                Text("Chaque achat groupé fait avancer ta ville.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
                    .padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(MontrealSphere.all(from: content)) { sphere in
                        SphereTile(sphere: sphere)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct SectionTitle: View {
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

/// « Tes économies 48 $ » + parts réservées, avec compteur animé.
private struct MySavingsCard: View {
    let content: ImpactViewModel.Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: 12); amount }
            VStack(alignment: .leading, spacing: 8) { title; amount }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard(padding: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tes économies")
        .accessibilityValue("\(Money.formatRounded(content.mySavingsCents)) sur \(shares)")
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tes économies").font(.headline).foregroundStyle(.texte)
            Text("sur \(shares) vs l'épicerie").font(.subheadline).foregroundStyle(.texteSecondaire)
        }
    }

    private var amount: some View {
        AnimatedMoney(cents: content.mySavingsCents)
            .priceStyle(.largeTitle.bold())
            .foregroundStyle(.economie)
    }

    private var shares: String {
        content.myShares == 1 ? "1 part réservée" : "\(content.myShares) parts réservées"
    }
}

/// Montant qui monte de 0 à sa valeur à l'apparition (instantané avec Reduce Motion).
private struct AnimatedMoney: View {
    let cents: Cents
    @State private var shown: Cents = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(Money.formatRounded(shown))
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear(perform: update)
            .onChange(of: cents, update)
    }

    private func update() {
        if reduceMotion {
            shown = cents
        } else {
            withAnimation(.smooth(duration: 0.9)) { shown = cents }
        }
    }
}

private struct StatTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .priceStyle(.title.bold())
                .foregroundStyle(.texte)
                .minimumScaleFactor(0.8)
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

// MARK: - 7 sphères de Montréal (RQ-128)

/// Une des 7 sphères d'action de Montréal, avec le chiffre du groupe qui la fait avancer.
private struct MontrealSphere: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let caption: String

    /// Aller-retour moyen en auto vers une grande surface, en km (estimation affichée comme telle).
    private static let groceryRoundTripKilometers = 3.4

    static func all(from content: ImpactViewModel.Content) -> [MontrealSphere] {
        let producers = Set(content.byProduct.map(\.product.vendorId)).count
        let freshKilograms = content.byProduct
            .filter { [.produce, .legumes, .eggs].contains($0.product.category) }
            .reduce(0) { $0 + $1.kilograms }
        let groupedDeliveries = max(0, content.totalShares - content.byProduct.count)
        let kilometers = Int((Double(content.householdCount) * groceryRoundTripKilometers).rounded())

        return [
            MontrealSphere(title: "Sécurité alimentaire", symbol: "basket.fill", tint: .grenier,
                           value: ImpactFormat.weight(content.totalKilograms),
                           caption: "de nourriture à prix de gros"),
            MontrealSphere(title: "Économie locale", symbol: "storefront.fill", tint: .economie,
                           value: "\(producers)",
                           caption: producers == 1 ? "producteur payé en direct" : "producteurs payés en direct"),
            MontrealSphere(title: "Vie de quartier", symbol: GrenierSymbol.groups, tint: .grenier,
                           value: "\(content.householdCount)",
                           caption: "familles qui achètent ensemble"),
            MontrealSphere(title: "Environnement", symbol: GrenierSymbol.impact, tint: .economie,
                           value: "\(groupedDeliveries)",
                           caption: "livraisons individuelles évitées"),
            MontrealSphere(title: "Mobilité", symbol: "figure.walk", tint: .grenier,
                           value: "−\(kilometers) km",
                           caption: "de trajets en auto vers l'épicerie (estimé)"),
            MontrealSphere(title: "Inclusion", symbol: GrenierSymbol.solidarity, tint: .solidarite,
                           value: "\(content.suspendedBasketCount)",
                           caption: content.suspendedAmountCents > 0
                               ? "paniers suspendus offerts (\(Money.formatRounded(content.suspendedAmountCents)))"
                               : "paniers suspendus offerts"),
            MontrealSphere(title: "Santé", symbol: "carrot.fill", tint: .economie,
                           value: ImpactFormat.weight(freshKilograms),
                           caption: "de fruits, légumes et légumineuses"),
        ]
    }
}

private struct SphereTile: View {
    let sphere: MontrealSphere
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: sphere.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(sphere.tint)
                    .frame(width: iconSize, height: iconSize)
                    .background(sphere.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text(sphere.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(sphere.value)
                .priceStyle(.title2.bold())
                .foregroundStyle(.texte)
            Text(sphere.caption)
                .font(.footnote)
                .foregroundStyle(.texteSecondaire)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sphere.title)
        .accessibilityValue("\(sphere.value) \(sphere.caption)")
    }
}

// MARK: - Formatage

private enum ImpactFormat {
    private static let locale = Locale(identifier: "fr_CA")

    /// « 180 kg » ou « 1,2 t ».
    static func weight(_ kilograms: Double) -> String {
        if kilograms >= 1_000 {
            return "\((kilograms / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale))) t"
        }
        return "\(kilograms.formatted(.number.precision(.fractionLength(0)).locale(locale))) kg"
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
        .dynamicTypeSize(.accessibility5)
}
