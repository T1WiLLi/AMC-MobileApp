import Foundation
import Testing
@testable import AMC_MobileApp

/// T-195 : à la clôture, subventions du fonds de solidarité, paiements enregistrés, versement du vendeur.
/// Commande « go1 » (groupe « g1 », vendeur « v1 ») : h1 6 parts, h2 8 parts, h3 8 parts à 9,90 $ la part.
struct ClosureSettlementTests {
    static let deadline = TierEngineTests.deadline
    static let now = deadline.addingTimeInterval(-3_600)

    /// Prix des parts : h1 59,40 $, h2 et h3 79,20 $.
    static let h1Price: Cents = 6 * 990
    static let h2Price: Cents = 8 * 990

    static func fund(_ cents: Cents) -> SolidarityFund {
        SolidarityFund(entries: cents > 0 ? [
            .init(kind: .contribution, orderId: nil, amountCents: cents, basketCount: 0, date: now)
        ] : [])
    }

    static func repository(
        fund: SolidarityFund? = nil,
        shares: [Share]? = nil,
        verified: Bool = false,
        eligible: Set<String> = ["h1"],
        outcome: PaymentSimulator.Outcome = .success
    ) -> FakeGroupOrderRepository {
        var shares = shares ?? [TierEngineTests.share("h1", 6), TierEngineTests.share("h2", 8), TierEngineTests.share("h3", 8)]
        for index in shares.indices where eligible.contains(shares[index].householdId) {
            shares[index].solidarityEligible = true
        }
        let committed = shares.reduce(0) { $0 + $1.quantity }
        var order = TierEngineTests.order(committed: committed, status: committed >= TierEngineTests.offer.minimumSharesToLaunch ? .reached : .open)
        order.committedHouseholds = shares.count
        return FakeGroupOrderRepository(
            groupOrders: [order], shares: [order.id: shares], offers: [TierEngineTests.offer], now: { now },
            payments: PaymentSimulator(outcome: outcome, now: { now }),
            solidarityFunds: fund.map { ["g1": $0] } ?? [:],
            verifiedVendorIds: verified ? [TierEngineTests.offer.vendorId] : []
        )
    }

    static let trigger = GroupOrderClosureTrigger.manual(
        user: ClosurePolicyTests.user(household: "h9"), groupCoordinatorIds: ["u1"]
    )

    // MARK: Subventions

