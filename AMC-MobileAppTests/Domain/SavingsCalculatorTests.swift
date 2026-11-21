import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de SavingsCalculator et de ShareMeasure (RQ-089, RQ-090, RQ-092).
struct SavingsCalculatorTests {
    static let montreal = TimeZone(identifier: "America/Montreal")!

    /// Date à l'heure de Montréal.
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func entry(
        _ household: String, order: String = "go1", group: String = "g1", neighborhood: String = "Rosemont",
        category: Product.Category? = .grains, date: Date = date(2026, 10, 15), quantity: Int = 1,
        reference: Cents = 2_000, final: Cents = 1_500, measure: ShareMeasure = .mass(kilograms: 10)
    ) -> SavingsEntry {
        SavingsEntry(
            householdId: household, groupOrderId: order, groupId: group, neighborhood: neighborhood,
            productId: "p-\(order)", category: category, date: date, quantity: quantity,
            referenceUnitPriceCents: reference, finalUnitPriceCents: final, measure: measure
        )
    }

    // MARK: ShareMeasure.parse

    @Test(arguments: [
        ("10 kg", ShareMeasure.mass(kilograms: 10)),
        ("10kg", .mass(kilograms: 10)),
        ("Sac de 2,5 kg", .mass(kilograms: 2.5)),
        ("sac de 2.5 KG", .mass(kilograms: 2.5)),
        ("500 g", .mass(kilograms: 0.5)),
        ("2 x 5 kg", .mass(kilograms: 10)),
        ("2 sacs de 5 kg", .mass(kilograms: 10)),
        ("1 kilo", .mass(kilograms: 1)),
        ("3 kilogrammes", .mass(kilograms: 3)),
        ("5 L", .volume(liters: 5)),
        ("4 litres", .volume(liters: 4)),
        ("Bidon de 4 L d'huile", .volume(liters: 4)),
        ("6 × 500 ml", .volume(liters: 3)),
        ("12 unités", .count(units: 12)),
        ("12 unites", .count(units: 12)),
        ("1 caisse", .count(units: 1)),
        ("1 douzaine", .count(units: 12)),
        ("2 douzaines", .count(units: 24)),
        ("demi-douzaine", .count(units: 6)),
        ("douzaine", .count(units: 12)),
        ("kg", .mass(kilograms: 1)),
        ("caisse", .unknown),
        ("", .unknown),
        ("0 kg", .unknown),
    ])
    func parsesShareUnits(text: String, expected: ShareMeasure) {
        let measure = ShareMeasure.parse(text)
        switch (measure, expected) {
        case let (.mass(actual), .mass(wanted)), let (.volume(actual), .volume(wanted)):
            #expect(abs(actual - wanted) < 1e-9, "\(text)")
        default:
            #expect(measure == expected, "\(text)")
        }
    }

    @Test func poundsAreConvertedToKilograms() {
        #expect(abs(ShareMeasure.parse("10 lb").kilograms - 4.535_92) < 1e-6)
    }

    @Test func kilogramsAndPackagesAvoidedPerShare() {
        #expect(ShareMeasure.mass(kilograms: 10).retailPackagesAvoided == 9)
        #expect(ShareMeasure.mass(kilograms: 2.5).retailPackagesAvoided == 2)
        #expect(ShareMeasure.mass(kilograms: 1).retailPackagesAvoided == 0)
        #expect(ShareMeasure.mass(kilograms: 0.5).retailPackagesAvoided == 0)
        #expect(ShareMeasure.volume(liters: 4).kilograms == 4)
        #expect(ShareMeasure.volume(liters: 4).retailPackagesAvoided == 3)
        #expect(ShareMeasure.count(units: 12).kilograms == 0)
        #expect(ShareMeasure.count(units: 12).retailPackagesAvoided == 0)
        #expect(ShareMeasure.unknown.kilograms == 0)
    }

    // MARK: SavingsEntry

    @Test func savingsPerShareIsReferenceMinusFinalTimesQuantity() {
        let entry = Self.entry("h1", quantity: 3, reference: 2_000, final: 1_450)
        #expect(entry.savingsCents == 1_650)
        #expect(entry.spentCents == 4_350)
        #expect(entry.groceryCents == 6_000)
        #expect(entry.kilograms == 30)
        #expect(entry.packagesAvoided == 27)
    }

    @Test func savingsNeverGoNegativeAndNegativeQuantitiesCountAsZero() {
        #expect(Self.entry("h1", quantity: 2, reference: 1_000, final: 1_200).savingsCents == 0)
        let negative = Self.entry("h1", quantity: -2)
        #expect(negative.savingsCents == 0)
        #expect(negative.kilograms == 0)
    }

    @Test func entryFromModels() {
        let product = Product(
            id: "p1", vendorId: "v1", name: "Riz basmati", category: .grains, unit: "sac de 10 kg",
            origin: "Québec", tags: [], photoURL: nil, referenceGroceryPriceCents: 2_500
        )
        let share = TierEngineTests.share("h1", 2)
        let order = TierEngineTests.order(committed: 20)
        let entry = SavingsEntry(
            share: share, order: order, offer: TierEngineTests.offer, product: product,
            neighborhood: "Rosemont", date: Self.date(2026, 10, 1), finalUnitPriceCents: 990
        )
        #expect(entry.groupId == "g1")
        #expect(entry.groupOrderId == "go1")
        #expect(entry.category == .grains)
        #expect(entry.measure == .mass(kilograms: 10))
        #expect(entry.savingsCents == 3_020)
    }

