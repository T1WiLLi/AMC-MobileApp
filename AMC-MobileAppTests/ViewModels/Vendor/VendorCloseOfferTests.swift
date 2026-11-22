import Foundation
import Testing
@testable import AMC_MobileApp

/// T-196 : le vendeur ferme sa commande depuis l'onglet Lots.
@MainActor
struct VendorCloseOfferTests {
    private typealias ID = FakeData.ID

    private func vendorUser(id: String = "u-vendeur", vendorId: String? = ID.fermeRive) -> AppUser {
        AppUser(id: id, displayName: "Vendeur", photoURL: nil, language: .french, roles: [.vendor],
                neighborhood: "Saint-Michel", dietaryPreferences: [], seniorMode: false,
                householdId: nil, vendorId: vendorId)
    }

    private func model(user: AppUser, userId: String? = nil) -> VendorDashboardViewModel {
        var data = FakeData.montreal
        data.users.append(user)
        return VendorDashboardViewModel(
            repositories: .fake(behavior: .instant, data: data), vendorId: ID.fermeRive, userId: userId ?? user.id
        )
    }

    @Test func closeButtonShowsForTheOwnerOfAnOpenOrder() async throws {
        let model = model(user: vendorUser())
        await model.load()
        let potato = try #require(model.state.value?.offers.first { $0.id == ID.potatoOffer })
        #expect(!potato.liveOrders.isEmpty)
        #expect(model.canClose(potato))
        // Aucune commande ouverte : rien à fermer.
        let apple = try #require(model.state.value?.offers.first { $0.id == ID.appleOffer })
        #expect(!model.canClose(apple))
    }

    @Test func closeButtonIsHiddenForAnotherVendorOrAFamily() async throws {
        let other = model(user: vendorUser(vendorId: ID.fermeLafleur))
        await other.load()
        let potato = try #require(other.state.value?.offers.first { $0.id == ID.potatoOffer })
        #expect(!other.canClose(potato))

        let family = model(user: vendorUser(vendorId: nil))
        await family.load()
        #expect(!family.canClose(potato))

        // Profil introuvable : le bouton reste caché, sans erreur.
        let unknown = model(user: vendorUser(), userId: "inconnu")
        await unknown.load()
        #expect(!unknown.canClose(potato))
        #expect(unknown.closeError == nil)
    }

    @Test func closingClosesTheOrdersThenRefreshesToTheClosedPhase() async throws {
        let model = model(user: vendorUser())
        await model.load()
        let before = try #require(model.state.value?.offers.first { $0.id == ID.potatoOffer })
        #expect(before.phase == .open)

        await model.closeOffer(offerId: ID.potatoOffer)

        let after = try #require(model.state.value?.offers.first { $0.id == ID.potatoOffer })
        #expect(after.linkedOrders.map(\.order.status) == [.closed])
        #expect(after.liveOrders.isEmpty)
        #expect(after.phase == .closed)
        #expect(!model.canClose(after))
        #expect(model.closeError == nil)
        #expect(model.closeSuccessCount == 1)
        #expect(model.closingOfferId == nil)
    }

    @Test func closingIsIgnoredWhenTheVendorMayNotClose() async throws {
        let model = model(user: vendorUser(vendorId: ID.fermeLafleur))
        await model.load()
        await model.closeOffer(offerId: ID.potatoOffer)
        let potato = try #require(model.state.value?.offers.first { $0.id == ID.potatoOffer })
        #expect(potato.phase == .open)
        #expect(model.closeSuccessCount == 0)
    }

    @Test func confirmationSaysPriceFamiliesAndPot() throws {
        let offer = try #require(FakeData.montreal.offers.first { $0.id == ID.potatoOffer })
        let order = GroupOrder(id: "o", groupId: "g", offerId: offer.id, status: .reached, currentTierIndex: 0,
                               committedShares: 19, committedHouseholds: 11, pickupPointId: nil, pickupSlots: [])
        let impact = VendorDashboardViewModel.ClosureImpact(offer: offer, liveOrders: [order])
        #expect(impact.confirmedOrders == 1)
        #expect(impact.payingHouseholds == 11)
        #expect(impact.lowestPriceCents == 1_150)
        let text = impact.message(shareUnit: offer.displayShareUnit)
        #expect(text.contains(Money.format(1_150)))
        #expect(text.contains("11 familles"))
        #expect(text.contains("pot du groupe"))
    }

    @Test func belowMinimumCancelsWithoutCharging() throws {
        let offer = try #require(FakeData.montreal.offers.first { $0.id == ID.potatoOffer })
        let order = GroupOrder(id: "o", groupId: "g", offerId: offer.id, status: .open, currentTierIndex: nil,
                               committedShares: 3, committedHouseholds: 3, pickupPointId: nil, pickupSlots: [])
        let impact = VendorDashboardViewModel.ClosureImpact(offer: offer, liveOrders: [order])
        #expect(impact.confirmedOrders == 0)
        #expect(impact.cancelledOrders == 1)
        #expect(impact.message(shareUnit: offer.displayShareUnit).contains("aucune famille ne sera débitée"))
    }
}
