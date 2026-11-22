import Charts
import SwiftUI

/// RQ-077 (T-119) : statistiques de ventes par produit, poussé depuis l'onglet Revenus du portail Vendeur.
/// Parts vendues, revenus, groupes et familles, palier moyen, économies offertes, tendance hebdomadaire
/// (barres + moyenne mobile, animées), meilleurs vendeurs et filtre de période.
/// Lit `@Environment(\.appContext)` pour les dépôts et le vendeur ; l'agrégation vit dans `ProductSalesAggregator`.
struct ProductStatsScreen: View {
    @Environment(\.appContext) private var context
    @State private var model: ProductStatsViewModel?

    var body: some View {
        Group {
            if let model {
                ProductStatsStateContent(model: model)
            } else {
                ProductStatsSkeleton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .grenierBackground()
        .navigationTitle("Ventes par produit")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard model == nil else { return }
            let created = ProductStatsViewModel(repositories: context.repositories, vendorId: context.vendorId)
            model = created
            await created.load()
        }
    }
}

/// Lien vers les statistiques, posé dans l'onglet Revenus : carte tapable qui zoome vers l'écran.
struct ProductStatsLink: View {
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 48

    var body: some View {
        NavigationLink {
            ProductStatsScreen()
                .navigationTransition(.zoom(sourceID: "product-stats", in: namespace))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .symbolEffect(.wiggle, options: .nonRepeating, value: reduceMotion ? false : appeared)
                    .frame(width: iconSide, height: iconSide)
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ventes par produit")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("Tendances, meilleurs vendeurs et économies offertes")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.texteSecondaire)
                    .accessibilityHidden(true)
            }
            .grenierCard()
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(PressableButtonStyle())
        .matchedTransitionSource(id: "product-stats", in: namespace)
        .accessibilityHint("Ouvre les statistiques de ventes de chaque produit")
        .onAppear { appeared = true }
    }
}

// MARK: - États

private struct ProductStatsStateContent: View {
    @Bindable var model: ProductStatsViewModel

    var body: some View {
        switch model.state {
        case .idle, .loading:
            ProductStatsSkeleton()
        case .empty:
            EmptyStateView(
                title: "Pas encore de ventes",
                systemImage: "chart.bar.xaxis",
                message: "Ici, tu suis chaque produit : parts vendues, revenus et économies offertes aux familles. Publie un lot pour voir tes premiers chiffres."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed, .loaded:
            StateView(state: model.state, retry: { await model.load() }) { report in
                ScrollView {
                    ProductStatsContent(report: report, model: model)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .refreshable { await model.refresh() }
            }
        }
    }
}

/// Squelette : mêmes blocs que le contenu, masqués.
private struct ProductStatsSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 12).fill(Color.surface).frame(height: 36)
                HStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 24).fill(Color.surface).frame(height: 96)
                    }
                }
                RoundedRectangle(cornerRadius: 24).fill(Color.surface).frame(height: 240)
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 24).fill(Color.surface).frame(height: 120)
                }
            }
            .padding(.horizontal, 16)
            .redacted(reason: .placeholder)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des statistiques")
    }
}

// MARK: - Contenu

private struct ProductStatsContent: View {
    let report: ProductStatsReport
    @Bindable var model: ProductStatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PeriodPicker(period: $model.period)

            SummaryGrid(report: report)
                .grenierAppear(index: 0)

            StatsSectionTitle("Tendance", systemImage: "chart.xyaxis.line", tint: .grenier)
            TrendCard(report: report, model: model)
                .grenierAppear(index: 1)

            if report.hasNoSales {
                NoSalesInPeriodCard(period: report.period) {
                    model.period = .all
                }
            } else {
                StatsSectionTitle("Meilleurs vendeurs", systemImage: "trophy.fill", tint: .economie)
                BestSellersPodium(products: report.bestSellers)
                    .grenierAppear(index: 2)
            }

