import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de ImpactMetrics (RQ-128 « Impact sur Montréal »).
struct ImpactMetricsTests {
    private func entry(
        _ household: String, order: String, neighborhood: String, category: Product.Category = .grains,
        quantity: Int, measure: ShareMeasure = .mass(kilograms: 10)
    ) -> SavingsEntry {
        SavingsCalculatorTests.entry(
            household, order: order, group: "g-\(neighborhood)", neighborhood: neighborhood,
            category: category, quantity: quantity, reference: 2_000, final: 1_500, measure: measure
        )
    }

    private var entries: [SavingsEntry] {
        [
            entry("h1", order: "go1", neighborhood: "Rosemont", quantity: 2),
            entry("h1", order: "go2", neighborhood: "Rosemont", category: .legumes, quantity: 1,
                  measure: .mass(kilograms: 5)),
            entry("h2", order: "go1", neighborhood: "Rosemont", quantity: 1),
            entry("h3", order: "go3", neighborhood: "Verdun", category: .eggs, quantity: 1,
                  measure: .count(units: 12)),
        ]
    }

    private let rosemont = ImpactContext(
        subsidizedBaskets: 3, subsidizedHouseholds: 1, localVendorSpendCents: 4_500, pickupTrips: 1
    )
    private let verdun = ImpactContext(
        subsidizedBaskets: 1, subsidizedHouseholds: 1, localVendorSpendCents: 1_500, pickupTrips: 1
    )

    @Test func neighborhoodReportHasOneIndicatorPerSphereInOrder() {
        let report = ImpactMetrics.report(neighborhood: "Rosemont", entries: entries, context: rosemont)
        #expect(report.title == "Impact sur Rosemont")
        #expect(report.indicators.map(\.sphere) == ImpactSphere.allCases)
        #expect(report.indicators.allSatisfy { !$0.title.isEmpty && !$0.unit.isEmpty && !$0.explanation.isEmpty })
        #expect(report.savings.savingsCents == 2_000)
    }

    @Test func neighborhoodFormulas() throws {
        let report = ImpactMetrics.report(neighborhood: "Rosemont", entries: entries, context: rosemont)
        // Dépenses de Rosemont : 4 parts × 15 $ = 60 $.
        #expect(report.savings.spentCents == 6_000)

        let food = try #require(report.indicator(.foodSecurity))
        #expect(food.value == 3)
        #expect(food.unit == "paniers")

        let local = try #require(report.indicator(.localEconomy))
        #expect(local.value == 45)
        #expect(local.unit == "$")
        #expect(local.explanation.hasPrefix("75 %"))

        #expect(report.indicator(.neighborhoodLife)?.value == 2)

        // Emballages : 3 parts de 10 kg (9 chacune) + 1 part de 5 kg (4) = 31.
        let environment = try #require(report.indicator(.environment))
        #expect(environment.value == 31)
        #expect(environment.explanation.contains("0,9 kg"))

        // Participations : (h1, go1), (h1, go2), (h2, go1) = 3 ; 1 seul déplacement réel → 2 trajets évités.
        let mobility = try #require(report.indicator(.mobility))
        #expect(mobility.value == 2)
        #expect(mobility.explanation.contains("6 km"))

        let inclusion = try #require(report.indicator(.inclusion))
        #expect(inclusion.value == 1)
        #expect(inclusion.unit == "ménage")
        #expect(inclusion.explanation.hasPrefix("50 %"))

        // Santé : 30 kg de céréales + 5 kg de légumineuses.
        #expect(report.indicator(.health)?.value == 35)
    }

    @Test func cityReportAggregatesEveryNeighborhood() throws {
        let report = ImpactMetrics.cityReport(entries: entries, contexts: ["Rosemont": rosemont, "Verdun": verdun])
        #expect(report.scope == .city)
        #expect(report.title == "Impact sur Montréal")
        #expect(report.context == ImpactContext(
            subsidizedBaskets: 4, subsidizedHouseholds: 2, localVendorSpendCents: 6_000, pickupTrips: 2
        ))
        #expect(report.indicator(.foodSecurity)?.value == 4)
        #expect(report.indicator(.localEconomy)?.value == 60)
        #expect(report.indicator(.neighborhoodLife)?.value == 3)
        #expect(report.indicator(.environment)?.value == 31)
        #expect(report.indicator(.mobility)?.value == 2)
        #expect(report.indicator(.health)?.value == 35)
        #expect(report.indicators.count == ImpactSphere.allCases.count)
    }

    @Test func emptyDataGivesZerosWithoutCrashing() {
        let indicators = ImpactMetrics.indicators(savings: .empty, context: .empty)
        #expect(indicators.count == 7)
        #expect(indicators.allSatisfy { $0.value == 0 })
        #expect(indicators.first { $0.sphere == .localEconomy }?.explanation.hasPrefix("0 %") == true)
    }

    @Test func localSpendIsCappedAndTripsNeverGoNegative() {
        let savings = SavingsCalculator.summary(of: [entry("h1", order: "go1", neighborhood: "Rosemont", quantity: 1)])
        let context = ImpactContext(localVendorSpendCents: 99_999, pickupTrips: 10)
        #expect(ImpactMetrics.indicator(.localEconomy, savings: savings, context: context).value == 15)
        #expect(ImpactMetrics.indicator(.mobility, savings: savings, context: context).value == 0)
    }

    @Test func sphereTitlesAreFrench() {
        #expect(ImpactSphere.allCases.map(\.title) == [
            "Sécurité alimentaire", "Économie locale", "Vie de quartier", "Environnement",
            "Mobilité", "Inclusion", "Santé",
        ])
    }

    @Test func formattedValueUsesQuebecDecimals() {
        let indicator = ImpactIndicator(sphere: .health, title: "t", value: 12.5, unit: "kg", explanation: "e")
        #expect(indicator.formattedValue == "12,5")
    }
}
