import Foundation
import Testing
@testable import AMC_MobileApp

/// `Share.finalPriceCents` est le total de la part (quantité × prix unitaire), pas un prix unitaire.
struct FinalPriceTotalTests {
    private typealias ID = FakeData.ID

    private static func share(quantity: Int, total: Cents?) -> Share {
        Share(householdId: ID.aminaHousehold, quantity: quantity, finalPriceCents: total, isPaid: true,
              suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false)
    }

    @Test func unitPriceIsTheTotalDividedByQuantity() {
        #expect(Self.share(quantity: 3, total: 3 * 990).finalUnitPriceCents == 990)
        #expect(Self.share(quantity: 3, total: nil).finalUnitPriceCents == nil)
        #expect(Self.share(quantity: 0, total: 0).finalUnitPriceCents == nil)
    }

    @Test func orderHistoryUsesTheUnitPriceOfAFrozenShare() throws {
        let data = FakeData.montreal
        var order = try #require(data.groupOrders.first { $0.id == ID.potatoOrder })
        order.status = .closed
        let offer = try #require(data.offers.first { $0.id == order.offerId })

        let price = OrderHistoryViewModel.finalPrice(share: Self.share(quantity: 3, total: 3 * 990), order: order, offer: offer)
        #expect(price == 990)
    }

    @Test func solidarityAmountDueIsTheFrozenTotal() {
        #expect(SolidarityMath.amountDue(of: Self.share(quantity: 3, total: 3 * 990), unitPriceCents: 1_200) == 2_970)
        #expect(SolidarityMath.amountDue(of: Self.share(quantity: 3, total: nil), unitPriceCents: 1_200) == 3_600)
    }
}