            if !report.products.isEmpty {
                StatsSectionTitle("Par produit", systemImage: GrenierSymbol.offers, tint: .grenier)
                ForEach(Array(report.products.enumerated()), id: \.element.id) { index, product in
                    ProductStatsCard(
                        product: product,
                        isSelected: model.selectedProductId == product.productId
                    ) {
                        model.toggleSelection(product.productId)
                    }
                    .grenierAppear(index: index + 3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .sensoryFeedback(.selection, trigger: model.period)
        .sensoryFeedback(.selection, trigger: model.selectedProductId)
        .grenierAnimation(.smooth, value: report)
        .grenierAnimation(.snappy, value: model.selectedProductId)
    }
}

private struct PeriodPicker: View {
    @Binding var period: ProductStatsPeriod

    var body: some View {
        Picker("Période", selection: $period) {
            ForEach(ProductStatsPeriod.allCases) { option in
                Text(option.title)
                    .accessibilityLabel(option.spokenTitle)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }
}

private struct StatsSectionTitle: View {
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
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .font(.title2.bold())
        .foregroundStyle(.texte)
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Chiffres clés

private struct SummaryGrid: View {
    let report: ProductStatsReport
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(
                title: "Revenus", value: Money.format(report.totalRevenueCents),
                numeric: Double(report.totalRevenueCents), detail: report.period.spokenTitle,
                systemImage: "banknote.fill", tint: .grenier
            )
            StatTile(
                title: "Parts vendues", value: report.totalUnits.formatted(),
                numeric: Double(report.totalUnits), detail: productsDetail,
                systemImage: GrenierSymbol.offers, tint: .grenier
            )
            StatTile(
                title: "Économies offertes", value: Money.format(report.totalSavingsCents),
                numeric: Double(report.totalSavingsCents), detail: "vs l'épicerie",
                systemImage: GrenierSymbol.savings, tint: .economie
            )
            StatTile(
                title: "Familles", value: report.householdCount.formatted(),
                numeric: Double(report.householdCount), detail: groupsDetail,
                systemImage: GrenierSymbol.groups, tint: .solidarite
            )
        }
    }

    private var productsDetail: String {
        let count = report.products.filter { $0.unitsSold > 0 }.count
        return count == 1 ? "1 produit" : "\(count) produits"
    }

    private var groupsDetail: String {
        report.groupCount == 1 ? "dans 1 groupe" : "dans \(report.groupCount) groupes"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let numeric: Double
    let detail: String
    let systemImage: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : numeric)
            }
            .font(.subheadline)
            .foregroundStyle(.texteSecondaire)
            .symbolRenderingMode(.hierarchical)
            Text(value)
                .priceStyle(.priceCompact)
                .foregroundStyle(.texte)
                .contentTransition(.numericText(value: numeric))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.texteSecondaire)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(value), \(detail)")
    }
}

// MARK: - Tendance (Swift Charts : barres + moyenne mobile, animées)

private struct TrendCard: View {
    let report: ProductStatsReport
    @Bindable var model: ProductStatsViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var selectedWeek: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 200

