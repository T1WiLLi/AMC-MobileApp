import Foundation
import Testing
@testable import AMC_MobileApp

/// E21-4 : « Payé et reçu côté famille » : états dérivés après la clôture.
@MainActor
struct ShareSettlementTests {
    private typealias ID = FakeData.ID

    private static func order(_ status: GroupOrder.Status) -> GroupOrder {
        GroupOrder(id: "go1", groupId: "g", offerId: "o", status: status, currentTierIndex: 1,
                   committedShares: 22, committedHouseholds: 3, pickupPointId: nil, pickupSlots: [])
    }

    private static func share(quantity: Int = 2, finalPrice: Cents? = 1_980, paid: Bool = true,
                              subsidy: Cents = 0, donation: Cents = 0) -> Share {
        Share(householdId: "h1", quantity: quantity, finalPriceCents: finalPrice, isPaid: paid,
              suspendedAmountCents: donation, subsidyCents: subsidy, qrCode: nil, isPickedUp: false)
    }

    // MARK: ShareSettlement

    @Test func openOrderOrNoShareHasNoSettlement() {
        #expect(ShareSettlement.make(order: Self.order(.open), share: Self.share(), groceryPricePerShareCents: 1_599) == nil)
        #expect(ShareSettlement.make(order: Self.order(.reached), share: Self.share(), groceryPricePerShareCents: 1_599) == nil)
        #expect(ShareSettlement.make(order: Self.order(.closed), share: nil, groceryPricePerShareCents: 1_599) == nil)
        #expect(ShareSettlement.make(order: nil, share: Self.share(), groceryPricePerShareCents: 1_599) == nil)
        #expect(ShareSettlement.make(order: Self.order(.closed), share: Self.share(quantity: 0),
                                     groceryPricePerShareCents: 1_599) == nil)
        // Prix final pas encore lu : pas d'état inventé.
        #expect(ShareSettlement.make(order: Self.order(.closed), share: Self.share(finalPrice: nil),
                                     groceryPricePerShareCents: 1_599) == nil)
    }

    @Test func paidShareShowsWhatWasPaidAndSavedVsGrocery() {
        let share = Self.share(subsidy: 300, donation: 500)
        let settlement = ShareSettlement.make(order: Self.order(.closed), share: share, groceryPricePerShareCents: 1_599)
        // Payé : 19,80 − 3,00 + 5,00 ; économisé : (15,99 − 9,90) × 2.
        #expect(settlement == .paid(paidCents: 1_980 - 300 + 500, savedCents: 2 * (1_599 - 990)))
        #expect(settlement?.isPaid == true)
        let delivered = ShareSettlement.make(order: Self.order(.delivered), share: share, groceryPricePerShareCents: 1_599)
        #expect(delivered?.isPaid == true)
    }

    @Test func savingsNeverNegative() {
        let settlement = ShareSettlement.make(order: Self.order(.closed), share: Self.share(), groceryPricePerShareCents: 500)
        #expect(settlement == .paid(paidCents: 1_980, savedCents: 0))
    }

    @Test func declinedShareKeepsTheAmountDue() {
        let settlement = ShareSettlement.make(order: Self.order(.closed), share: Self.share(paid: false, donation: 500),
                                              groceryPricePerShareCents: 1_599)
        #expect(settlement == .declined(dueCents: 2_480))
        #expect(settlement?.isPaid == false)
    }

    @Test func cancelledOrderChargedNothing() {
        let settlement = ShareSettlement.make(order: Self.order(.cancelled), share: Self.share(finalPrice: nil, paid: false),
                                              groceryPricePerShareCents: 1_599)
        #expect(settlement == .cancelled)
    }

    // MARK: Barre de paliers et carte de l'Accueil

    @Test func closedTierBarNoLongerAsksToUnlock() {
        let tiers = TierEngineTests.offer.tiers
        let open = TierProgressBar(tiers: tiers, committedShares: 1, totalShares: 40)
        #expect(open.nudge != nil)
        let closed = TierProgressBar(tiers: tiers, committedShares: 1, totalShares: 40, isClosed: true)
        #expect(closed.nudge == nil)
        #expect(closed.shortNudge == nil)
    }

    // MARK: Fiche du lot

    private func closeAfterReserving(outcome: PaymentSimulator.Outcome) async throws -> OfferDetailViewModel {
        let data = FakeData.montreal
        let fake = AppRepositories.fake(behavior: .instant, data: data)
        let repositories = AppRepositories(
            users: fake.users, groups: fake.groups, vendors: fake.vendors, offers: fake.offers,
            groupOrders: FakeGroupOrderRepository(
                groupOrders: data.groupOrders, shares: data.shares, offers: data.offers,
                payments: PaymentSimulator(outcome: outcome)
            ),
            pickupPoints: fake.pickupPoints
        )
        let order = try #require(data.groupOrders.first { $0.id == ID.potatoOrder })
        let model = OfferDetailViewModel(repositories: repositories, offerId: order.offerId,
                                         householdId: ID.aminaHousehold, groupId: order.groupId, userId: ID.amina)
        await model.load()
        model.selectedQuantity = 2
        await model.reserve()
        #expect(model.settlement == nil)
        #expect(model.receipt == nil)
        await model.closeOrder()
        #expect(model.actionError == nil)
        return model
    }

    @Test func paidShareGetsAReceipt() async throws {
        let model = try await closeAfterReserving(outcome: .success)
        let content = try #require(model.state.value)
        let share = try #require(content.myShare)
        let unit = try #require(share.finalUnitPriceCents)
        #expect(model.settlement == .paid(paidCents: share.finalPriceCents ?? 0,
                                          savedCents: 2 * (content.product.referenceGroceryPriceCents - unit)))
        let receipt = try #require(model.receipt)
        #expect(receipt.quantity == 2)
        #expect(receipt.unitPriceCents == unit)
        #expect(receipt.totalCents == share.finalPriceCents)
        #expect(receipt.groupOrderId == ID.potatoOrder)
        #expect(receipt.productName == content.product.name)
        #expect(receipt.payment?.methodLabel == PaymentSimulator.methodLabel)
        #expect(receipt.isPaid)
        // Plus de plafond « au plus » une fois la commande fermée.
        #expect(model.reservedMaxPriceCents == nil)
    }

    @Test func declinedPaymentHasNoReceipt() async throws {
        let model = try await closeAfterReserving(outcome: .declined)
        guard case .declined(let due) = model.settlement else {
            Issue.record("attendu : paiement refusé")
            return
        }
        #expect(due == model.state.value?.myShare?.finalPriceCents)
        #expect(model.receipt == nil)
    }

    @Test func homeShowsThePaidClosedOrder() async throws {
        let data = FakeData.montreal
        let repositories = AppRepositories.fake(behavior: .instant, data: data)
        let order = try #require(data.groupOrders.first { $0.id == ID.potatoOrder })
        let model = OfferDetailViewModel(repositories: repositories, offerId: order.offerId,
                                         householdId: ID.aminaHousehold, groupId: order.groupId, userId: ID.amina)
        await model.load()
        await model.reserve()
        await model.closeOrder()

        let home = FamilyHomeViewModel(repositories: repositories, userId: ID.amina,
                                       householdId: ID.aminaHousehold, groupId: order.groupId)
        await home.load()
        let mine = try #require(home.state.value?.myOrders.first { $0.offer.id == order.offerId })
        #expect(mine.isClosed)
        #expect(mine.isPaid)
        #expect(mine.myShareQuantity == 1)
    }

    @Test func openSummaryIsNeitherClosedNorPaid() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        try await repositories.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let home = FamilyHomeViewModel(repositories: repositories, userId: ID.amina,
                                       householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await home.load()
        let mine = try #require(home.state.value?.myOrders.first)
        #expect(!mine.isClosed)
        #expect(!mine.isPaid)
    }
}
