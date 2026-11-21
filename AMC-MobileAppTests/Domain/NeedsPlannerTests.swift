import Foundation
import Testing
@testable import AMC_MobileApp

/// T-105 : planificateur de besoins (RQ-099) et suggestions de lots (RQ-100).
/// Riz : sac de 10 kg, paliers 8 → 23,00 $, 16 → 19,90 $, épicerie 28,99 $.
/// Pommes de terre : sac de 10 kg, paliers 10 → 11,50 $, 20 → 9,90 $, épicerie 15,99 $.
/// Pommes : caisse de 5 kg, palier 5 → 11,00 $, épicerie 14,99 $.
struct NeedsPlannerTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400

    static let rice = Product(id: "rice", vendorId: "v", name: "Riz basmati", category: .grains, unit: "sac",
                              origin: "", tags: [], photoURL: nil, referenceGroceryPriceCents: 2_899)
    static let potatoes = Product(id: "potatoes", vendorId: "v", name: "Pommes de terre", category: .produce,
                                  unit: "sac", origin: "", tags: [], photoURL: nil, referenceGroceryPriceCents: 1_599)
    static let apples = Product(id: "apples", vendorId: "v", name: "Pommes", category: .produce, unit: "caisse",
                                origin: "", tags: [], photoURL: nil, referenceGroceryPriceCents: 1_499)
    static let oil = Product(id: "oil", vendorId: "v", name: "Huile de canola", category: .oils, unit: "bidon",
                             origin: "", tags: [], photoURL: nil, referenceGroceryPriceCents: 1_500)

    static func offer(_ id: String, product: String, unit: String = "sac de 10 kg", tiers: [PriceTier],
                      total: Int = 30, days: Double = 4, status: Offer.Status = .active) -> Offer {
        Offer(id: id, vendorId: "v", productId: product, totalShares: total, shareUnit: unit, tiers: tiers,
              minimumSharesToLaunch: 1, deadline: now.addingTimeInterval(days * day), zones: [], status: status)
    }

    static let riceOffer = offer("o-rice", product: "rice",
                                 tiers: [PriceTier(minShares: 8, priceCents: 2_300), PriceTier(minShares: 16, priceCents: 1_990)])
    static let potatoOffer = offer("o-potatoes", product: "potatoes",
                                   tiers: [PriceTier(minShares: 10, priceCents: 1_150), PriceTier(minShares: 20, priceCents: 990),
                                           PriceTier(minShares: 30, priceCents: 850)], days: 2)
    static let appleOffer = offer("o-apples", product: "apples", unit: "caisse de 5 kg",
                                  tiers: [PriceTier(minShares: 5, priceCents: 1_100)], days: 6)
    static let oilOffer = offer("o-oil", product: "oil", unit: "bidon de 5 L", tiers: [PriceTier(minShares: 1, priceCents: 1_200)])

    static let products = [rice, potatoes, apples, oil]

    static func plan(_ needs: [NeedItem], budget: Cents = 10_000) -> MonthlyNeedsPlan {
        MonthlyNeedsPlan(needs: needs, budgetCents: budget)
    }

    static func run(_ offers: [Offer], _ plan: MonthlyNeedsPlan, budget: Cents? = nil,
                    committed: [String: Int] = [:]) -> NeedsPlanResult {
        NeedsPlanner.suggestions(offers: offers, products: products, plan: plan, budget: budget,
                                 committedShares: committed, now: now)
    }

    // MARK: Couverture et budget

    @Test func coversNeedWithEnoughSharesAtFirstTierPrice() throws {
        let grains = NeedItem(target: .category(.grains), quantity: 20, unit: .kilograms)
        let result = Self.run([Self.riceOffer], Self.plan([grains]))

        let suggestion = try #require(result.suggestions.first)
        #expect(suggestion.shares == 2)
        #expect(suggestion.unitPriceCents == 2_300)
        #expect(suggestion.costCents == 4_600)
        #expect(suggestion.savingsCents == 1_198)
        #expect(suggestion.coveredQuantity == 20)
        #expect(result.usedBudgetCents == 4_600)
        #expect(result.remainingBudgetCents == 5_400)
        #expect(result.savingsCents == 1_198)
        #expect(result.savings.kilograms == 20)
        #expect(result.coverage[grains.id] == 1)
        #expect(result.unmatchedNeedIds.isEmpty)
    }

    @Test func budgetCapsShares() throws {
        let grains = NeedItem(target: .category(.grains), quantity: 50, unit: .kilograms)
        let result = Self.run([Self.riceOffer], Self.plan([grains], budget: 5_000))

        let suggestion = try #require(result.suggestions.first)
        #expect(suggestion.sharesToCoverNeed == 5)
        #expect(suggestion.shares == 2)
        #expect(result.usedBudgetCents == 4_600)
        #expect(abs((result.coverage[grains.id] ?? 0) - 0.4) < 1e-9)
        #expect(abs(result.budgetUsage - 0.92) < 1e-9)
    }

    @Test func explicitBudgetOverridesPlanBudget() {
        let grains = NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms)
        let result = Self.run([Self.riceOffer], Self.plan([grains], budget: 100_000), budget: 1_000)
        #expect(result.budgetCents == 1_000)
        #expect(result.suggestions.first?.fitsBudget == false)
    }

    @Test func outOfBudgetLotStaysVisibleAfterAffordableOnes() {
        let grains = NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms)
        let produce = NeedItem(target: .category(.produce), quantity: 10, unit: .kilograms)
        // 15 $ : les pommes de terre (11,50 $) passent, le riz (23 $) non.
        let result = Self.run([Self.riceOffer, Self.potatoOffer], Self.plan([grains, produce], budget: 1_500))

        #expect(result.suggestions.map(\.id) == ["o-potatoes", "o-rice"])
        #expect(result.suggestions.map(\.fitsBudget) == [true, false])
        #expect(result.suggestions[1].shares == 0)
        #expect(result.suggestions[1].costCents == 0)
        #expect(result.usedBudgetCents == 1_150)
        #expect(result.coverage[grains.id] == 0)
    }

    @Test func zeroBudgetSuggestsNothingAffordable() {
        let grains = NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms)
        let result = Self.run([Self.riceOffer], Self.plan([grains], budget: 0))
        #expect(result.suggestions.count == 1)
        #expect(result.suggestions.allSatisfy { !$0.fitsBudget })
        #expect(result.usedBudgetCents == 0)
        #expect(result.savingsCents == 0)
    }

    // MARK: Paliers

    @Test func committedSharesUnlockLowerTier() throws {
        let grains = NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms)
        let result = Self.run([Self.riceOffer], Self.plan([grains]), committed: ["o-rice": 15])
        let suggestion = try #require(result.suggestions.first)
        #expect(suggestion.shares == 1)
        #expect(suggestion.unitPriceCents == 1_990) // 15 + 1 = 16 parts : palier 2
        #expect(suggestion.savingsPercent == 31)
    }

    @Test func sharesNeverExceedAvailableShares() throws {
        let grains = NeedItem(target: .category(.grains), quantity: 100, unit: .kilograms)
        let result = Self.run([Self.riceOffer], Self.plan([grains], budget: 100_000), committed: ["o-rice": 27])
        #expect(try #require(result.suggestions.first).shares == 3)
    }

    // MARK: Classement

    @Test func bestLotWinsAndCoveredNeedGetsNoSecondLot() {
        let produce = NeedItem(target: .category(.produce), quantity: 10, unit: .kilograms)
        let result = Self.run([Self.appleOffer, Self.potatoOffer], Self.plan([produce]))
        // Pommes de terre : économie plus forte, date limite plus proche.
        #expect(result.suggestions.map(\.id) == ["o-potatoes"])
    }

    @Test func productNeedTakesPrecedenceOverCategory() {
        let produce = NeedItem(target: .category(.produce), quantity: 10, unit: .kilograms)
        let applesNeed = NeedItem(target: .product(id: "apples", name: "Pommes", category: .produce),
                                  quantity: 10, unit: .kilograms)
        let result = Self.run([Self.appleOffer, Self.potatoOffer], Self.plan([produce, applesNeed]))
        let byOffer = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.id, $0.needId) })
        #expect(byOffer["o-apples"] == applesNeed.id)
        #expect(byOffer["o-potatoes"] == produce.id)
    }

    @Test func scoreRewardsSavingsAndUrgency() {
        let need = NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms)
        let base = NeedsPlanner.score(perShare: 10, need: need, savingsPercent: 20, costCents: 1_000, budget: 10_000,
                                      deadline: Self.now.addingTimeInterval(10 * Self.day), now: Self.now)
        let cheaper = NeedsPlanner.score(perShare: 10, need: need, savingsPercent: 40, costCents: 1_000, budget: 10_000,
                                         deadline: Self.now.addingTimeInterval(10 * Self.day), now: Self.now)
        let sooner = NeedsPlanner.score(perShare: 10, need: need, savingsPercent: 20, costCents: 1_000, budget: 10_000,
                                        deadline: Self.now.addingTimeInterval(1 * Self.day), now: Self.now)
        let overBudget = NeedsPlanner.score(perShare: 10, need: need, savingsPercent: 20, costCents: 20_000, budget: 10_000,
                                            deadline: Self.now.addingTimeInterval(10 * Self.day), now: Self.now)
        let overBuy = NeedsPlanner.score(perShare: 25, need: need, savingsPercent: 20, costCents: 1_000, budget: 10_000,
                                         deadline: Self.now.addingTimeInterval(10 * Self.day), now: Self.now)
        #expect(cheaper > base)
        #expect(sooner > base)
        #expect(overBudget < base)
        #expect(overBuy < base)
        #expect((0...1).contains(base))
    }

    // MARK: Filtres et cas limites

    @Test func ignoresInactiveAndExpiredLotsAndReportsUnmatchedNeeds() {
        let grains = NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms)
        let eggs = NeedItem(target: .category(.eggs), quantity: 24, unit: .units)
        let closed = Self.offer("o-closed", product: "rice", tiers: [PriceTier(minShares: 1, priceCents: 100)], status: .closed)
        let expired = Self.offer("o-expired", product: "rice", tiers: [PriceTier(minShares: 1, priceCents: 100)], days: -1)
        let unknownProduct = Self.offer("o-unknown", product: "nope", tiers: [PriceTier(minShares: 1, priceCents: 100)])
        let result = Self.run([closed, expired, unknownProduct], Self.plan([grains, eggs]))
        #expect(result.suggestions.isEmpty)
        #expect(Set(result.unmatchedNeedIds) == [grains.id, eggs.id])
        #expect(result.overallCoverage == 0)
    }

    @Test func shareInAnotherUnitCountsAsOneShareCoveringTheNeed() throws {
        let oils = NeedItem(target: .category(.oils), quantity: 3, unit: .units)
        let result = Self.run([Self.oilOffer], Self.plan([oils]))
        let suggestion = try #require(result.suggestions.first)
        #expect(suggestion.shares == 1)
        #expect(suggestion.coveredQuantity == nil)
        #expect(result.coverage[oils.id] == 1)
    }

    @Test func litersMatchVolumeShares() throws {
        let oils = NeedItem(target: .category(.oils), quantity: 8, unit: .liters)
        let result = Self.run([Self.oilOffer], Self.plan([oils]))
        #expect(try #require(result.suggestions.first).shares == 2)
    }

    @Test func emptyPlanGivesEmptyResult() {
        let result = Self.run([Self.riceOffer], Self.plan([]))
        #expect(result.suggestions.isEmpty)
        #expect(result.coverage.isEmpty)
        #expect(result.usedBudgetCents == 0)
    }

    @Test(arguments: [(10.0, 10.0, 1), (10.1, 10.0, 2), (25.0, 10.0, 3), (0.5, 10.0, 1)])
    func sharesForRoundsUp(quantity: Double, perShare: Double, expected: Int) {
        #expect(NeedsPlanner.sharesFor(quantity: quantity, perShare: perShare) == expected)
    }

    @Test func sharesForUnknownMeasureIsOne() {
        #expect(NeedsPlanner.sharesFor(quantity: 12, perShare: nil) == 1)
    }

    @Test func unitAmountsFromShareMeasure() {
        #expect(NeedUnit.kilograms.amount(in: .mass(kilograms: 10)) == 10)
        #expect(NeedUnit.liters.amount(in: .volume(liters: 5)) == 5)
        #expect(NeedUnit.units.amount(in: .count(units: 12)) == 12)
        #expect(NeedUnit.units.amount(in: .mass(kilograms: 10)) == nil)
        #expect(NeedUnit.kilograms.amount(in: .unknown) == nil)
    }

    @Test func planRoundTripsThroughJSON() throws {
        let plan = Self.plan([
            NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms),
            NeedItem(target: .product(id: "rice", name: "Riz basmati", category: .grains), quantity: 2.5, unit: .kilograms),
        ], budget: 12_300)
        let decoded = try JSONDecoder().decode(MonthlyNeedsPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
    }
}