    private var weeks: [ProductWeekPoint] { model.chartWeeks }
    private var average: [Double] { ProductSalesAggregator.movingAverage(of: weeks) }
    private var maxUnits: Double { max(Double(weeks.map(\.units).max() ?? 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProductFilterChips(products: report.products, selection: $model.selectedProductId)

            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedProduct?.name ?? "Tous les produits")
                    .font(.headline)
                    .foregroundStyle(.texte)
                    .contentTransition(.opacity)
                Spacer()
                LegendSwatch(title: "Parts", color: .grenier, isLine: false)
                LegendSwatch(title: "Moy. 3 sem.", color: .economie, isLine: true)
            }

            Chart {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    BarMark(
                        x: .value("Semaine", week.weekStart, unit: .weekOfYear),
                        y: .value("Parts", Double(week.units) * progress)
                    )
                    .foregroundStyle(Color.grenier.gradient)
                    .clipShape(.rect(cornerRadius: 6))
                    .opacity(selectedWeek == nil || isSelected(week) ? 1 : 0.4)

                    LineMark(
                        x: .value("Semaine", week.weekStart, unit: .weekOfYear),
                        y: .value("Moyenne", average[index] * progress)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.economie)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .symbol {
                        Circle().fill(Color.economie).frame(width: 6, height: 6)
                    }
                }

                if let selected = selectedPoint {
                    RuleMark(x: .value("Semaine", selected.weekStart, unit: .weekOfYear))
                        .foregroundStyle(Color.texteSecondaire.opacity(0.3))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            WeekCallout(week: selected)
                        }
                }
            }
            .chartYScale(domain: 0...(maxUnits * 1.15))
            .chartXSelection(value: $selectedWeek)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: weeks.count > 8 ? 2 : 1)) { _ in
                    AxisGridLine().foregroundStyle(Color.piste)
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.piste)
                    AxisValueLabel()
                }
            }
            .frame(height: chartHeight)
            .accessibilityChartDescriptor(TrendChartDescriptor(
                title: model.selectedProduct?.name ?? "Tous les produits", weeks: weeks
            ))

            TrendFootnote(product: model.selectedProduct, report: report)
        }
        .grenierCard()
        .sensoryFeedback(.selection, trigger: selectedWeek) { _, new in new != nil }
        .onAppear { animateIn() }
        .onChange(of: report.period) { animateIn() }
        .onChange(of: model.selectedProductId) { animateIn() }
    }

    private var selectedPoint: ProductWeekPoint? {
        guard let selectedWeek else { return nil }
        return weeks.first { isSelected($0, date: selectedWeek) }
    }

    private func isSelected(_ week: ProductWeekPoint, date: Date? = nil) -> Bool {
        guard let date = date ?? selectedWeek else { return false }
        return Calendar.current.isDate(week.weekStart, equalTo: date, toGranularity: .weekOfYear)
    }

    /// Les barres poussent depuis 0, la courbe suit ; instantané sous Reduce Motion.
    private func animateIn() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        progress = 0
        withAnimation(.spring(duration: 0.8, bounce: 0.15)) { progress = 1 }
    }
}

private struct LegendSwatch: View {
    let title: String
    let color: Color
    let isLine: Bool

    var body: some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: isLine ? 14 : 8, height: isLine ? 3 : 10)
            Text(title)
                .font(.caption)
                .foregroundStyle(.texteSecondaire)
        }
        .accessibilityHidden(true)
    }
}

