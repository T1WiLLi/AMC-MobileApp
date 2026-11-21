import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct OrganizationLedgerTests {
    private func profile(subsidized: Int, balance: Cents, price: Cents = 2_500) -> GroupSolidarityProfile {
        GroupSolidarityProfile(
            groupId: "g", groupName: "G", neighborhood: "N", centerGeohash: "f25dv", householdCount: 10,
            subsidizedHouseholds: subsidized, basketPriceCents: price,
            fund: SolidarityFund(entries: balance > 0
                ? [.init(kind: .contribution, orderId: nil, amountCents: balance, basketCount: 0, date: .now)] : []),
            sponsorOrganizationIds: []
        )
    }

    @Test func basketsPlanUsesBasketPrice() throws {
        let plan = try OrganizationLedger.plan(.suspendedBaskets(count: 4), for: profile(subsidized: 3, balance: 0))
        #expect(plan.amountCents == 10_000)
        #expect(plan.basketCount == 4)
        #expect(plan.householdsReached == 3)
    }

    @Test func fundPlanCountsWholeBaskets() throws {
        let plan = try OrganizationLedger.plan(.fund(amountCents: 6_000), for: profile(subsidized: 5, balance: 0))
        #expect(plan.basketCount == 2)
        #expect(plan.householdsReached == 2)
    }

    @Test func invalidAmountsThrow() {
        let target = profile(subsidized: 1, balance: 0)
        #expect(throws: AppError.self) { try OrganizationLedger.plan(.fund(amountCents: 0), for: target) }
        #expect(throws: AppError.self) { try OrganizationLedger.plan(.suspendedBaskets(count: -1), for: target) }
        #expect(throws: AppError.self) {
            try OrganizationLedger.plan(.fund(amountCents: OrganizationLedger.maxDonationCents + 1), for: target)
        }
    }

    @Test func needLevels() {
        #expect(profile(subsidized: 0, balance: 0).needLevel == .covered)
        #expect(profile(subsidized: 4, balance: 2_500).needLevel == .urgent)
        #expect(profile(subsidized: 4, balance: 5_000).needLevel == .moderate)
        #expect(profile(subsidized: 4, balance: 10_000).needLevel == .covered)
    }

    @Test func summaryTotals() {
        let summary = OrganizationLedger.summarize(
            donations: FakeData.demoOrganizationDonations, sponsorships: FakeData.demoSponsorships
        )
        #expect(summary.basketsFunded == FakeData.demoOrganizationDonations.reduce(0) { $0 + $1.basketCount })
        #expect(summary.groupsSponsored == 2)
        #expect(summary.months.count == 6)
        #expect(summary.groceryValueCents > summary.totalGivenCents)
    }
}

@MainActor
struct OrganizationPortalModelTests {
    private func makeModel() -> OrganizationPortalModel {
        OrganizationPortalModel(repository: FakeOrganizationRepository(), organizationId: FakeData.ID.laRuche)
    }

    @Test func loadsSnapshot() async {
        let model = makeModel()
        await model.load()
        #expect(model.snapshot?.profiles.count == FakeData.demoSolidarityProfiles.count)
        #expect(model.prioritizedGroups.first?.needLevel == .urgent)
    }

    @Test func donateAddsToFundAndImpact() async throws {
        let model = makeModel()
        await model.load()
        let before = try #require(model.profile(id: FakeData.ID.montrealNord)).fund.balanceCents
        let baskets = model.impact.basketsFunded
        let done = await model.donate(.suspendedBaskets(count: 3), toGroup: FakeData.ID.montrealNord)
        #expect(done)
        #expect(model.profile(id: FakeData.ID.montrealNord)?.fund.balanceCents == before + 3 * 2_300)
        #expect(model.impact.basketsFunded == baskets + 3)
        #expect(model.lastDonation?.isSimulated == true)
    }

    @Test func sponsorAndEnd() async {
        let model = makeModel()
        await model.load()
        let sponsored = await model.sponsor(groupId: FakeData.ID.villeray, monthlyBasketGoal: 8)
        #expect(sponsored)
        #expect(model.sponsoredGroups.contains { $0.groupId == FakeData.ID.villeray })
        let ended = await model.endSponsorship(groupId: FakeData.ID.villeray)
        #expect(ended)
        #expect(!model.sponsoredGroups.contains { $0.groupId == FakeData.ID.villeray })
    }

    @Test func invalidDonationSetsError() async {
        let model = makeModel()
        await model.load()
        let done = await model.donate(.fund(amountCents: 0), toGroup: FakeData.ID.parcEx)
        #expect(!done)
        #expect(model.actionError != nil)
    }
}

@MainActor
struct PortalChoiceMigrationTests {
    @Test func legacyBothMigrates() {
        #expect(PortalChoice(rawValue: "both") == .both)
        #expect(PortalChoice(rawValue: "family,organization")?.portals == [.family, .organization])
        #expect(PortalChoice(rawValue: "nope") == nil)
        #expect(PortalChoice(selection: Set(Portal.allCases))?.initialPortal == .family)
        #expect(PortalChoice.organization.initialPortal == .organization)
    }
}
