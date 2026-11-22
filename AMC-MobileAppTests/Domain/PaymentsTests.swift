import Foundation
import Testing
@testable import AMC_MobileApp

/// E07 : paiement simulé (RQ-058), reçus (RQ-059), revenus vendeur (RQ-060), remboursements (RQ-061).
struct PaymentsTests {
    private static let date = Date(timeIntervalSince1970: 1_795_100_000)
    private let offer = TierEngineTests.offer
    private let simulator = PaymentSimulator(now: { PaymentsTests.date })

    private func share(_ household: String, _ quantity: Int, suspended: Cents = 0) -> Share {
        TierEngineTests.share(household, quantity, suspended: suspended)
    }

    private func order(_ status: GroupOrder.Status = .closed, id: String = "go1", group: String = "g1") -> GroupOrder {
        var order = TierEngineTests.order(committed: 20, status: status)
        order.id = id
        order.groupId = group
        return order
    }

    /// h1 : 2 parts, h2 : 1 part subventionnée, h3 : 1 part + 500 ¢ de panier suspendu.
    private func allocated(orderId: String = "go1") throws -> [Share] {
        try ShareAllocator.allocate(
            orderId: orderId, offer: offer,
            shares: [share("h1", 2), share("h2", 1), share("h3", 1, suspended: 500)],
            unitPriceCents: 990, eligibleHouseholdIds: ["h2"], solidarityFundCents: 200
        ).shares
    }

    private func allocatedShare(_ household: String, orderId: String = "go1") throws -> Share {
        try #require(try allocated(orderId: orderId).first { $0.householdId == household })
    }

    // MARK: RQ-058 paiement simulé

    @Test func successfulPaymentRecordsTheAmountDue() throws {
        let h2 = try allocatedShare("h2")
        let record = try simulator.pay(share: h2, order: order())
        #expect(record.id == "PAY-go1-h2-1")
        #expect(record.status == .succeeded)
        #expect(record.finalPriceCents == 990)
        #expect(record.subsidyCents == 700)
        #expect(record.amountDueCents == 290)
        #expect(record.methodLabel == "Apple Pay")
        #expect(record.date == Self.date)
        #expect(PaymentSimulator.applying(record, to: h2).isPaid)
    }

    @Test func suspendedDonationIsAddedToTheAmountDue() throws {
        let record = try simulator.pay(share: try allocatedShare("h3"), order: order())
        #expect(record.donationCents == 500)
        #expect(record.amountDueCents == 1_490)
    }

    @Test func declinedPaymentLeavesTheShareUnpaidAndCanBeRetried() throws {
        let h1 = try allocatedShare("h1")
        let declined = try PaymentSimulator(outcome: .declined, now: { PaymentsTests.date })
            .pay(share: h1, order: order())
        #expect(declined.status == .declined)
        #expect(!PaymentSimulator.applying(declined, to: h1).isPaid)

        let retry = try simulator.pay(share: h1, order: order(), existing: [declined])
        #expect(retry.id == "PAY-go1-h1-2")
        #expect(retry.status == .succeeded)
    }

    @Test func refusesToPayTwice() throws {
        let h1 = try allocatedShare("h1")
        let first = try simulator.pay(share: h1, order: order())
        #expect(throws: AppError.self) { try simulator.pay(share: h1, order: order(), existing: [first]) }
        var paid = h1
        paid.isPaid = true
        #expect(throws: AppError.self) { try simulator.pay(share: paid, order: order()) }
    }

    @Test(arguments: [GroupOrder.Status.open, .reached, .cancelled])
    func refusesToPayAnOrderThatIsNotClosed(status: GroupOrder.Status) throws {
        let h1 = try allocatedShare("h1")
        #expect(throws: AppError.self) { try simulator.pay(share: h1, order: order(status)) }
    }

    @Test func refusesAShareWithoutFinalPrice() {
        #expect(throws: AppError.self) { try simulator.pay(share: share("h1", 2), order: order()) }
    }

    @Test func payAllSkipsSharesAlreadyPaid() throws {
        let shares = try allocated()
        let first = try simulator.pay(share: shares[0], order: order())
        let records = try simulator.payAll(shares: shares, order: order(), existing: [first])
        #expect(records.map(\.householdId) == ["h2", "h3"])
        #expect(records.allSatisfy { $0.status == .succeeded })
    }

    // MARK: RQ-061 remboursements

    @Test func cancelledOrderRefundsOnlyPaidShares() throws {
        let shares = try allocated()
        let paid = try simulator.pay(share: shares[0], order: order())
        let declined = try PaymentSimulator(outcome: .declined).pay(share: shares[1], order: order())
        let refunds = try simulator.refunds(for: order(.cancelled), payments: [paid, declined])
        #expect(refunds.count == 1)
        #expect(refunds.first?.id == "RF-PAY-go1-h1-1")
        #expect(refunds.first?.householdId == "h1")
        #expect(refunds.first?.amountCents == paid.amountDueCents)
        #expect(refunds.first?.date == Self.date)
    }

    @Test func refundsAreNeverIssuedTwiceNorForOpenOrders() throws {
        let paid = try simulator.pay(share: try allocatedShare("h1"), order: order())
        let refunds = try simulator.refunds(for: order(.cancelled), payments: [paid])
        #expect(try simulator.refunds(for: order(.cancelled), payments: [paid], existingRefunds: refunds).isEmpty)
        #expect(throws: AppError.self) { try simulator.refunds(for: order(.closed), payments: [paid]) }
        #expect(try simulator.refunds(for: order(.cancelled), payments: []).isEmpty)
    }

