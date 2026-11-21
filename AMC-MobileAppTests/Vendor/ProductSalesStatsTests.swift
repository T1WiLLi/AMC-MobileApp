import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-077 (T-119) : agrégation des ventes par produit.
struct ProductSalesStatsTests {
    private static let calendar = SavingsCalculator.montrealCalendar
    /// Mercredi 18 novembre 2026, midi à Montréal.
    private static let now: Date = {
        var components = DateComponents(year: 2026, month: 11, day: 18, hour: 12)
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)!
    }()
    private static let week: TimeInterval = 7 * 86_400

    private static func product(_ id: String, _ name: String, reference: Cents = 2_000) -> Product {
        Product(id: id, vendorId: "v", name: name, category: .grains, unit: "sac", origin: "QC", tags: [],
                photoURL: nil, referenceGroceryPriceCents: reference)
    }

    /// Lot à deux paliers : 8 parts → 16,00 $, 16 parts → 14,00 $.
    private static func offer(_ id: String, product: String, weeksAgo: Double, status: Offer.Status = .closed) -> Offer {
        Offer(id: id, vendorId: "v", productId: product, totalShares: 60, shareUnit: "sac de 10 kg",
              tiers: [PriceTier(minShares: 16, priceCents: 1_400), PriceTier(minShares: 8, priceCents: 1_600)],
              minimumSharesToLaunch: 8, deadline: now.addingTimeInterval(-weeksAgo * week), zones: [], status: status)
    }

    private static func order(
        _ id: String, offer: String, group: String, shares: Int, households: Int, tier: Int?,
        status: GroupOrder.Status = .delivered
    ) -> GroupOrder {
        GroupOrder(id: id, groupId: group, offerId: offer, status: status, currentTierIndex: tier,
                   committedShares: shares, committedHouseholds: households, pickupPointId: nil, pickupSlots: [])
    }

    private static let products = [product("rice", "Riz", reference: 2_000), product("flour", "Farine", reference: 1_500)]

    private static let offers = [
        offer("rice-1", product: "rice", weeksAgo: 2),
        offer("rice-2", product: "rice", weeksAgo: 1),
        offer("flour-1", product: "flour", weeksAgo: 1),
        offer("rice-old", product: "rice", weeksAgo: 8),
        offer("draft", product: "flour", weeksAgo: 1, status: .draft),
    ]

    private static let orders = [
        // Riz, il y a 2 semaines : 10 parts au palier 1 (16 $), 20 parts au palier 2 (14 $).
        order("o1", offer: "rice-1", group: "g1", shares: 10, households: 6, tier: 0),
        order("o2", offer: "rice-1", group: "g2", shares: 20, households: 12, tier: 1),
        // Riz, la semaine dernière : 5 parts, sous le premier palier.
        order("o3", offer: "rice-2", group: "g1", shares: 5, households: 4, tier: nil),
        // Annulée : ignorée.
        order("o4", offer: "rice-2", group: "g3", shares: 50, households: 30, tier: 1, status: .cancelled),
        // Farine : 9 parts au palier 1 (16 $, plus cher que l'épicerie : économie nulle).
        order("o5", offer: "flour-1", group: "g3", shares: 9, households: 7, tier: 0),
        // Riz il y a 8 semaines : hors de « 4 sem. ».
        order("o6", offer: "rice-old", group: "g4", shares: 12, households: 8, tier: 0),
        // Brouillon : ignoré.
        order("o7", offer: "draft", group: "g1", shares: 40, households: 20, tier: 1),
    ]

    private func report(_ period: ProductStatsPeriod) -> ProductStatsReport {
        ProductSalesAggregator.report(
            products: Self.products, offers: Self.offers, orders: Self.orders, period: period, now: Self.now,
            calendar: Self.calendar
        )
    }

    @Test func aggregatesUnitsRevenueGroupsAndHouseholdsPerProduct() throws {
        let report = report(.fourWeeks)
        let rice = try #require(report.product(id: "rice"))
        #expect(rice.unitsSold == 35)
        #expect(rice.revenueCents == 10 * 1_600 + 20 * 1_400)
        #expect(rice.groupCount == 2)
        #expect(rice.householdCount == 22)
        #expect(rice.orderCount == 3)
        #expect(rice.shareUnit == "sac de 10 kg")
        #expect(rice.tierCount == 2)

        let flour = try #require(report.product(id: "flour"))
        #expect(flour.unitsSold == 9)
        #expect(flour.revenueCents == 9 * 1_600)
    }

    @Test func savingsUseTheGroceryReferenceAndNeverGoNegative() throws {
        let report = report(.fourWeeks)
        let rice = try #require(report.product(id: "rice"))
        // (20 − 16) × 10 + (20 − 14) × 20 ; la commande sous le premier palier n'économise rien.
        #expect(rice.savingsCents == 400 * 10 + 600 * 20)
        #expect(report.product(id: "flour")?.savingsCents == 0)
        #expect(report.totalSavingsCents == rice.savingsCents)
    }

    @Test func averageTierCountsOrdersBelowTheFirstTierAsZero() throws {
        let rice = try #require(report(.fourWeeks).product(id: "rice"))
        // Paliers 1, 2 et 0 → 1.
        #expect(rice.averageTier == 1)
        #expect(report(.fourWeeks).product(id: "flour")?.averageTier == 1)
    }

    @Test func periodFilterExcludesOlderOffers() throws {
        let short = report(.fourWeeks)
        let long = report(.twelveWeeks)
        #expect(short.product(id: "rice")?.unitsSold == 35)
        #expect(long.product(id: "rice")?.unitsSold == 47)
        #expect(short.weekly.count == 4)
        #expect(long.weekly.count == 12)
        #expect(report(.all).product(id: "rice")?.unitsSold == 47)
    }

    @Test func weeklyBucketsAddUpToTheTotals() {
        let report = report(.twelveWeeks)
        #expect(report.weekly.reduce(0) { $0 + $1.units } == report.totalUnits)
        #expect(report.weekly.reduce(0) { $0 + $1.revenueCents } == report.totalRevenueCents)
        for product in report.products {
            #expect(product.weekly.count == report.weekly.count)
        }
        // Semaines consécutives, triées, chacune un lundi.
        let starts = report.weekly.map(\.weekStart)
        #expect(starts == starts.sorted())
        #expect(starts.allSatisfy { Self.calendar.component(.weekday, from: $0) == 2 })
    }

    @Test func totalsAndDistinctGroupsSpanEveryProduct() {
        let report = report(.fourWeeks)
        #expect(report.totalUnits == 44)
        #expect(report.groupCount == 3)
        #expect(report.householdCount == 29)
        #expect(report.totalRevenueCents == report.products.reduce(0) { $0 + $1.revenueCents })
    }

    @Test func productsAreSortedByRevenueAndBestSellersByUnits() {
        let report = report(.fourWeeks)
        #expect(report.products.map(\.productId) == ["rice", "flour"])
        #expect(report.bestSellers.map(\.productId) == ["rice", "flour"])
    }

    @Test func openOffersClosingNextWeekStillCount() throws {
        let future = Self.offer("rice-next", product: "rice", weeksAgo: -1, status: .active)
        let report = ProductSalesAggregator.report(
            products: Self.products, offers: [future],
            orders: [Self.order("o", offer: "rice-next", group: "g1", shares: 8, households: 5, tier: 0, status: .open)],
            period: .fourWeeks, now: Self.now, calendar: Self.calendar
        )
        #expect(report.totalUnits == 8)
        #expect(report.weekly.count == 5)
        #expect(report.weekly.last?.units == 8)
    }

    @Test func missingProductFallsBackToTheShareUnit() throws {
        let report = ProductSalesAggregator.report(
            products: [], offers: [Self.offer("x", product: "gone", weeksAgo: 1)],
            orders: [Self.order("o", offer: "x", group: "g", shares: 3, households: 2, tier: nil)],
            period: .fourWeeks, now: Self.now, calendar: Self.calendar
        )
        let product = try #require(report.products.first)
        #expect(product.name == "sac de 10 kg")
        #expect(product.revenueCents == 0)
        #expect(product.averageTier == 0)
    }

    @Test func noOrdersGivesAnEmptyButValidReport() {
        let report = ProductSalesAggregator.report(
            products: Self.products, offers: [Self.offer("rice-1", product: "rice", weeksAgo: 1)], orders: [],
            period: .fourWeeks, now: Self.now, calendar: Self.calendar
        )
        #expect(report.hasNoSales)
        #expect(report.bestSellers.isEmpty)
        #expect(report.products.first?.averageTier == nil)
        #expect(report.weekly.count == 4)
    }

    @Test func trendComparesTheLastTwoWeeksWithSales() {
        func points(_ units: [Int]) -> [ProductWeekPoint] {
            units.enumerated().map { ProductWeekPoint(weekStart: Date(timeIntervalSince1970: Double($0) * 1_000), units: $1, revenueCents: 0) }
        }
        #expect(ProductSalesAggregator.trend(of: points([10, 0, 15])) == .up(percent: 50))
        #expect(ProductSalesAggregator.trend(of: points([20, 10])) == .down(percent: 50))
        #expect(ProductSalesAggregator.trend(of: points([20, 20])) == .flat)
        #expect(ProductSalesAggregator.trend(of: points([0, 7])) == .new)
    }

    @Test func movingAverageSmoothsOverThreeWeeks() {
        let weeks = [3, 6, 9, 0].enumerated().map {
            ProductWeekPoint(weekStart: Date(timeIntervalSince1970: Double($0) * 1_000), units: $1, revenueCents: 0)
        }
        #expect(ProductSalesAggregator.movingAverage(of: weeks) == [3, 4.5, 6, 5])
    }
}

