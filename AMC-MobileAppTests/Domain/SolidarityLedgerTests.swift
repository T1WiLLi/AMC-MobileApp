import Foundation
import Testing
@testable import AMC_MobileApp

/// Tests de la solidarité (E10 : RQ-078 à RQ-080, RQ-082, RQ-083).
struct SolidarityLedgerTests {
    private let offer = TierEngineTests.offer
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func share(_ household: String, _ quantity: Int, suspended: Cents = 0) -> Share {
        TierEngineTests.share(household, quantity, suspended: suspended)
    }

    // MARK: RQ-078 panier suspendu

    @Test func suspendedBasketAddsUpOnMyShare() throws {
        let order = TierEngineTests.order(committed: 12)
        let once = try SolidarityLedger.addingSuspendedBasket(500, to: share("h1", 2), in: order)
        let twice = try SolidarityLedger.addingSuspendedBasket(250, to: once, in: order)
        #expect(once.suspendedAmountCents == 500)
        #expect(twice.suspendedAmountCents == 750)
        #expect(twice.quantity == 2)
        #expect(try SolidarityLedger.removingSuspendedBasket(from: twice, in: order).suspendedAmountCents == 0)
    }

    @Test func suspendedBasketRejectsBadAmountsAndClosedOrders() {
        let open = TierEngineTests.order()
        for amount in [0, -100] {
            #expect(throws: AppError.invalidInput("Choisis un montant plus grand que 0 $.")) {
                try SolidarityLedger.addingSuspendedBasket(amount, to: share("h1", 1), in: open)
            }
        }
        #expect(throws: AppError.self) {
            try SolidarityLedger.addingSuspendedBasket(1, to: share("h1", 1, suspended: 20_000), in: open)
        }
        #expect((try? SolidarityLedger.addingSuspendedBasket(20_000, to: share("h1", 1), in: open)) != nil)
        #expect(throws: AppError.orderClosed) {
            try SolidarityLedger.addingSuspendedBasket(500, to: share("h1", 1), in: TierEngineTests.order(status: .closed))
        }
    }

    // MARK: RQ-079 fonds

    @Test func fundBalanceBasketsAndHistory() throws {
        var fund = try SolidarityLedger.donating(2_500, to: SolidarityFund(), date: date)
        fund.entries.append(.init(kind: .application, orderId: "go0", amountCents: 990, basketCount: 1,
                                  date: date.addingTimeInterval(60)))
        #expect(fund.balanceCents == 1_510)
        #expect(fund.totalContributedCents == 2_500)
        #expect(fund.basketsOffered == 1)
        #expect(fund.basketsFundable(unitPriceCents: 500) == 3)
        #expect(fund.basketsFundable(unitPriceCents: 0) == 0)
        #expect(fund.history.map(\.kind) == [.application, .contribution])
        #expect(throws: AppError.self) { try SolidarityLedger.donating(0, to: fund) }
    }

    // MARK: RQ-080 application anonyme

    @Test func applyFeedsFundThenPaysSubsidizedShares() throws {
        let start = try SolidarityLedger.donating(1_000, to: SolidarityFund(), date: date)
        let application = try SolidarityLedger.apply(
            orderId: "go1", offer: offer,
            shares: [share("h1", 2, suspended: 1_500), share("h2", 1), share("h3", 2)],
            unitPriceCents: 990, eligibleHouseholdIds: ["h2", "h3"], fund: start, date: date
        )
        // Fonds : 1 000 + 1 500 = 2 500, parts admissibles : 990 + 1 980 = 2 970 → tout part au prorata.
        #expect(application.summary == .init(contributedCents: 1_500, fundUsedCents: 2_500,
                                             fundRemainingCents: 0, basketsFunded: 2))
        #expect(application.fund.balanceCents == application.allocation.fundRemainingCents)
        #expect(application.fund.basketsOffered == 2)
        #expect(application.allocation.shares.map(\.subsidyCents).reduce(0, +) == 2_500)
        #expect(application.allocation.shares.first { $0.householdId == "h1" }?.subsidyCents == 0)
    }

    @Test func applyMatchesShareAllocatorAndKeepsLeftovers() throws {
        let shares = [share("h1", 1, suspended: 3_000), share("h2", 1)]
        let application = try SolidarityLedger.apply(
            orderId: "go1", offer: offer, shares: shares, unitPriceCents: 990,
            eligibleHouseholdIds: ["h2"], fund: SolidarityFund(), date: date
        )
        let direct = try ShareAllocator.allocate(
            orderId: "go1", offer: offer, shares: shares, unitPriceCents: 990,
            eligibleHouseholdIds: ["h2"], solidarityFundCents: 0
        )
        #expect(application.allocation == direct)
        #expect(application.fund.balanceCents == 2_010)
        #expect(application.summary.basketsFunded == 1)
    }

    @Test func groupVisibleOutputNeverNamesAHousehold() throws {
        let application = try SolidarityLedger.apply(
            orderId: "go1", offer: offer,
            shares: [share("menage-secret", 1), share("h1", 1, suspended: 2_000)],
            unitPriceCents: 990, eligibleHouseholdIds: ["menage-secret"], fund: SolidarityFund(), date: date
        )
        let visible = String(describing: application.summary) + String(describing: application.fund)
        #expect(!visible.contains("menage-secret"))
        #expect(!visible.contains("h1"))
    }

    @Test func applyWithoutFundOrEligibleHouseholdsLeavesNoApplicationEntry() throws {
        let application = try SolidarityLedger.apply(
            orderId: "go1", offer: offer, shares: [share("h1", 1, suspended: 500)],
            unitPriceCents: 990, eligibleHouseholdIds: [], fund: SolidarityFund(), date: date
        )
        #expect(application.fund.entries.map(\.kind) == [.contribution])
        #expect(application.summary.basketsFunded == 0)
        #expect(application.fund.balanceCents == 500)
    }

    // MARK: RQ-082 codes d'organisme

    @Test func referralCodeRoundTripsForEverySerial() throws {
        for serial in 0...ReferralCode.maxSerial {
            let code = try ReferralCode(organisation: "cb", serial: serial)
            #expect(try ReferralCode(validating: code.description) == code)
        }
        #expect(try ReferralCode(organisation: "CB", serial: 42).description == "ORG-CB-00420")
        #expect(try ReferralCode(validating: " org-cb-00420 ").serial == 42)
    }

    @Test func referralCodeCatchesTyposAndBadFormats() {
        #expect(!ReferralCode.isValid("ORG-CB-00520")) // faute de frappe sur un chiffre
        #expect(!ReferralCode.isValid("ORG-CB-00240")) // deux chiffres inversés
        #expect(!ReferralCode.isValid("ORG-BC-00420")) // deux lettres inversées
        for bad in ["", "ORG-CB-0042", "ABC-CB-00420", "ORG-C1-00420", "ORG-CB-+0420", "ORG-CB-00420-1"] {
            #expect(!ReferralCode.isValid(bad))
        }
        #expect(throws: AppError.self) { try ReferralCode(organisation: "CBA", serial: 1) }
        #expect(throws: AppError.self) { try ReferralCode(organisation: "CB", serial: 10_000) }
    }

    @Test func referralCodeGivesSubsidizedStatusPrivately() throws {
        let profile = try ReferralCode.subsidizedProfile(redeeming: "org-cb-00420", issuedCodes: ["ORG-CB-00420"])
        #expect(profile == HouseholdPrivate(isSubsidized: true, referralCode: "ORG-CB-00420"))
        #expect(throws: AppError.self) {
            try ReferralCode.subsidizedProfile(redeeming: "ORG-CB-00420", issuedCodes: ["ORG-CB-00011"])
        }
        let eligible = ReferralCode.eligibleHouseholdIds([
            "h1": profile,
            "h2": HouseholdPrivate(isSubsidized: false, referralCode: nil),
            "h3": HouseholdPrivate(isSubsidized: true, referralCode: "ORG-CB-00520"),
        ])
        #expect(eligible == ["h1"])
    }

    // MARK: RQ-083 compteur public

    @Test func publicCounterUsesFrenchPlural() {
        #expect(SolidarityLedger.publicCounterText(basketsOffered: 0) == "0 panier suspendu offert dans ton quartier")
        #expect(SolidarityLedger.publicCounterText(basketsOffered: 1) == "1 panier suspendu offert dans ton quartier")
        #expect(SolidarityLedger.publicCounterText(basketsOffered: 12) == "12 paniers suspendus offerts dans ton quartier")
    }

    @MainActor @Test func fundSummaryFormatsMoney() throws {
        let fund = try SolidarityLedger.donating(4_250, to: SolidarityFund(), date: date)
        let text = SolidarityLedger.fundSummary(fund, unitPriceCents: 990)
        #expect(text.hasPrefix(Money.format(4_250)))
        #expect(text.hasSuffix("de quoi offrir 4 paniers"))
        #expect(SolidarityLedger.fundSummary(fund, unitPriceCents: 5_000) == "\(Money.format(4_250)) dans le fonds")
        #expect(SolidarityLedger.fundSummary(fund, unitPriceCents: 4_000).hasSuffix("offrir 1 panier"))
    }
}
