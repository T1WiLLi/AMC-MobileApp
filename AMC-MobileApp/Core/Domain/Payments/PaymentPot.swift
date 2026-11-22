// PaymentPot.swift
// Le « pot » d'une commande groupée (E21) : les familles réservent sans payer ; à la clôture
// le prix est figé au palier final et chaque part est payée dans le pot, qui paie ensuite le vendeur.
// Swift pur ; paiements simulés.

import Foundation

nonisolated struct PaymentPot: Sendable, Equatable {
    /// Parts payées, en quantité : « 18 parts payées sur 23 ».
    var paidShareCount: Int
    /// Parts réservées (quantité totale des parts non vides).
    var totalShareCount: Int
    /// Ménages dont la part est payée.
    var paidHouseholdCount: Int
    /// Ménages ayant au moins une part.
    var householdCount: Int
    /// Ce que les familles ont versé dans le pot : somme des `PaymentSimulator.amountDue` des parts payées
    /// (prix final − subvention + don pour un panier suspendu).
    var collectedCents: Cents
    /// Part de `collectedCents` qui revient au vendeur : dons solidaires exclus,
    /// comme `VendorRevenue.Line.collectedCents` (prix final − subvention).
    var collectedForVendorCents: Cents
    /// Dons pour des paniers suspendus versés avec les parts payées (pas un revenu du vendeur).
    var collectedDonationsCents: Cents
    /// Ce que les familles doivent verser en tout une fois le prix figé ; 0 avant la clôture.
    var totalDueCents: Cents
    /// Valeur des parts réservées au prix des paliers (avant subventions et dons).
    /// Avant la clôture : quantité engagée × prix du palier courant (prix du premier palier sous le minimum).
    /// Après : somme des prix finaux figés. Commande annulée : 0.
    var projectedCents: Cents
    /// Prix figé (commande fermée ou livrée) : les parts peuvent être payées.
    var isSettled: Bool

    /// Ce qui reste à verser dans le pot (jamais négatif) ; 0 avant la clôture.
    var remainingCents: Cents { max(0, totalDueCents - collectedCents) }

    /// Toutes les parts sont payées (et il y en a au moins une).
    var isFullyPaid: Bool { isSettled && householdCount > 0 && paidHouseholdCount == householdCount }

    /// - Parameters:
    ///   - shares: parts de la commande ; après la clôture, réparties par `ShareAllocator.allocate`.
    ///   - offer: lot de la commande, pour l'estimation avant la clôture.
    init(order: GroupOrder, shares: [Share], offer: Offer) {
        let active = shares.filter { $0.quantity > 0 }
        let settled = VendorRevenue.counts(order)
        // Une part ne compte comme payée que si son prix est figé (commande fermée ou livrée).
        let paid = settled ? active.filter(\.isPaid) : []

        paidShareCount = paid.reduce(0) { $0 + $1.quantity }
        totalShareCount = active.reduce(0) { $0 + $1.quantity }
        paidHouseholdCount = paid.count
        householdCount = active.count
        collectedCents = paid.reduce(0) { $0 + Self.amountDue($1) }
        collectedForVendorCents = paid.reduce(0) { $0 + Self.vendorAmount($1) }
        collectedDonationsCents = collectedCents - collectedForVendorCents
        totalDueCents = settled ? active.reduce(0) { $0 + Self.amountDue($1) } : 0
        isSettled = settled

        switch order.status {
        case .open, .reached:
            let unitPrice = TierEngine.progress(offer: offer, committedShares: order.committedShares).unitPriceCents ?? 0
            projectedCents = max(0, order.committedShares) * unitPrice
        case .closed, .delivered:
            projectedCents = active.reduce(0) { $0 + max(0, $1.finalPriceCents ?? 0) }
        case .cancelled:
            projectedCents = 0
        }
    }

    /// « Tu paieras au plus X $ » : `quantity` × prix du palier courant de la commande
    /// (prix du premier palier sous le minimum). Le prix ne fait que baisser quand on franchit un palier,
    /// donc c'est un maximum. Quantité ≤ 0 ou lot sans palier : 0.
    static func maxPriceCents(quantity: Int, offer: Offer, order: GroupOrder) -> Cents {
        guard quantity > 0 else { return 0 }
        let unitPrice = TierEngine.progress(offer: offer, committedShares: order.committedShares).unitPriceCents ?? 0
        return quantity * unitPrice
    }

    /// Montant dû d'une part, 0 si son prix n'est pas figé ou si ses montants sont invalides.
    static func amountDue(_ share: Share) -> Cents {
        (try? PaymentSimulator.amountDue(for: share)) ?? 0
    }

    /// Ce que le vendeur reçoit pour une part : prix final (subvention comprise, payée par le fonds
    /// de solidarité), sans le don. 0 si le prix n'est pas figé ou si les montants sont invalides.
    static func vendorGross(_ share: Share) -> Cents {
        guard (try? PaymentSimulator.amountDue(for: share)) != nil else { return 0 }
        return share.finalPriceCents ?? 0
    }

    /// Part payée par la famille qui revient au vendeur : prix final − subvention.
    private static func vendorAmount(_ share: Share) -> Cents {
        guard (try? PaymentSimulator.amountDue(for: share)) != nil else { return 0 }
        return (share.finalPriceCents ?? 0) - share.subsidyCents
    }
}