    // MARK: Agrégats

    @Test func householdTotal() {
        let entries = [
            Self.entry("h1", order: "go1", quantity: 2),
            Self.entry("h1", order: "go2", quantity: 1, reference: 900, final: 600, measure: .count(units: 12)),
            Self.entry("h2", order: "go1", quantity: 5),
        ]
        let summary = SavingsCalculator.household("h1", in: entries)
        #expect(summary.savingsCents == 1_300)
        #expect(summary.shares == 3)
        #expect(summary.householdCount == 1)
        #expect(summary.participations == 2)
        #expect(summary.orderCount == 2)
        #expect(summary.kilograms == 20)
        #expect(summary.packagesAvoided == 18)
        #expect(abs(summary.packagingKilogramsAvoided - 0.54) < 1e-9)
    }

    @Test func emptySummary() {
        let summary = SavingsCalculator.summary(of: [SavingsEntry]())
        #expect(summary == .empty)
        #expect(summary.savingsRate == 0)
    }

    @Test func groupAndNeighborhoodTotals() {
        let entries = [
            Self.entry("h1", group: "g1", neighborhood: "Rosemont", quantity: 2),
            Self.entry("h2", group: "g1", neighborhood: "Rosemont", quantity: 1),
            Self.entry("h3", order: "go3", group: "g2", neighborhood: "Rosemont", quantity: 4),
            Self.entry("h4", order: "go4", group: "g3", neighborhood: "Verdun", quantity: 1),
        ]
        let group = SavingsCalculator.group("g1", in: entries)
        #expect(group.savingsCents == 1_500)
        #expect(group.householdCount == 2)

        let rosemont = SavingsCalculator.neighborhood("Rosemont", in: entries)
        #expect(rosemont.savingsCents == 3_500)
        #expect(rosemont.householdCount == 3)
        #expect(rosemont.orderCount == 2)
        #expect(abs(rosemont.savingsRate - 0.25) < 1e-9)

        let byNeighborhood = SavingsCalculator.byNeighborhood(entries)
        #expect(byNeighborhood["Verdun"]?.savingsCents == 500)
        #expect(SavingsCalculator.byGroup(entries).keys.sorted() == ["g1", "g2", "g3"])
    }

    @Test func kilogramsByCategorySkipUnknownCategoriesAndCounts() {
        let entries = [
            Self.entry("h1", category: .legumes, quantity: 2, measure: .mass(kilograms: 5)),
            Self.entry("h2", category: .eggs, quantity: 1, measure: .count(units: 12)),
            Self.entry("h3", category: nil, quantity: 1),
        ]
        let summary = SavingsCalculator.summary(of: entries)
        #expect(summary.kilogramsByCategory == [.legumes: 10])
        #expect(summary.kilograms == 20)
    }

    // MARK: Par mois

    @Test func monthlyBucketsUseMontrealTime() {
        // 31 octobre 22 h à Montréal = 1er novembre 2 h UTC : la part reste en octobre.
        let lateOctober = Self.date(2026, 10, 31, hour: 22)
        let entries = [
            Self.entry("h1", date: Self.date(2026, 11, 2), quantity: 1),
            Self.entry("h1", date: lateOctober, quantity: 2),
            Self.entry("h1", date: Self.date(2026, 9, 1, hour: 0), quantity: 1),
            Self.entry("h1", date: Self.date(2026, 11, 30, hour: 23), quantity: 0),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.montreal
        let months = SavingsCalculator.monthly(entries, calendar: calendar)
        #expect(months.map(\.id) == ["2026-09", "2026-10", "2026-11"])
        #expect(months.map(\.summary.savingsCents) == [500, 1_000, 500])
        #expect(months[1].monthStart == Self.date(2026, 10, 1, hour: 0))

        // Le même instant, en UTC, tombe en novembre : c'est bien le calendrier injecté qui décide.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(SavingsCalculator.monthly([Self.entry("h1", date: lateOctober)], calendar: utc).map(\.id) == ["2026-11"])
    }

    @Test func defaultCalendarIsMontreal() {
        #expect(SavingsCalculator.montrealCalendar.timeZone.identifier == "America/Montreal")
        let months = SavingsCalculator.monthly([Self.entry("h1", date: Self.date(2026, 10, 31, hour: 23))])
        #expect(months.map(\.id) == ["2026-10"])
    }

    @Test func monthlyTotalsAddUpToTheTotal() {
        let entries = (1...12).map { month in
            Self.entry("h\(month % 3)", order: "go\(month)", date: Self.date(2026, month, 10), quantity: month)
        }
        let months = SavingsCalculator.monthly(entries)
        #expect(months.count == 12)
        #expect(months.reduce(0) { $0 + $1.summary.savingsCents } == SavingsCalculator.summary(of: entries).savingsCents)
    }
}
