import Foundation
import Testing
@testable import AMC_MobileApp

/// T-202 : cas limites trouvés en QA adverse du portail Organisme (double toucher, parrainage en double,
/// organisme absent, quartier trop long pour les règles, montants limites).
@MainActor
struct OrganizationQAEdgeCaseTests {
    private func makeModel(
        _ repository: FakeOrganizationRepository = FakeOrganizationRepository(),
        organizationId: String = FakeData.ID.laRuche
    ) -> OrganizationPortalModel {
        OrganizationPortalModel(repository: repository, organizationId: organizationId)
    }

    // MARK: Dons

    @Test func doubleTapCreatesOnlyOneDonation() async {
        let repository = FakeOrganizationRepository(behavior: FakeBehavior(latencyMilliseconds: 20...20, failure: nil))
        let model = makeModel(repository)
        await model.load()
        let before = model.snapshot?.donations.count ?? 0
        async let first = model.donate(.suspendedBaskets(count: 1), toGroup: FakeData.ID.parcEx)
        async let second = model.donate(.suspendedBaskets(count: 1), toGroup: FakeData.ID.parcEx)
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1)
        #expect(model.snapshot?.donations.count == before + 1)
        let stored = try? await repository.donations(ofOrganization: FakeData.ID.laRuche)
        #expect(stored?.count == before + 1)
        #expect(!model.isSubmitting)
    }

    @Test func donationLimitsMatchFirestoreRules() throws {
        let profile = try #require(FakeData.demoSolidarityProfiles.first)
        // Bornes de isValidDonation / isFundCredit : 1 à 500 000 cents.
        #expect(try OrganizationLedger.plan(.fund(amountCents: 500), for: profile).amountCents == 500)
        #expect(try OrganizationLedger.plan(.fund(amountCents: 500_000), for: profile).amountCents == 500_000)
        #expect(throws: AppError.self) { try OrganizationLedger.plan(.fund(amountCents: 500_001), for: profile) }
        // Paniers : jamais plus de 5 000 $ même si le stepper monte à 200.
        let maxBaskets = OrganizationLedger.maxDonationCents / profile.basketPriceCents
        #expect(try OrganizationLedger.plan(.suspendedBaskets(count: maxBaskets), for: profile).amountCents
            <= OrganizationLedger.maxDonationCents)
        if maxBaskets < OrganizationLedger.maxBasketsPerDonation {
            #expect(throws: AppError.self) {
                try OrganizationLedger.plan(.suspendedBaskets(count: maxBaskets + 1), for: profile)
            }
        }
    }

    @Test func donationEntryHasNoOrderIdAndZeroBaskets() throws {
        let profile = try #require(FakeData.demoSolidarityProfiles.first)
        let (donation, fund) = try OrganizationLedger.record(
            .suspendedBaskets(count: 3), to: profile, organizationId: "org", donationId: "don"
        )
        let entry = try #require(fund.entries.last)
        // isFundCredit : basketCount == 0 et clés exactes (orderId nil n'est pas encodé).
        #expect(entry.orderId == nil)
        #expect(entry.basketCount == 0)
        #expect(entry.amountCents == donation.amountCents)
        #expect(donation.householdsReached <= donation.basketCount)
        #expect(fund.balanceCents == profile.fund.balanceCents + donation.amountCents)
    }

    @Test func failedDonationLeavesSnapshotUntouched() async {
        let model = makeModel()
        await model.load()
        let before = model.snapshot
        let done = await model.donate(.fund(amountCents: OrganizationLedger.maxDonationCents + 1), toGroup: FakeData.ID.parcEx)
        #expect(!done)
        #expect(model.actionError != nil)
        #expect(model.snapshot == before)
        #expect(model.completedActions == 0)
    }

    // MARK: Parrainages

    @Test func sponsoringTwiceUpdatesGoalWithoutDuplicate() async {
        let model = makeModel()
        await model.load()
        #expect(await model.sponsor(groupId: FakeData.ID.villeray, monthlyBasketGoal: 5))
        #expect(await model.sponsor(groupId: FakeData.ID.villeray, monthlyBasketGoal: 40))
        let matches = model.snapshot?.sponsorships.filter { $0.groupId == FakeData.ID.villeray } ?? []
        #expect(matches.count == 1)
        #expect(matches.first?.monthlyBasketGoal == 40)
        let ids = model.profile(id: FakeData.ID.villeray)?.sponsorOrganizationIds ?? []
        #expect(ids.filter { $0 == FakeData.ID.laRuche }.count == 1)
    }

    @Test func invalidGoalIsRefused() async {
        let model = makeModel()
        await model.load()
        #expect(!(await model.sponsor(groupId: FakeData.ID.villeray, monthlyBasketGoal: 0)))
        #expect(model.actionError != nil)
        #expect(!model.sponsoredGroups.contains { $0.groupId == FakeData.ID.villeray })
    }

    @Test func longNeighborhoodIsTruncatedForTheRules() async throws {
        var profile = try #require(FakeData.demoSolidarityProfiles.first { $0.groupId == FakeData.ID.villeray })
        profile.neighborhood = String(repeating: "Quartier très long ", count: 5)
        #expect(profile.neighborhood.count > Sponsorship.maxNeighborhoodLength)
        let repository = FakeOrganizationRepository(profiles: [profile])
        let sponsorship = try await repository.sponsor(
            groupId: FakeData.ID.villeray, organizationId: FakeData.ID.laRuche, monthlyBasketGoal: 10
        )
        #expect(sponsorship.neighborhood.count == Sponsorship.maxNeighborhoodLength)
        #expect(Sponsorship.storedNeighborhood("Villeray") == "Villeray")
    }

    @Test func endingAnAbsentSponsorshipIsHarmless() async {
        let model = makeModel()
        await model.load()
        let before = model.snapshot?.sponsorships
        #expect(await model.endSponsorship(groupId: FakeData.ID.montrealNord))
        #expect(model.snapshot?.sponsorships == before)
    }

    // MARK: Recherche

    @Test func suggestionsFollowTheTypedQuery() async {
        let model = makeModel()
        await model.load()
        let all = model.neighborhoodSuggestions
        #expect(all.count == Set(FakeData.demoSolidarityProfiles.map(\.neighborhood)).count)
        model.searchText = "zzzz"
        #expect(model.neighborhoodSuggestions.isEmpty)
        #expect(model.searchResults.isEmpty)
        model.searchText = "viller"
        #expect(model.neighborhoodSuggestions == ["Villeray"])
        model.searchText = "villeray"
        // Le quartier est déjà choisi : plus de suggestion par-dessus les résultats.
        #expect(model.neighborhoodSuggestions.isEmpty)
        #expect(model.searchResults.allSatisfy { $0.neighborhood == "Villeray" })
    }

    // MARK: Compte et organisme

    @Test func missingOrganizationShowsAnError() async {
        let model = makeModel(organizationId: "org-inexistant")
        await model.load()
        guard case .failed(let error) = model.state else {
            Issue.record("Un organisme absent doit donner un état d'erreur, pas \(model.state)")
            return
        }
        #expect(error == .notFound)
        #expect(model.impact == .empty)
        #expect(model.prioritizedGroups.isEmpty)
    }

    @Test func failedRefreshKeepsLoadedPortal() async {
        let model = makeModel()
        await model.load()
        let loaded = model.snapshot
        #expect(loaded != nil)
        let offline = makeModel(FakeOrganizationRepository(behavior: .failing(.offline)))
        await offline.load()
        #expect(offline.snapshot == nil)
        // Rafraîchir un portail déjà chargé : l'écran reste.
        await model.load()
        #expect(model.snapshot == loaded)
    }
}
