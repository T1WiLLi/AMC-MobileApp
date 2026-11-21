import Foundation
import Testing
@testable import AMC_MobileApp

/// ViewModels du parcours Familles (T-019), sur `FakeData.montreal`.
/// Pommes de terre à Saint-Michel : 19 parts, paliers 10 → 11,50 $, 20 → 9,90 $, 30 → 8,50 $ ; épicerie 15,99 $.
@MainActor
struct FamilyViewModelTests {
    private typealias ID = FakeData.ID

    private func repositories(_ behavior: FakeBehavior = .instant) -> AppRepositories {
        .fake(behavior: behavior)
    }

    // MARK: OfferPricing

    @Test func pricingFollowsTheTiers() {
        let tiers = [PriceTier(minShares: 20, priceCents: 990), PriceTier(minShares: 10, priceCents: 1_150),
                     PriceTier(minShares: 30, priceCents: 850)]
        let pricing = OfferPricing(tiers: tiers, committedShares: 19, groceryPriceCents: 1_599)
        #expect(pricing.tierNumber == 1)
        #expect(pricing.currentPriceCents == 1_150)
        #expect(pricing.sharesToNextTier == 1)
        #expect(pricing.nextTierDiscountPercent == 14)
        #expect(pricing.savingsPercent == 28)
        #expect(pricing.savingsCents(forShares: 2) == 898)

        let below = pricing.with(committedShares: 3)
        #expect(below.tierNumber == 0)
        #expect(below.currentPriceCents == 1_150)

        let top = pricing.with(committedShares: 35)
        #expect(top.tierNumber == 3)
        #expect(top.nextTier == nil)
        #expect(top.sharesToNextTier == nil)
    }

    // MARK: F1

    @Test func homeLoadsAminaGroupAndOffers() async throws {
        let viewModel = FamilyHomeViewModel(repositories: repositories(), userId: ID.amina,
                                            householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.firstName == "Amina")
        #expect(content.group.id == ID.saintMichel)
        #expect(content.currentOrders.map(\.offer.id) == [ID.potatoOffer])
        #expect(content.currentOrders.first?.committedShares == 19)
        #expect(content.myOrders.isEmpty)
        #expect(content.newOffers.map(\.offer.id) == [ID.riceOffer])
        #expect(content.savedCents == 0)
    }

