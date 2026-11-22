import Foundation
import Testing
@testable import AMC_MobileApp

/// E21-3 : « Réserver = enregistrer sa carte » et « Tu paieras au plus X $ ».
@MainActor
struct CardRegistrationTests {
    private typealias ID = FakeData.ID

    private func makeModel(_ repos: AppRepositories = .fake(behavior: .instant)) -> OfferDetailViewModel {
        OfferDetailViewModel(repositories: repos, offerId: ID.potatoOffer,
                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
    }

    @Test func firstReservationShowsTheCardSheetWithoutReserving() async throws {
        let model = makeModel()
        await model.load()
        #expect(model.state.value?.myShareQuantity == 0)
        #expect(model.needsCardRegistration)
        model.toggleSuspended(500)
        let expectedMax = model.selectedMaxPriceCents
        await model.requestReserve()
        let sheet = try #require(model.cardRegistration)
        #expect(sheet.quantity == 1)
        #expect(sheet.maxPriceCents == expectedMax)
        #expect(sheet.donationCents == 500)
        #expect(sheet.methodLabel == PaymentSimulator.methodLabel)
        #expect(model.state.value?.myShareQuantity == 0)
    }

    @Test func cancellingTheSheetReservesNothing() async {
        let model = makeModel()
        await model.load()
        await model.requestReserve()
        model.dismissCardRegistration()
        #expect(model.cardRegistration == nil)
        #expect(model.state.value?.myShareQuantity == 0)
        #expect(model.needsCardRegistration)
    }

    @Test func confirmingReservesAndLaterChangesSkipTheSheet() async {
        let model = makeModel()
        await model.load()
        await model.requestReserve()
        await model.confirmCardRegistration()
        #expect(model.cardRegistration == nil)
        #expect(model.actionError == nil)
        #expect(model.state.value?.myShareQuantity == 1)
        #expect(!model.needsCardRegistration)

        // Changer la quantité : pas de nouvelle feuille, la part change tout de suite.
        model.selectedQuantity = 2
        await model.requestReserve()
        #expect(model.cardRegistration == nil)
        #expect(model.state.value?.myShareQuantity == 2)

        // Annuler puis réserver à nouveau pendant la même visite : la carte est déjà enregistrée.
        await model.cancelShare()
        model.selectedQuantity = 1
        await model.requestReserve()
        #expect(model.cardRegistration == nil)
        #expect(model.state.value?.myShareQuantity == 1)
    }

    @Test func existingShareMeansTheCardIsAlreadyRegistered() async {
        let repos = AppRepositories.fake(behavior: .instant)
        let first = makeModel(repos)
        await first.load()
        await first.reserve()
        let reopened = makeModel(repos)
        await reopened.load()
        #expect(reopened.state.value?.myShareQuantity == 1)
        #expect(!reopened.needsCardRegistration)
    }

    @Test func reservedMaxPriceIncludesTheBasketAndOnlyWhileOpen() async throws {
        let model = makeModel()
        await model.load()
        #expect(model.reservedMaxPriceCents == nil)
        model.toggleSuspended(1_000)
        await model.reserve()
        let content = try #require(model.state.value)
        let order = try #require(content.groupOrder)
        let expected = PaymentPot.maxPriceCents(quantity: 1, offer: content.offer, order: order) + 1_000
        #expect(model.reservedMaxPriceCents == expected)
    }

    @Test func maxPriceDropsLiveWhenAnotherFamilyUnlocksATier() async throws {
        let model = makeModel()
        await model.load()
        await model.reserve()
        let content = try #require(model.state.value)
        let order = try #require(content.groupOrder)
        let before = try #require(model.reservedMaxPriceCents)
        let nextTier = try #require(content.offer.sortedTiers.first { $0.minShares > order.committedShares })

        var bigger = order
        bigger.committedShares = nextTier.minShares
        let (stream, continuation) = AsyncThrowingStream<GroupOrder, any Error>.makeStream()
        continuation.yield(order)
        continuation.yield(bigger)
        continuation.finish()
        await model.follow(stream)

        let after = try #require(model.reservedMaxPriceCents)
        #expect(after < before)
        #expect(after == nextTier.priceCents)
    }

    @Test func maxPriceHelperFollowsTheTiers() throws {
        let data = FakeData.montreal
        let offer = try #require(data.offers.first { $0.id == ID.potatoOffer })
        var order = GroupOrder(id: "o", groupId: "g", offerId: offer.id, status: .open, currentTierIndex: nil,
                               committedShares: 0, committedHouseholds: 0, pickupPointId: nil, pickupSlots: [])
        let tiers = offer.sortedTiers
        var previous = PaymentPot.maxPriceCents(quantity: 2, offer: offer, order: order)
        #expect(previous == 2 * tiers[0].priceCents)
        for tier in tiers.dropFirst() {
            order.committedShares = tier.minShares
            let price = PaymentPot.maxPriceCents(quantity: 2, offer: offer, order: order)
            #expect(price <= previous)
            #expect(price == 2 * tier.priceCents)
            previous = price
        }
        #expect(PaymentPot.maxPriceCents(quantity: 0, offer: offer, order: order) == 0)
    }
}