/// Bulle de la semaine pointée dans le graphique.
private struct WeekCallout: View {
    let week: ProductWeekPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sem. du \(week.weekStart.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.caption)
                .foregroundStyle(.texteSecondaire)
            Text(week.units == 1 ? "1 part" : "\(week.units) parts")
                .font(.subheadline.bold())
                .foregroundStyle(.texte)
            Text(Money.format(week.revenueCents))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.grenier)
        }
        .padding(8)
        .background(Color.surface, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

/// Puces « Tous » + un produit par puce ; choisir une puce recentre le graphique sur ce produit.
private struct ProductFilterChips: View {
    let products: [ProductSalesStats]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "Tous", systemImage: "square.grid.2x2.fill", id: nil)
                ForEach(products) { product in
                    chip(title: product.name, systemImage: ProductCategorySymbol.name(for: product.category), id: product.productId)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, systemImage: String, id: String?) -> some View {
        let isOn = selection == id
        return Button {
            selection = id
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? Color.onAccent : Color.texte)
                .background(isOn ? Color.grenier : Color.piste.opacity(0.6), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct TrendFootnote: View {
    let product: ProductSalesStats?
    let report: ProductStatsReport

    var body: some View {
        let trend = product?.trend ?? ProductSalesAggregator.trend(of: report.weekly)
        Label {
            Text(text(for: trend))
        } icon: {
            TrendIcon(trend: trend)
        }
        .font(.subheadline)
        .foregroundStyle(.texteSecondaire)
    }

    private func text(for trend: ProductSalesTrend) -> String {
        switch trend {
        case .up(let percent): "En hausse de \(percent) % par rapport à la semaine de ventes précédente"
        case .down(let percent): "En baisse de \(percent) % par rapport à la semaine de ventes précédente"
        case .flat: "Stable d'une semaine de ventes à l'autre"
        case .new: "Pas encore assez de semaines pour une tendance"
        }
    }
}

private struct TrendIcon: View {
    let trend: ProductSalesTrend

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch trend {
        case .up: "arrow.up.right.circle.fill"
        case .down: "arrow.down.right.circle.fill"
        case .flat: "equal.circle.fill"
        case .new: "sparkles"
        }
    }

    private var tint: Color {
        switch trend {
        case .up: .economie
        case .down: .grenier
        case .flat, .new: .texteSecondaire
        }
    }
}

/// Graphique audio et description VoiceOver de la tendance.
private struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let weeks: [ProductWeekPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = weeks.map { "Semaine du \($0.weekStart.formatted(.dateTime.day().month(.wide)))" }
        let maxUnits = Double(max(weeks.map(\.units).max() ?? 0, 1))
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Semaine", categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(title: "Parts vendues", range: 0...maxUnits, gridlinePositions: []) {
            "\(Int($0)) parts"
        }
        let series = AXDataSeriesDescriptor(
            name: "Parts vendues par semaine",
            isContinuous: false,
            dataPoints: zip(labels, weeks).map { label, week in
                AXDataPoint(x: label, y: Double(week.units), label: Money.format(week.revenueCents))
            }
        )
        return AXChartDescriptor(
            title: "Tendance : \(title)",
            summary: "\(weeks.reduce(0) { $0 + $1.units }) parts sur \(weeks.count) semaines.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Meilleurs vendeurs

private struct BestSellersPodium: View {
    let products: [ProductSalesStats]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                if index > 0 { Divider().padding(.leading, 64) }
                PodiumRow(rank: index + 1, product: product, leaderUnits: products.first?.unitsSold ?? 1)
            }
        }
        .padding(.vertical, 4)
        .background(Color.surface, in: .rect(cornerRadius: 24))
    }
}

private struct PodiumRow: View {
    let rank: Int
    let product: ProductSalesStats
    let leaderUnits: Int

    @ScaledMetric(relativeTo: .headline) private var badgeSide: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rank == 1 ? "trophy.fill" : "medal.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(rank == 1 ? Color.economie : Color.grenier)
                .symbolEffect(.bounce, value: rank == 1 && appeared && !reduceMotion)
                .frame(width: badgeSide, height: badgeSide)
                .background((rank == 1 ? Color.economie : Color.grenier).opacity(0.12), in: .circle)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(rank)")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.onAccent)
                        .padding(4)
                        .background(Color.grenier, in: .circle)
                        .offset(x: 4, y: 4)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(product.name)
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Spacer(minLength: 8)
                    Text(product.unitsSold == 1 ? "1 part" : "\(product.unitsSold) parts")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.grenier)
                        .contentTransition(.numericText(value: Double(product.unitsSold)))
                }
                GeometryReader { proxy in
                    Capsule().fill(Color.piste)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.grenier.gradient)
                                .frame(width: proxy.size.width * share * (appeared ? 1 : 0))
                        }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            withGrenierAnimation(.smooth, reduceMotion: reduceMotion) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank)\(rank == 1 ? "er" : "e") : \(product.name), \(product.unitsSold) parts, \(Money.format(product.revenueCents))")
    }

    private var share: CGFloat {
        leaderUnits > 0 ? CGFloat(product.unitsSold) / CGFloat(leaderUnits) : 0
    }
}

/// Aucune vente sur la période : on propose d'élargir à tout l'historique.
private struct NoSalesInPeriodCard: View {
    let period: ProductStatsPeriod
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aucune vente sur cette période")
                        .font(.headline)
                        .foregroundStyle(.texte)
                    Text("Aucune part engagée — \(period.spokenTitle.lowercased()).")
                        .font(.subheadline)
                        .foregroundStyle(.texteSecondaire)
                }
            } icon: {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
            }
            if period != .all {
                Button(action: showAll) {
                    Label("Voir tout l'historique", systemImage: "clock.arrow.circlepath")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glass)
                .tint(.grenier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .grenierCard()
    }
}

// MARK: - Par produit