    // MARK: RQ-059 reçus

    @Test func receiptShowsSavingsSubsidyAndTotal() throws {
        let h2 = try allocatedShare("h2")
        let payment = try simulator.pay(share: h2, order: order())
        let receipt = try Receipt.make(
            share: h2, order: order(), offer: offer, productName: "Riz basmati",
            referencePricePerShareCents: 1_600, payment: payment
        )
        #expect(receipt.quantity == 1)
        #expect(receipt.unitPriceCents == 990)
        #expect(receipt.finalPriceCents == 990)
        #expect(receipt.referencePriceCents == 1_600)
        #expect(receipt.savingsCents == 610)
        #expect(receipt.subsidyCents == 700)
        #expect(receipt.donationCents == 0)
        #expect(receipt.totalCents == 290)
        #expect(receipt.isPaid)
    }

    @Test func receiptWithDonationAndNoSavings() throws {
        let h3 = try allocatedShare("h3")
        let receipt = try Receipt.make(
            share: h3, order: order(), offer: offer, productName: "Riz", referencePricePerShareCents: 900
        )
        #expect(receipt.savingsCents == 0)
        #expect(receipt.donationCents == 500)
        #expect(receipt.totalCents == 1_490)
        #expect(!receipt.isPaid)
    }

    @Test func receiptIgnoresAPaymentOfAnotherHousehold() throws {
        let payment = try simulator.pay(share: try allocatedShare("h1"), order: order())
        let receipt = try Receipt.make(
            share: try allocatedShare("h2"), order: order(), offer: offer, productName: "Riz",
            referencePricePerShareCents: 1_600, payment: payment
        )
        #expect(receipt.payment == nil)
    }

    @MainActor
    @Test func receiptPlainTextIsInFrench() throws {
        let h3 = try allocatedShare("h3")
        let payment = try simulator.pay(share: h3, order: order())
        let text = try Receipt.make(
            share: h3, order: order(), offer: offer, productName: "Riz basmati",
            referencePricePerShareCents: 1_600, payment: payment
        ).plainText()
        #expect(text.hasPrefix("Reçu LeGrenier"))
        #expect(text.contains("Riz basmati : 1 × 10 kg"))
        #expect(text.contains("Tu économises \(Money.format(610))"))
        #expect(text.contains("Ton don pour un panier suspendu : +\(Money.format(500))"))
        #expect(text.contains("Total payé : \(Money.format(1_490))"))
        #expect(text.contains("Payé avec Apple Pay"))
        #expect(!text.contains("fonds de solidarité"))
    }

    @MainActor
    @Test func unpaidReceiptPlainTextShowsAmountToPay() throws {
        let text = try Receipt.make(
            share: try allocatedShare("h2"), order: order(), offer: offer, productName: "Riz",
            referencePricePerShareCents: 1_600
        ).plainText()
        #expect(text.contains("Payé par le fonds de solidarité : −\(Money.format(700))"))
        #expect(text.contains("Total à payer : \(Money.format(290))"))
    }

    // MARK: RQ-060 revenus vendeur

    @Test func vendorRevenueByOfferAndGroup() throws {
        let sharesA = try allocated(orderId: "goA")
        let sharesB = try allocated(orderId: "goB")
        let orderA = order(id: "goA", group: "g1")
        let orderB = order(.delivered, id: "goB", group: "g2")
        let cancelled = order(.cancelled, id: "goC", group: "g1")
        var otherVendorOffer = offer
        otherVendorOffer.id = "o2"
        otherVendorOffer.vendorId = "v2"
        var otherOrder = order(id: "goD", group: "g1")
        otherOrder.offerId = "o2"

        let paymentsA = try simulator.payAll(shares: sharesA, order: orderA)
        let paymentB = try simulator.pay(share: sharesB[2], order: orderB) // h3 seulement, avec don

        let report = VendorRevenue.report(
            vendorId: "v1", offers: [offer, otherVendorOffer],
            orders: [orderA, orderB, cancelled, otherOrder],
            sharesByOrder: ["goA": sharesA, "goB": sharesB, "goC": sharesA, "goD": sharesA],
            payments: paymentsA + [paymentB]
        )

        // Par commande : 4 parts × 990 = 3 960 brut, 700 de subvention.
        #expect(report.byGroup.map(\.id) == ["g1", "g2"])
        let g1 = report.byGroup[0], g2 = report.byGroup[1]
        #expect(g1.grossCents == 3_960 && g1.subsidyCents == 700 && g1.collectedCents == 3_260)
        #expect(g1.outstandingCents == 0)
        #expect(g2.collectedCents == 990) // le don de 500 va au fonds, pas au vendeur
        #expect(g2.outstandingCents == 3_960 - 700 - 990)

        #expect(report.byOffer.map(\.id) == ["o1"])
        #expect(report.byOffer[0].orderCount == 2)
        #expect(report.byOffer[0].sharesSold == 8)
        #expect(report.total.grossCents == 7_920)
        #expect(report.total.subsidyCents == 1_400)
        #expect(report.total.collectedCents == 4_250)
    }

    @Test func vendorRevenueIgnoresDeclinedAndDuplicatePayments() throws {
        let shares = try allocated()
        let declined = try PaymentSimulator(outcome: .declined).pay(share: shares[0], order: order())
        let report = VendorRevenue.report(
            vendorId: "v1", offers: [offer], orders: [order()],
            sharesByOrder: ["go1": shares], payments: [declined]
        )
        #expect(report.total.collectedCents == 0)
        #expect(report.total.outstandingCents == 3_960 - 700)
    }
}