    @Test func homeShowsAminaOrderAndSavingsOnceShared() async throws {
        let repos = repositories()
        try await repos.groupOrders.setShare(quantity: 2, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = FamilyHomeViewModel(repositories: repos, userId: ID.amina,
                                            householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.myOrders.first?.myShareQuantity == 2)
        #expect(content.savedCents == 2 * (1_599 - 990))
    }

    @Test func homeFailsOffline() async {
        let viewModel = FamilyHomeViewModel(repositories: repositories(.failing(.offline)), userId: ID.amina,
                                            householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    // MARK: Groupes et F2

    @Test func groupsListMembershipFirstAndJoin() async throws {
        let viewModel = GroupsViewModel(repositories: repositories(), householdId: ID.aminaHousehold)
        await viewModel.load()
        let items = try #require(viewModel.state.value)
        #expect(items.map(\.id) == [ID.saintMichel, ID.hochelaga])
        #expect(items.map(\.isMember) == [true, false])
        #expect(viewModel.myGroups.map(\.id) == [ID.saintMichel])

        await viewModel.join(groupId: ID.hochelaga)
        let joined = try #require(viewModel.state.value?.first { $0.id == ID.hochelaga })
        #expect(joined.isMember)
        #expect(joined.group.householdCount == 28)
        #expect(viewModel.pendingGroupIds.isEmpty)

        await viewModel.leave(groupId: ID.hochelaga)
        #expect(viewModel.state.value?.first { $0.id == ID.hochelaga }?.isMember == false)
    }

    @Test func groupsEmptyInUnknownNeighborhood() async {
        let viewModel = GroupsViewModel(repositories: repositories(), householdId: ID.aminaHousehold,
                                        neighborhood: "Verdun")
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    @Test func groupsFailOffline() async {
        let viewModel = GroupsViewModel(repositories: repositories(.failing(.offline)), householdId: ID.aminaHousehold)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    @Test func groupDetailLoadsPickupAndOrders() async throws {
        let viewModel = GroupDetailViewModel(repositories: repositories(), householdId: ID.aminaHousehold,
                                             groupId: ID.saintMichel)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.isMember)
        #expect(content.members.count == 12)
        #expect(content.pickupPoint?.id == ID.jarryPickup)
        #expect(content.nextSlot != nil)
        #expect(content.openOrders.map(\.offer.id) == [ID.potatoOffer])

        await viewModel.leave()
        #expect(viewModel.state.value?.isMember == false)
        #expect(viewModel.state.value?.group.householdCount == 11)
    }

    @Test func groupDetailFailsOffline() async {
        let viewModel = GroupDetailViewModel(repositories: repositories(.failing(.offline)),
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    // MARK: F3 / F4

    @Test func offerDetailLoadsTheGroupOrder() async throws {
        let viewModel = OfferDetailViewModel(repositories: repositories(), offerId: ID.potatoOffer,
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.product.id == ID.potatoes)
        #expect(content.vendor.id == ID.fermeRive)
        #expect(content.committedShares == 19)
        #expect(content.myShareQuantity == 0)
        #expect(content.isOpen)
        #expect(viewModel.pricing?.currentPriceCents == 1_150)
        #expect(viewModel.quantityOptions == [1, 2, 3])
        #expect(viewModel.selectedQuantity == 1)
        #expect(viewModel.selectionUnlocksTier)
        #expect(viewModel.selectedTotalCents == 990)
        #expect(viewModel.selectedSavingsCents == 609)
        #expect(viewModel.canReserve)
    }

    @Test func aminaShareCrossesTheTierAndCelebrates() async throws {
        let repos = repositories()
        let viewModel = OfferDetailViewModel(repositories: repos, offerId: ID.potatoOffer,
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        viewModel.selectedQuantity = 1
        await viewModel.reserve()

        #expect(viewModel.actionError == nil)
        let content = try #require(viewModel.state.value)
        #expect(content.committedShares == 20)
        #expect(content.myShareQuantity == 1)
        #expect(viewModel.pricing?.currentPriceCents == 990)

        let celebration = try #require(viewModel.celebration)
        #expect(celebration.tierNumber == 2)
        #expect(celebration.tierCount == 3)
        #expect(!celebration.isLastTier)
        #expect(celebration.previousPriceCents == 1_150)
        #expect(celebration.newPriceCents == 990)
        #expect(celebration.committedShares == 20)
        #expect(celebration.myTotalCents == 990)
        #expect(celebration.mySavingsCents == 609)

        let stored = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        #expect(stored.committedShares == 20)
        #expect(stored.currentTierIndex == 1)

        viewModel.dismissCelebration()
        #expect(viewModel.celebration == nil)
        #expect(!viewModel.canReserve)
    }

    @Test func changingTheShareWithoutNewTierDoesNotCelebrate() async throws {
        let viewModel = OfferDetailViewModel(repositories: repositories(), offerId: ID.potatoOffer,
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        await viewModel.reserve()
        viewModel.dismissCelebration()

        viewModel.selectedQuantity = 2
        await viewModel.reserve()
        #expect(viewModel.state.value?.committedShares == 21)
        #expect(viewModel.celebration == nil)

        await viewModel.cancelShare()
        #expect(viewModel.state.value?.committedShares == 19)
        #expect(viewModel.state.value?.myShareQuantity == 0)
        #expect(viewModel.celebration == nil)
    }

    @Test func firstReservationOpensTheGroupOrder() async throws {
        let repos = repositories()
        let viewModel = OfferDetailViewModel(repositories: repos, offerId: ID.riceOffer,
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state.value?.groupOrder == nil)
        #expect(viewModel.state.value?.canStartOrder == true)
        #expect(viewModel.state.value?.isOpen == true)
        #expect(viewModel.canReserve)

        viewModel.selectedQuantity = 2
        await viewModel.reserve()
        #expect(viewModel.actionError == nil)
        let order = try #require(viewModel.state.value?.groupOrder)
        #expect(order.groupId == ID.saintMichel)
        #expect(order.offerId == ID.riceOffer)
        #expect(order.committedShares == 2)
        #expect(viewModel.state.value?.myShareQuantity == 2)
        #expect(try await repos.groupOrders.groupOrders(ofOffer: ID.riceOffer).map(\.id) == [order.id])
    }

    @Test func offerWithoutGroupCannotBeReserved() async throws {
        let viewModel = OfferDetailViewModel(repositories: repositories(), offerId: ID.riceOffer,
                                             householdId: ID.aminaHousehold, groupId: nil)
        await viewModel.load()
        #expect(viewModel.state.value?.canStartOrder == false)
        #expect(!viewModel.canReserve)
        await viewModel.reserve()
        #expect(viewModel.actionError != nil)
    }

    @Test func offerDetailFailsOffline() async {
        let viewModel = OfferDetailViewModel(repositories: repositories(.failing(.offline)), offerId: ID.potatoOffer,
                                             householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    // MARK: F5

    @Test func pickupIsEmptyWithoutShare() async {
        let viewModel = PickupViewModel(repositories: repositories(), householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    @Test func pickupShowsAminaShare() async throws {
        let repos = repositories()
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = PickupViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.pickupPoint.id == ID.jarryPickup)
        #expect(content.hostFirstName == "Amina")
        #expect(content.items.map(\.product.id) == [ID.potatoes])
        #expect(content.totalCents == 990)
        #expect(content.slot != nil)
        #expect(content.minutesUntilPickup(from: .now).map { $0 > 0 } == true)
        #expect(content.orderCode.hasPrefix("GRN-"))
        #expect(content.orderCode == PickupViewModel.orderCode(householdId: ID.aminaHousehold, groupId: ID.saintMichel))
        #expect(!content.qrPayload.isEmpty)
    }

    @Test func pickupFailsOffline() async {
        let viewModel = PickupViewModel(repositories: repositories(.failing(.offline)),
                                        householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }

    // MARK: F6

    @Test func impactIsComputedFromShares() async throws {
        let repos = repositories()
        let viewModel = ImpactViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let before = try #require(viewModel.state.value)
        #expect(before.totalShares == 19)
        #expect(before.householdCount == 11)
        #expect(before.neighborhoodSavingsCents == 19 * (1_599 - 1_150))
        #expect(before.totalKilograms == 190)
        #expect(before.mySavingsCents == 0)
        #expect(before.byProduct.map(\.product.id) == [ID.potatoes])

        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        await viewModel.load()
        let after = try #require(viewModel.state.value)
        #expect(after.householdCount == 12)
        #expect(after.neighborhoodSavingsCents == 20 * (1_599 - 990))
        #expect(after.mySavingsCents == 609)
        #expect(after.myShares == 1)
    }

    /// T-086 : `Share.finalPriceCents` est le total payé pour toute la part (quantité × prix unitaire),
    /// pas un prix unitaire. 3 sacs à 9,90 $ figés à la clôture = 29,70 $ ; économie 3 × (15,99 − 9,90).
    @Test func impactReadsFinalPriceAsShareTotal() async throws {
        var data = FakeData.montreal
        func closed(_ householdId: String, _ quantity: Int, suspended: Cents = 0) -> Share {
            Share(householdId: householdId, quantity: quantity, finalPriceCents: quantity * 990, isPaid: true,
                  suspendedAmountCents: suspended, subsidyCents: 0, qrCode: nil, isPickedUp: false)
        }
        data.shares[ID.potatoOrder] = [closed(ID.aminaHousehold, 3), closed("household-voisin", 2, suspended: 500)]
        let viewModel = ImpactViewModel(repositories: .fake(behavior: .instant, data: data),
                                        householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()

        let content = try #require(viewModel.state.value)
        #expect(content.myShares == 3)
        #expect(content.mySavingsCents == 3 * (1_599 - 990))
        #expect(content.totalShares == 5)
        #expect(content.neighborhoodSavingsCents == 5 * (1_599 - 990))
        #expect(content.byProduct.first?.savingsCents == 5 * (1_599 - 990))
        #expect(content.suspendedAmountCents == 500)
    }

    /// Une part figée plus chère que l'épicerie ne donne jamais d'économie négative.
    @Test func impactNeverCountsNegativeSavingsOnFinalTotal() async throws {
        var data = FakeData.montreal
        data.shares[ID.potatoOrder] = [
            Share(householdId: ID.aminaHousehold, quantity: 2, finalPriceCents: 2 * 1_700, isPaid: true,
                  suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false),
        ]
        let viewModel = ImpactViewModel(repositories: .fake(behavior: .instant, data: data),
                                        householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()

        let content = try #require(viewModel.state.value)
        #expect(content.mySavingsCents == 0)
        #expect(content.neighborhoodSavingsCents == 0)
    }

    @Test func kilogramsAreParsedFromShareUnit() {
        #expect(ImpactViewModel.kilograms(in: "sac de 10 kg") == 10)
        #expect(ImpactViewModel.kilograms(in: "2,5 kg") == 2.5)
        #expect(ImpactViewModel.kilograms(in: "5kg") == 5)
        #expect(ImpactViewModel.kilograms(in: "1 douzaine") == 0)
    }

    @Test func impactFailsOffline() async {
        let viewModel = ImpactViewModel(repositories: repositories(.failing(.offline)),
                                        householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        #expect(viewModel.state.error == .offline)
    }
}
