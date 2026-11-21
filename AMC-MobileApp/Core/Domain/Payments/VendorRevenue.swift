// VendorRevenue.swift
// Revenus d'un vendeur par lot et par groupe (E07 : RQ-060), calculés à partir des commandes
// fermées et des paiements simulés.

import Foundation

nonisolated enum VendorRevenue {
    struct Line: Identifiable, Sendable, Equatable {
        /// Identifiant du lot ou du groupe (« total » pour la ligne de total).
        var id: String
        var orderCount: Int
        var sharesSold: Int
        /// Somme des prix finaux des parts.
        var grossCents: Cents
        /// Part payée par le fonds de solidarité.
        var subsidyCents: Cents
        /// Encaissé auprès des familles pour le vendeur (dons solidaires exclus).
        var collectedCents: Cents
        /// Ce qui reste à encaisser auprès des familles : brut − subventions − encaissé.
        var outstandingCents: Cents { grossCents - subsidyCents - collectedCents }

        static func empty(_ id: String) -> Line {
            Line(id: id, orderCount: 0, sharesSold: 0, grossCents: 0, subsidyCents: 0, collectedCents: 0)
        }

        mutating func add(_ other: Line) {
            orderCount += other.orderCount
            sharesSold += other.sharesSold
            grossCents += other.grossCents
            subsidyCents += other.subsidyCents
            collectedCents += other.collectedCents
        }
    }

    struct Report: Sendable, Equatable {
        var byOffer: [Line]
        var byGroup: [Line]
        var total: Line
    }

    /// Commande dont les parts sont figées et comptent dans les revenus.
    static func counts(_ order: GroupOrder) -> Bool {
        order.status == .closed || order.status == .delivered
    }

    /// - Parameters:
    ///   - offers: lots connus ; seules les commandes d'un lot de `vendorId` sont comptées.
    ///   - sharesByOrder: parts réparties (`ShareAllocator.allocate`) par identifiant de commande.
    ///   - payments: paiements simulés ; seuls les réussis comptent, un seul par ménage et commande.
    static func report(
        vendorId: String,
        offers: [Offer],
        orders: [GroupOrder],
        sharesByOrder: [String: [Share]],
        payments: [PaymentRecord]
    ) -> Report {
        let vendorOffers = Set(offers.filter { $0.vendorId == vendorId }.map(\.id))
        var byOffer: [String: Line] = [:]
        var byGroup: [String: Line] = [:]
        var total = Line.empty("total")

        for order in orders where counts(order) && vendorOffers.contains(order.offerId) {
            let line = line(for: order, shares: sharesByOrder[order.id] ?? [], payments: payments)
            byOffer[order.offerId, default: .empty(order.offerId)].add(line)
            byGroup[order.groupId, default: .empty(order.groupId)].add(line)
            total.add(line)
        }
        return Report(
            byOffer: byOffer.values.sorted { $0.id < $1.id },
            byGroup: byGroup.values.sorted { $0.id < $1.id },
            total: total
        )
    }

    private static func line(for order: GroupOrder, shares: [Share], payments: [PaymentRecord]) -> Line {
        let active = shares.filter { $0.quantity > 0 }
        var paid: [String: PaymentRecord] = [:]
        for payment in payments where payment.groupOrderId == order.id && payment.status == .succeeded {
            if paid[payment.householdId] == nil { paid[payment.householdId] = payment }
        }
        let collected = active.reduce(0) { sum, share in
            guard let payment = paid[share.householdId] else { return sum }
            return sum + payment.finalPriceCents - payment.subsidyCents
        }
        return Line(
            id: order.id,
            orderCount: 1,
            sharesSold: active.reduce(0) { $0 + $1.quantity },
            grossCents: active.reduce(0) { $0 + ($1.finalPriceCents ?? 0) },
            subsidyCents: active.reduce(0) { $0 + $1.subsidyCents },
            collectedCents: collected
        )
    }
}