private struct ProductStatsCard: View {
    let product: ProductSalesStats
    let isSelected: Bool
    let select: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var iconSide: CGFloat = 44

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                header
                metrics
                if product.unitsSold > 0 {
                    Sparkline(weeks: product.weekly)
                        .frame(height: 36)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .grenierCard()
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.grenier, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isSelected ? "Retire ce produit du graphique" : "Affiche ce produit dans le graphique de tendance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(isSelected ? "Voir tous les produits" : "Voir sa tendance", systemImage: "chart.xyaxis.line", action: select)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: ProductCategorySymbol.name(for: product.category))
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.grenier)
                    .frame(width: iconSide, height: iconSide)
                    .background(Color.grenier.opacity(0.12), in: .rect(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.headline)
                    .foregroundStyle(.texte)
                Text(product.shareUnit)
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(product.revenueCents))
                    .priceStyle(.priceCompact)
                    .foregroundStyle(product.revenueCents > 0 ? Color.texte : Color.texteSecondaire)
                    .contentTransition(.numericText(value: Double(product.revenueCents)))
                TrendIcon(trend: product.trend)
                    .font(.subheadline)
            }
        }
    }

    private var metrics: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            Metric(systemImage: GrenierSymbol.offers, tint: .grenier, text: unitsText)
            Metric(systemImage: GrenierSymbol.savings, tint: .economie, text: "\(Money.format(product.savingsCents)) économisés")
            Metric(systemImage: GrenierSymbol.groups, tint: .solidarite, text: groupsText)
            Metric(systemImage: "checkmark.seal.fill", tint: .grenier, text: tierText)
        }
    }

    private var unitsText: String { product.unitsSold == 1 ? "1 part vendue" : "\(product.unitsSold) parts vendues" }

    private var groupsText: String {
        let groups = product.groupCount == 1 ? "1 groupe" : "\(product.groupCount) groupes"
        let families = product.householdCount == 1 ? "1 famille" : "\(product.householdCount) familles"
        return "\(groups) · \(families)"
    }

    private var tierText: String {
        guard let average = product.averageTier else { return "Aucun palier" }
        let formatted = average.formatted(.number.precision(.fractionLength(0...1)))
        return product.tierCount > 0 ? "Palier moyen \(formatted) / \(product.tierCount)" : "Palier moyen \(formatted)"
    }

    private var accessibilityText: String {
        "\(product.name) : \(Money.format(product.revenueCents)), \(unitsText), \(groupsText), \(tierText), "
            + "\(Money.format(product.savingsCents)) d'économies offertes"
    }
}

private struct Metric: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.texteSecondaire)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .font(.subheadline)
        .symbolRenderingMode(.hierarchical)
    }
}

/// Mini-courbe des parts par semaine, sous la carte d'un produit.
private struct Sparkline: View {
    let weeks: [ProductWeekPoint]