    @Test func fundCoversTheSubsidizedShareAndIsDebitedByTheExactAmount() async throws {
        let repository = Self.repository(fund: Self.fund(10_000))
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.first { $0.householdId == "h1" }?.subsidyCents == Self.h1Price)
        #expect(shares.filter { $0.householdId != "h1" }.allSatisfy { $0.subsidyCents == 0 })
        #expect(closure.fundDebitCents == Self.h1Price)
        #expect(closure.fundEntry?.kind == .application)
        #expect(closure.fundEntry?.amountCents == Self.h1Price)
        #expect(closure.fundEntry?.orderId == "go1")
        let fundAfter = try #require(await repository.solidarityFund(ofGroup: "g1"))
        #expect(fundAfter.balanceCents == 10_000 - Self.h1Price)
        #expect(closure.vendorPayout?.subsidyTotalCents == Self.h1Price)
    }

    @Test func insufficientFundGivesAPartialSubsidyAndNeverGoesNegative() async throws {
        let repository = Self.repository(fund: Self.fund(3_000))
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.first { $0.householdId == "h1" }?.subsidyCents == 3_000)
        #expect(closure.fundDebitCents == 3_000)
        let fundAfter = try #require(await repository.solidarityFund(ofGroup: "g1"))
        #expect(fundAfter.balanceCents == 0)
        // La famille paie le reste : 59,40 $ - 30 $.
        let payment = try #require(await repository.payments(ofGroupOrder: "go1").first { $0.householdId == "h1" })
        #expect(payment.amountDueCents == Self.h1Price - 3_000)
    }

    @Test func emptyFundGivesNoSubsidyAndWritesNothingToTheFund() async throws {
        let repository = Self.repository(fund: Self.fund(0))
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.allSatisfy { $0.subsidyCents == 0 })
        #expect(closure.fundDebitCents == 0)
        #expect(closure.fundEntry == nil)
        let fundAfter = try #require(await repository.solidarityFund(ofGroup: "g1"))
        #expect(fundAfter.entries.isEmpty)
        #expect(fundAfter.balanceCents == 0)
    }

    @Test func groupWithoutFundDocumentGivesNoSubsidy() async throws {
        let repository = Self.repository(fund: nil)
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)
        #expect(closure.fundDebitCents == 0)
        #expect(try await repository.shares(ofGroupOrder: "go1").allSatisfy { $0.subsidyCents == 0 })
    }

    @Test func suspendedBasketsPaySubsidiesBeforeTheFundIsTouched() async throws {
        // h2 offre 20 $ : le fonds ne paie que 59,40 $ - 20 $.
        let shares = [TierEngineTests.share("h1", 6), TierEngineTests.share("h2", 8, suspended: 2_000), TierEngineTests.share("h3", 8)]
        let repository = Self.repository(fund: Self.fund(10_000), shares: shares)
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        #expect(closure.fundUsedCents == Self.h1Price)
        #expect(closure.contributedCents == 2_000)
        #expect(closure.fundDebitCents == Self.h1Price - 2_000)
        let fundAfter = try #require(await repository.solidarityFund(ofGroup: "g1"))
        #expect(fundAfter.balanceCents == 10_000 - (Self.h1Price - 2_000))
    }

    @Test func onlyHouseholdsWhoDeclaredThemselvesEligibleAreSubsidized() async throws {
        let repository = Self.repository(fund: Self.fund(100_000), eligible: [])
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)
        #expect(closure.fundDebitCents == 0)
        #expect(try await repository.shares(ofGroupOrder: "go1").allSatisfy { $0.subsidyCents == 0 })
    }

    @Test func reservingFlagsASubsidizedHouseholdShare() async throws {
        let order = TierEngineTests.order(committed: 0, status: .open)
        let repository = FakeGroupOrderRepository(
            groupOrders: [order], shares: [order.id: []], offers: [TierEngineTests.offer], now: { Self.now },
            subsidizedHouseholdIds: ["h1"]
        )
        try await repository.setShare(quantity: 2, householdId: "h1", groupOrderId: "go1")
        try await repository.setShare(quantity: 3, householdId: "h2", groupOrderId: "go1")
        let shares = try await repository.shares(ofGroupOrder: "go1")
        #expect(shares.first { $0.householdId == "h1" }?.solidarityEligible == true)
        #expect(shares.first { $0.householdId == "h2" }?.solidarityEligible != true)
    }

    // MARK: Paiements enregistrés

    @Test func everyPaidShareGetsARecordedPayment() async throws {
        let repository = Self.repository(fund: Self.fund(10_000))
        try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let payments = try await repository.payments(ofGroupOrder: "go1")
        #expect(payments.map(\.householdId) == ["h1", "h2", "h3"])
        #expect(payments.allSatisfy { $0.status == .succeeded && $0.groupOrderId == "go1" })
        #expect(payments.first { $0.householdId == "h1" }?.subsidyCents == Self.h1Price)
        #expect(payments.first { $0.householdId == "h1" }?.amountDueCents == 0)
        #expect(payments.first { $0.householdId == "h2" }?.amountDueCents == Self.h2Price)
    }

    @Test func declinedPaymentsAreNotRecorded() async throws {
        let repository = Self.repository(outcome: .declined)
        try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)
        #expect(try await repository.payments(ofGroupOrder: "go1").isEmpty)
        #expect(try await repository.vendorPayout(ofGroupOrder: "go1")?.grossCents == 0)
    }

    @Test func cancelledOrderRecordsNoPaymentAndNoPayout() async throws {
        let repository = Self.repository(shares: [TierEngineTests.share("h1", 3), TierEngineTests.share("h2", 2)])
        let closure = try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)
        #expect(closure.order.status == .cancelled)
        #expect(closure.vendorPayout == nil)
        #expect(try await repository.payments(ofGroupOrder: "go1").isEmpty)
        #expect(try await repository.vendorPayout(ofGroupOrder: "go1") == nil)
    }

    // MARK: Versement du vendeur

    @Test func vendorPayoutHoldsEverythingUntilPickupForAnUnverifiedVendor() async throws {
        let repository = Self.repository(verified: false)
        try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let payout = try #require(await repository.vendorPayout(ofGroupOrder: "go1"))
        // 22 parts × 9,90 $ ; 1 % arrondi part par part : 0,59 $ + 2 × 0,79 $.
        #expect(payout.grossCents == 21_780)
        #expect(payout.commissionCents == 59 + 79 + 79)
        #expect(payout.netCents == 21_780 - 217)
        #expect(payout.releasedCents == 0)
        #expect(payout.heldCents == payout.netCents)
        #expect(!payout.isDeposit)
        #expect(payout.paidShareCount == 3)
        #expect(payout.vendorId == "v1")
    }

    @Test func verifiedVendorGetsAHalfDepositAtClosure() async throws {
        let repository = Self.repository(verified: true)
        try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let payout = try #require(await repository.vendorPayout(ofGroupOrder: "go1"))
        #expect(payout.isDeposit)
        // Acompte arrondi au cent inférieur, part par part : 29,40 $ + 2 × 39,20 $.
        #expect(payout.releasedCents == 2_940 + 3_920 + 3_920)
        #expect(payout.heldCents == payout.netCents - payout.releasedCents)
    }

    // MARK: Revenus du vendeur

    @Test func settlementShowsCollectedCommissionNetDepositAndBalance() async throws {
        let repository = Self.repository(fund: Self.fund(10_000), verified: true)
        try await repository.closeGroupOrder(id: "go1", trigger: Self.trigger)

        let order = try await repository.groupOrder(id: "go1")
        let shares = try await repository.shares(ofGroupOrder: "go1")
        let report = VendorRevenue.report(
            vendorId: "v1", offers: [TierEngineTests.offer], orders: [order],
            sharesByOrder: ["go1": shares], payments: try await repository.payments(ofGroupOrder: "go1")
        )
        let payout = try #require(await repository.vendorPayout(ofGroupOrder: "go1"))
        let settlement = VendorSettlement(report: report, payouts: [payout])

        #expect(settlement.closedOrderCount == 1)
        #expect(settlement.grossCents == 21_780)
        #expect(settlement.solidarityCents == Self.h1Price)
        // Les familles paient le prix moins la subvention ; le reste vient du fonds.
        #expect(settlement.collectedFromFamiliesCents == 21_780 - Self.h1Price)
        #expect(settlement.commissionCents == 217)
        #expect(settlement.netCents == 21_563)
        #expect(settlement.releasedCents == 10_780)
        #expect(settlement.heldCents == 21_563 - 10_780)
        #expect(settlement.outstandingCents == 0)
        #expect(!settlement.isEmpty)
    }

    @Test func settlementWithoutAnyPayoutIsEmpty() {
        let report = VendorRevenue.report(vendorId: "v1", offers: [], orders: [], sharesByOrder: [:], payments: [])
        #expect(VendorSettlement(report: report, payouts: []).isEmpty)
    }

    @Test func settlementSumsSeveralOrders() {
        let one = Self.record(order: "a", gross: 10_000, subsidy: 0)
        let two = Self.record(order: "b", gross: 5_000, subsidy: 1_000)
        let report = VendorRevenue.report(vendorId: "v1", offers: [], orders: [], sharesByOrder: [:], payments: [])
        let settlement = VendorSettlement(report: report, payouts: [one, two])
        #expect(settlement.closedOrderCount == 2)
        #expect(settlement.grossCents == 15_000)
        #expect(settlement.solidarityCents == 1_000)
        // Commission de 1 % (#329) : 100 + 50 cents.
        #expect(settlement.commissionCents == 150)
        #expect(settlement.netCents == 14_850)
    }

    static func record(order: String, gross: Cents, subsidy: Cents) -> VendorPayoutRecord {
        let share = Share(
            householdId: "h", quantity: 1, finalPriceCents: gross, isPaid: true,
            suspendedAmountCents: 0, subsidyCents: subsidy, qrCode: nil, isPickedUp: false
        )
        let closed = TierEngineTests.order(committed: 10, status: .closed)
        let payout = VendorPayout(order: closed, shares: [share], vendorIsVerified: false)
        return VendorPayoutRecord(
            orderId: order, vendorId: "v1", payout: payout, subsidyTotalCents: subsidy,
            solidarityContributedCents: 0, paidShareCount: 1, date: now
        )
    }
}
