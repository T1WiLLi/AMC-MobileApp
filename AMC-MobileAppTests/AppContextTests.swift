import Testing
@testable import AMC_MobileApp

@MainActor
struct AppContextTests {
    @Test func launchContextNeverUsesDemoIdsWithFirebase() {
        // T-127 : avec Firebase, le contexte de base n'a aucun id ; il est résolu depuis la session.
        for mode in [BackendMode.emulator, .demoProject] {
            let context = AppContext.launch(mode: mode)
            #expect(!context.isResolved)
            #expect(context.householdId.isEmpty && context.vendorId.isEmpty && context.groupId == nil)
        }
        #expect(AppContext.launch(mode: .fake).isResolved)
    }

    @Test func demoContextUsesFakePersonas() {
        let context = AppContext.demo
        #expect(context.householdId == FakeData.ID.aminaHousehold)
        #expect(context.groupId == FakeData.ID.parcExtension)
        #expect(context.vendorId == FakeData.ID.fermeLafleur)
    }

    @Test func offerRouteIsHashableByOffer() {
        #expect(OfferRoute(offerId: "a") == OfferRoute(offerId: "a"))
        #expect(OfferRoute(offerId: "a") != OfferRoute(offerId: "b"))
    }
}

/// T-180 : parcours de démo du pitch (Amina, Parc-Extension, « Riz basmati — Ferme Lafleur »).
@MainActor
struct DemoPathDataTests {
    @Test func riceLotIsOneShareBelowATier() throws {
        let data = FakeData.montreal
        let offer = try #require(data.offers.first { $0.id == FakeData.ID.lafleurRiceOffer })
        let order = try #require(data.groupOrders.first { $0.id == FakeData.ID.lafleurRiceOrder })
        #expect(order.groupId == FakeData.ID.parcExtension)
        #expect(order.committedShares == 19)
        #expect(offer.tierIndex(forCommittedShares: 19) == 1)
        #expect(offer.tierIndex(forCommittedShares: 20) == 2)
        #expect(offer.tiers[2].priceCents < offer.tiers[1].priceCents)
    }

    @Test func fakeSignUpIsVerifiedInDemoMode() async throws {
        let demo = FakeAuthService(latency: .zero, autoVerifiesEmail: true)
        let user = try await demo.signUp(email: "a@b.co", password: "motdepasse1", displayName: "Amina")
        #expect(!user.needsEmailVerification)
        let strict = FakeAuthService(latency: .zero)
        let pending = try await strict.signUp(email: "a@b.co", password: "motdepasse1", displayName: "Amina")
        #expect(pending.needsEmailVerification)
    }

    @Test func demoUserIsAminaEverywhere() {
        #expect(AuthUser.sample.displayName.hasPrefix("Amina"))
        #expect(FakeData.montreal.users.first?.displayName.hasPrefix("Amina") == true)
    }
}
