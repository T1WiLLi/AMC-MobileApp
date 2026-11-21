import Charts
import SwiftUI

/// Carte « Tes économies » (maquette F6) : total du mois courant et barres des derniers mois.
/// Le mois courant est en Economie plein, les précédents en Economie léger.
struct SavingsChart: View {
    let months: [ImpactSnapshot.MonthlySaving]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.impactAnimatesOnAppear) private var animatesOnAppear
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var barCorner: CGFloat = 12
    @State private var grown = false

    init(months: [ImpactSnapshot.MonthlySaving]) {
        self.months = months
    }

    private var current: ImpactSnapshot.MonthlySaving? { months.last }
    private var isStatic: Bool { reduceMotion || !animatesOnAppear }
    private var barsAtFullHeight: Bool { isStatic || grown }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if months.isEmpty {
                Text("Tes économies apparaîtront ici après ta première cueillette.")
                    .font(.subheadline)
                    .foregroundStyle(.texteSecondaire)
            } else {
                chart
            }
        }
        .grenierCard(padding: 20)
        .task {
            guard !isStatic, !grown else { return }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 0.8)) { grown = true }
        }
    }

    @ViewBuilder
    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text("Tes économies")
                .font(.title3.bold())
                .foregroundStyle(.texte)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            AnimatedCounter(value: current?.savedCents ?? 0, format: .money)
                .priceStyle(.largeTitle.bold())
                .foregroundStyle(.economie)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.headerAccessibilityLabel(current))
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart(months) { month in
            let isCurrent = month.id == current?.id
            BarMark(
                x: .value("Mois", month.shortLabel),
                y: .value("Économies", barsAtFullHeight ? Double(month.savedCents) / 100 : 0)
            )
            .foregroundStyle(isCurrent ? Color.economie : Color.economie.opacity(0.25))
            .clipShape(.rect(cornerRadius: barCorner))
            .annotation(position: .top, spacing: 6) {
                Text(Money.formatRounded(month.savedCents))
                    .font(.caption.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Color.economie : Color.texteSecondaire)
                    .opacity(barsAtFullHeight ? 1 : 0)
            }
        }
        .chartYScale(domain: 0...Self.yMax(for: months))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.subheadline)
                    .foregroundStyle(Color.texteSecondaire)
            }
        }
        .frame(height: chartHeight)
        .accessibilityChartDescriptor(SavingsChartDescriptor(months: months))
    }

    // MARK: - Calculs (testés)

    /// Haut de l'échelle : 15 % de marge au-dessus de la plus haute barre, pour l'annotation.
    static func yMax(for months: [ImpactSnapshot.MonthlySaving]) -> Double {
        let highest = Double(months.map(\.savedCents).max() ?? 0) / 100
        return max(highest * 1.15, 1)
    }

    static func headerAccessibilityLabel(_ current: ImpactSnapshot.MonthlySaving?) -> String {
        guard let current else { return "Tes économies : aucune pour l'instant" }
        return "Tes économies en \(current.longLabel) : \(Money.formatRounded(current.savedCents))"
    }
}

/// Description du graphique pour VoiceOver (Audio Graphs).
struct SavingsChartDescriptor: AXChartDescriptorRepresentable {
    let months: [ImpactSnapshot.MonthlySaving]

    func makeChartDescriptor() -> AXChartDescriptor {
        let dollars = months.map { Double($0.savedCents) / 100 }
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Mois",
            categoryOrder: months.map(\.longLabel)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Économies en dollars",
            range: 0...max(dollars.max() ?? 0, 1),
            gridlinePositions: []
        ) { value in Money.formatRounded(Cents((value * 100).rounded())) }
        let series = AXDataSeriesDescriptor(
            name: "Tes économies",
            isContinuous: false,
            dataPoints: months.map {
                AXDataPoint(x: $0.longLabel, y: Double($0.savedCents) / 100)
            }
        )
        return AXChartDescriptor(
            title: "Tes économies par mois",
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    /// « De août à novembre, tes économies passent de 22 $ à 48 $. »
    var summary: String {
        guard let first = months.first, let last = months.last else { return "Aucune économie pour l'instant." }
        if months.count == 1 {
            return "En \(last.longLabel), tu as économisé \(Money.formatRounded(last.savedCents))."
        }
        return "De \(first.longLabel) à \(last.longLabel), tes économies passent de \(Money.formatRounded(first.savedCents)) à \(Money.formatRounded(last.savedCents))."
    }
}

#Preview("Clair") {
    ScrollView { SavingsChart(months: ImpactSnapshot.demo.monthlySavings).padding() }
        .grenierBackground()
}

#Preview("Sombre") {
    ScrollView { SavingsChart(months: ImpactSnapshot.demo.monthlySavings).padding() }
        .grenierBackground()
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    ScrollView { SavingsChart(months: ImpactSnapshot.demo.monthlySavings).padding() }
        .grenierBackground()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Vide") {
    SavingsChart(months: []).padding().grenierBackground()
}
