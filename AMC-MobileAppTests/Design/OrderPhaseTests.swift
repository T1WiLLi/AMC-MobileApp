import Testing
@testable import AMC_MobileApp

/// T-196 : statut affiché sur `OfferCard` (et la carte vendeur) selon l'état du lot et de la commande.
@MainActor
struct OrderPhaseTests {
    private func card(offer: Offer.Status = .active, order: GroupOrder.Status?, isClosed: Bool = false) -> OfferCard {
        var offer_ = CardPreviewData.offer
        offer_.status = offer
        return OfferCard(offer: offer_, product: CardPreviewData.product, vendor: CardPreviewData.vendor,
                         committedShares: 25, committedHouseholds: 25, isClosed: isClosed, orderStatus: order)
    }

    @Test func openOrderKeepsTheDeadline() {
        for status in [GroupOrder.Status.open, .reached] {
            let card = card(order: status)
            #expect(card.phase == .open)
            #expect(card.phase.title == nil)
            #expect(card.accessibilityText.contains("se termine"))
        }
        #expect(card(order: nil).phase == .open)
    }

    @Test func closedDeliveredAndCancelledOrdersReplaceTheDeadline() {
        #expect(card(order: .closed).phase == .closed)
        #expect(card(order: .delivered).phase == .delivered)
        #expect(card(order: .cancelled).phase == .cancelled)
        #expect(OrderPhase.closed.title == "Fermée, en préparation")
        #expect(OrderPhase.delivered.title == "Livrée")
        #expect(OrderPhase.cancelled.title == "Annulée")
        for status in [GroupOrder.Status.closed, .delivered, .cancelled] {
            #expect(!card(order: status).accessibilityText.contains("se termine"))
        }
    }

    @Test func legacyIsClosedFlagStillMeansClosed() {
        #expect(card(order: nil, isClosed: true).phase == .closed)
        #expect(card(order: .reached, isClosed: true).phase == .closed)
    }

    @Test func aWithdrawnOrFinishedOfferIsNotShownAsOpen() {
        #expect(card(offer: .closed, order: nil).phase == .closed)
        #expect(card(offer: .cancelled, order: nil).phase == .cancelled)
        #expect(card(offer: .draft, order: nil).phase == .open)
    }

    @Test func everyNonOpenPhaseHasASymbolAndAVoiceOverText() {
        for phase in [OrderPhase.closed, .delivered, .cancelled] {
            #expect(phase.title != nil)
            #expect(phase.spokenText != nil)
            #expect(!phase.symbol.isEmpty)
        }
        #expect(OrderPhase.open.spokenText == nil)
    }

    @Test func vendorPhaseAggregatesAllGroupOrders() {
        #expect(OrderPhase.aggregate(offer: .active, orders: []) == .open)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.open, .closed]) == .open)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.reached]) == .open)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.closed, .closed]) == .closed)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.closed, .delivered]) == .closed)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.delivered, .delivered]) == .delivered)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.cancelled, .closed]) == .closed)
        #expect(OrderPhase.aggregate(offer: .active, orders: [.cancelled]) == .cancelled)
    }
}
