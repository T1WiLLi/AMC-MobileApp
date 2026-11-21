import Foundation
import Testing
@testable import AMC_MobileApp

/// Normalise les espaces (insécables, fines) pour comparer les textes formatés.
@MainActor private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

@MainActor
struct ImpactSnapshotTests {
    @Test func demoMatchesDesignSystem() {
        let demo = ImpactSnapshot.demo
        #expect(demo.firstName == "Amina")
        #expect(demo.currentMonthSavedCents == 4_800)
        #expect(demo.neighborhoodSavedCents == 390_000)
        #expect(demo.suspendedBasketsOffered == 12)
        #expect(demo.households == 24)
        #expect(demo.monthlySavings.map(\.savedCents) == [2_200, 3_100, 3_900, 4_800])
        #expect(demo.currentMonthName == "novembre")
    }

    @Test func monthLabelsAreFrench() {
        #expect(ImpactSnapshot.demo.monthlySavings.map(\.shortLabel) == ["août", "sept.", "oct.", "nov."])
    }

    @Test func plural() {
        #expect(plain(ImpactFormat.plural(1, "famille")) == "1 famille")
        #expect(plain(ImpactFormat.plural(24, "famille")) == "24 familles")
        #expect(plain(ImpactFormat.plural(12, "panier suspendu offert", "paniers suspendus offerts")) == "12 paniers suspendus offerts")
    }
}

@MainActor
struct CounterFormatTests {
    @Test func money() {
        #expect(plain(CounterFormat.money.string(for: 4_800)) == "48 $")
        #expect(plain(CounterFormat.money.string(for: 390_000)) == "3 900 $")
    }

    @Test func numbers() {
        #expect(CounterFormat.integer().string(for: 12) == "12")
        #expect(plain(CounterFormat.integer(unit: "kg").string(for: 310)) == "310 kg")
        #expect(plain(CounterFormat.decimal(unit: "t").string(for: 1.2)) == "1,2 t")
        #expect(plain(CounterFormat.percent.string(for: 0.62)) == "62 %")
    }

    @Test func reduction() {
        #expect(plain(CounterFormat.reduction(unit: "km").string(for: 41)) == "−41 km")
        #expect(plain(CounterFormat.reduction(unit: "km").string(for: 0)) == "0 km")
        #expect(CounterFormat.reduction(unit: "km").accessibilityString(for: 41) == "41 km en moins")
    }
}

@MainActor
struct SphereImpactTests {
    @Test func sevenSpheresWithSymbolsAndSentences() {
        #expect(ImpactSphere.allCases.count == 7)
        for sphere in ImpactSphere.allCases {
            #expect(!sphere.systemImage.isEmpty)
            #expect(!sphere.metric(in: .demo).sentence.isEmpty)
        }
    }

    @Test func metricsComeFromSnapshot() {
        let demo = ImpactSnapshot.demo
        #expect(plain(ImpactSphere.foodSecurity.metric(in: demo).valueText) == "3 900 $")
        #expect(plain(ImpactSphere.foodSecurity.metric(in: demo).sentence) == "économisés par 24 familles, et 12 paniers suspendus offerts")
        #expect(plain(ImpactSphere.localEconomy.metric(in: demo).sentence).contains("6 fermes du Québec pour 1,2 t"))
        #expect(plain(ImpactSphere.mobility.metric(in: demo).valueText) == "−41 km")
        #expect(plain(ImpactSphere.health.metric(in: demo).valueText) == "62 %")
        #expect(ImpactSphere.inclusion.metric(in: demo).valueText == "9")
    }

    @Test func rowsPairSpheresAndKeepLastAlone() {
        let rows = SphereImpactGrid.rows(of: ImpactSphere.allCases)
        #expect(rows.map(\.count) == [2, 2, 2, 1])
        #expect(rows.last == [.health])
        #expect(SphereImpactGrid.rows(of: []).isEmpty)
    }
}

@MainActor
struct SavingsChartTests {
    @Test func yScaleLeavesRoomForAnnotation() {
        #expect(SavingsChart.yMax(for: ImpactSnapshot.demo.monthlySavings) == 48 * 1.15)
        #expect(SavingsChart.yMax(for: []) == 1)
    }

    @Test func accessibilityTexts() {
        let months = ImpactSnapshot.demo.monthlySavings
        #expect(plain(SavingsChart.headerAccessibilityLabel(months.last)) == "Tes économies en novembre : 48 $")
        #expect(plain(SavingsChartDescriptor(months: months).summary) == "De août à novembre, tes économies passent de 22 $ à 48 $.")
        #expect(SavingsChartDescriptor(months: []).summary == "Aucune économie pour l'instant.")
    }

    @Test func descriptorHasOnePointPerMonth() {
        let descriptor = SavingsChartDescriptor(months: ImpactSnapshot.demo.monthlySavings).makeChartDescriptor()
        #expect(descriptor.series.first?.dataPoints.count == 4)
    }
}

@MainActor
struct ImpactSummaryCardTests {
    @Test func texts() {
        let card = ImpactSummaryCard(snapshot: .demo)
        #expect(card.greeting == "Bravo Amina !")
        #expect(card.subtitle == "Novembre à Parc-Extension")
        #expect(plain(card.accessibilitySummary) == "Amina, tu as économisé 48 $ ce mois-ci. Ton quartier a économisé 3 900 $. 12 paniers suspendus offerts.")
    }
}
