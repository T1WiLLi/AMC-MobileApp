// TierEngine.swift
// Règles des paliers de prix d'une commande groupée (E06 : RQ-051 à RQ-054).
// Swift pur, sans Firebase : la transaction Firestore (B-019) et les dépôts fake l'appellent.

import Foundation

nonisolated enum TierEngine {
    /// Où en est une commande par rapport aux paliers de son lot. Sert à TierProgressBar et aux textes VoiceOver.
    struct Progress: Sendable, Equatable {
        /// Index dans `Offer.sortedTiers` du palier atteint, nil sous le premier palier.
        var currentTierIndex: Int?
        var currentTier: PriceTier?
        var nextTier: PriceTier?
        /// Parts qui manquent pour le prochain palier, nil si le dernier est atteint.
        var sharesToNextTier: Int?
        /// Prix d'une part au palier atteint ; sous le premier palier, prix du premier palier (prix « si ça part »).
        var unitPriceCents: Cents?
        /// Le minimum pour lancer la livraison est atteint.
        var isLaunchable: Bool
        /// Parts encore disponibles dans le lot.
        var remainingShares: Int
    }

    /// Résultat de la clôture (RQ-053, RQ-054).
    enum ClosureOutcome: Sendable, Equatable {
        /// Commande confirmée : prix figé au palier atteint.
        case confirmed(tierIndex: Int, unitPriceCents: Cents)
        /// Minimum non atteint : commande annulée.
        case cancelled
    }

    static func progress(offer: Offer, committedShares: Int) -> Progress {
        let tiers = offer.sortedTiers
        let index = offer.tierIndex(forCommittedShares: committedShares)
        let next = offer.nextTier(afterCommittedShares: committedShares)
        return Progress(
            currentTierIndex: index,
            currentTier: index.map { tiers[$0] },
            nextTier: next,
            sharesToNextTier: next.map { $0.minShares - committedShares },
            unitPriceCents: index.map { tiers[$0].priceCents } ?? tiers.first?.priceCents,
            isLaunchable: committedShares >= offer.minimumSharesToLaunch,
            remainingShares: max(0, offer.totalShares - committedShares)
        )
    }

    /// Une commande dont on peut encore changer les parts.
    static func isOpen(_ order: GroupOrder) -> Bool {
        order.status == .open || order.status == .reached
    }

    /// RQ-051 : recalcule quantité, ménages, palier et statut après un changement de parts,
    /// comme la transaction Firestore le fera en une fois. Lève `.orderClosed` si la commande est fermée.
    static func recalculated(_ order: GroupOrder, offer: Offer, shares: [Share]) throws -> GroupOrder {
        guard isOpen(order) else { throw AppError.orderClosed }
        // Une quantité négative ferait disparaître les parts des autres du total (T-093).
        guard shares.allSatisfy({ $0.quantity >= 0 }) else {
            throw AppError.invalidInput(String(localized: "La quantité ne peut pas être négative."))
        }
        let committed = shares.reduce(0) { $0 + $1.quantity }
        guard committed <= offer.totalShares else {
            throw AppError.invalidInput(String(localized: "Ce lot ne compte que \(offer.totalShares) parts."))
        }
        var order = order
        order.committedShares = committed
        order.committedHouseholds = shares.filter { $0.quantity > 0 }.count
        order.currentTierIndex = offer.tierIndex(forCommittedShares: committed)
        order.status = committed >= offer.minimumSharesToLaunch ? .reached : .open
        return order
    }

    /// RQ-052 : un nouveau palier franchi, à fêter (animation, notification locale). Faux si on redescend.
    static func crossedNewTier(from old: GroupOrder, to new: GroupOrder) -> Bool {
        (new.currentTierIndex ?? -1) > (old.currentTierIndex ?? -1)
    }

    /// RQ-053 : la commande doit être clôturée (date limite passée, encore ouverte).
    static func shouldClose(_ order: GroupOrder, offer: Offer, now: Date = .now) -> Bool {
        isOpen(order) && now >= offer.deadline
    }

    static func closureOutcome(offer: Offer, committedShares: Int) -> ClosureOutcome {
        guard committedShares >= offer.minimumSharesToLaunch,
              let index = offer.tierIndex(forCommittedShares: committedShares) else { return .cancelled }
        return .confirmed(tierIndex: index, unitPriceCents: offer.sortedTiers[index].priceCents)
    }

    /// RQ-053, RQ-054 : clôture la commande. Le palier est figé : après ça, le prix ne bouge plus (RQ-052).
    static func closed(_ order: GroupOrder, offer: Offer) throws -> (order: GroupOrder, outcome: ClosureOutcome) {
        guard isOpen(order) else { throw AppError.orderClosed }
        var order = order
        let outcome = closureOutcome(offer: offer, committedShares: order.committedShares)
        switch outcome {
        case .confirmed(let tierIndex, _):
            order.status = .closed
            order.currentTierIndex = tierIndex
        case .cancelled:
            order.status = .cancelled
        }
        return (order, outcome)
    }

    /// Texte VoiceOver et sous-titre : « Encore 3 parts pour le prochain palier ».
    @MainActor
    static func nextTierSummary(_ progress: Progress) -> String {
        guard let missing = progress.sharesToNextTier, let next = progress.nextTier else {
            return String(localized: "Meilleur prix atteint")
        }
        let parts = FrenchPlural.count(missing, "part")
        return String(localized: "Encore \(parts) pour passer à \(Money.format(next.priceCents)) la part")
    }
}