    var body: some View {
        Chart(weeks) { week in
            AreaMark(x: .value("Semaine", week.weekStart), y: .value("Parts", week.units))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [Color.grenier.opacity(0.25), Color.grenier.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
            LineMark(x: .value("Semaine", week.weekStart), y: .value("Parts", week.units))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.grenier)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

/// Symbole SF d'une catégorie de produit.
enum ProductCategorySymbol {
    static func name(for category: Product.Category?) -> String {
        switch category {
        case .grains: "takeoutbag.and.cup.and.straw.fill"
        case .legumes: "leaf.fill"
        case .oils: "drop.fill"
        case .flour: "bag.fill"
        case .canned: "cylinder.fill"
        case .eggs: "oval.portrait.fill"
        case .meat: "fork.knife"
        case .produce: "carrot.fill"
        case .household: "sparkles"
        case nil: GrenierSymbol.offers
        }
    }
}

// MARK: - Données de démo

#if DEBUG
extension FakeData {
    /// Historique de 10 semaines pour les previews : Les Moulins du Nord vend riz, lentilles et farine.
    static let productStatsDemo: FakeData = {
        var data = FakeData.montreal
        let vendor = FakeData.ID.moulinsDuNord
        let week: TimeInterval = 7 * 86_400
        let now = Date.now
        data.products += [
            Product(id: "product-lentilles", vendorId: vendor, name: "Lentilles vertes", category: .legumes,
                    unit: "sac de 5 kg", origin: "Saskatchewan", tags: [.vegan], photoURL: nil,
                    referenceGroceryPriceCents: 1_899),
            Product(id: "product-farine", vendorId: vendor, name: "Farine biologique", category: .flour,
                    unit: "sac de 10 kg", origin: "Mirabel, QC", tags: [.organic, .local], photoURL: nil,
                    referenceGroceryPriceCents: 2_499),
        ]
        let groups = [FakeData.ID.saintMichel, FakeData.ID.hochelaga]
        let plan: [(product: String, weeksAgo: Int, shares: [Int], tier: Int)] = [
            (FakeData.ID.rice, 9, [10, 6], 0), (FakeData.ID.rice, 7, [14, 9], 0), (FakeData.ID.rice, 5, [18, 12], 1),
            (FakeData.ID.rice, 3, [20, 15], 1), (FakeData.ID.rice, 1, [22, 17], 1),
            ("product-lentilles", 8, [6, 4], 0), ("product-lentilles", 6, [9, 0], 0),
            ("product-lentilles", 4, [11, 8], 1), ("product-lentilles", 2, [12, 10], 1),
            ("product-farine", 6, [5, 0], 0), ("product-farine", 2, [8, 6], 0),
        ]
        for (index, entry) in plan.enumerated() {
            let offerId = "offer-demo-\(index)"
            let reference = data.products.first { $0.id == entry.product }?.referenceGroceryPriceCents ?? 2_000
            data.offers.append(Offer(
                id: offerId, vendorId: vendor, productId: entry.product, totalShares: 60, shareUnit: "sac",
                tiers: [PriceTier(minShares: 8, priceCents: reference * 80 / 100),
                        PriceTier(minShares: 16, priceCents: reference * 68 / 100)],
                minimumSharesToLaunch: 8, deadline: now.addingTimeInterval(-Double(entry.weeksAgo) * week),
                zones: ["f25d"], status: .closed
            ))
            for (groupIndex, shares) in entry.shares.enumerated() where shares > 0 {
                data.groupOrders.append(GroupOrder(
                    id: "order-demo-\(index)-\(groupIndex)", groupId: groups[groupIndex], offerId: offerId,
                    status: .delivered, currentTierIndex: shares >= 16 ? 1 : (shares >= 8 ? entry.tier : nil),
                    committedShares: shares, committedHouseholds: max(1, shares * 2 / 3),
                    pickupPointId: nil, pickupSlots: []
                ))
            }
        }
        return data
    }()
}

private extension AppContext {
    static func statsPreview(_ repositories: AppRepositories, vendorId: String = FakeData.ID.moulinsDuNord) -> AppContext {
        var context = AppContext.instant
        context.repositories = repositories
        context.vendorId = vendorId
        return context
    }
}
#endif

#Preview("Clair") {
    NavigationStack { ProductStatsScreen() }
        .environment(\.appContext, .statsPreview(.fake(data: .productStatsDemo)))
}

#Preview("Sombre") {
    NavigationStack { ProductStatsScreen() }
        .environment(\.appContext, .statsPreview(.fake(data: .productStatsDemo)))
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    NavigationStack { ProductStatsScreen() }
        .environment(\.appContext, .statsPreview(.fake(data: .productStatsDemo)))
        .dynamicTypeSize(.accessibility5)
}

#Preview("Vide") {
    NavigationStack { ProductStatsScreen() }
        .environment(\.appContext, .statsPreview(.fake(behavior: .instant), vendorId: "vendor-inconnu"))
}

#Preview("Hors ligne") {
    NavigationStack { ProductStatsScreen() }
        .environment(\.appContext, .statsPreview(.fake(behavior: .failing(.offline))))
}

#Preview("Lien Revenus") {
    NavigationStack {
        ProductStatsLink().padding()
    }
    .environment(\.appContext, .statsPreview(.fake(data: .productStatsDemo)))
}