/// Le ViewModel lit les dépôts et ré-agrège quand la période change.
@MainActor
struct ProductStatsViewModelTests {
    @Test func loadsTheDemoVendorAndSwitchesPeriodWithoutReloading() async throws {
        let model = ProductStatsViewModel(
            repositories: .fake(behavior: .instant, data: .productStatsDemo), vendorId: FakeData.ID.moulinsDuNord
        )
        await model.load()
        let twelve = try #require(model.state.value)
        #expect(twelve.products.count == 3)
        #expect(twelve.bestSellers.first?.productId == FakeData.ID.rice)

        model.period = .fourWeeks
        let four = try #require(model.state.value)
        #expect(four.period == .fourWeeks)
        #expect(four.totalUnits < twelve.totalUnits)
    }

    @Test func selectionTogglesAndFollowsTheChart() async throws {
        let model = ProductStatsViewModel(
            repositories: .fake(behavior: .instant, data: .productStatsDemo), vendorId: FakeData.ID.moulinsDuNord
        )
        await model.load()
        model.toggleSelection(FakeData.ID.rice)
        #expect(model.selectedProduct?.productId == FakeData.ID.rice)
        #expect(model.chartWeeks == model.selectedProduct?.weekly)
        model.toggleSelection(FakeData.ID.rice)
        #expect(model.selectedProductId == nil)
        #expect(model.chartWeeks == model.state.value?.weekly)
    }

    @Test func vendorWithoutOffersIsEmpty() async {
        let model = ProductStatsViewModel(repositories: .fake(behavior: .instant), vendorId: "vendor-inconnu")
        await model.load()
        guard case .empty = model.state else {
            Issue.record("attendu .empty, reçu \(model.state)")
            return
        }
    }

    @Test func offlineFails() async {
        let model = ProductStatsViewModel(repositories: .fake(behavior: .failing(.offline)), vendorId: FakeData.ID.moulinsDuNord)
        await model.load()
        #expect(model.state.error == .offline)
    }
}
