// GroupOrderClosure.swift
// Clôture d'une commande groupée et paiement simulé des parts au pot du groupe (E21-2).
// Même calcul pour `FakeGroupOrderRepository` et `FirestoreGroupOrderRepository` (dans sa transaction) :
//   1. qui ferme et quand (`ClosurePolicy`) : à la main par la coordination ou le vendeur du lot, avant ou après
//      la date limite ; automatiquement seulement après la date limite ;
//   2. l'issue (`TierEngine.closed`) : confirmée au palier atteint, annulée sous le minimum (personne ne paie) ;
//   3. confirmée : prix figés (`ShareAllocator.allocate`), puis chaque part payée avec `PaymentSimulator`
//      (`isPaid` à true pour chaque paiement réussi, inchangé s'il est refusé).

import Foundation

/// Qui déclenche la clôture.
nonisolated enum GroupOrderClosureTrigger: Sendable, Equatable {
    /// Bouton « Fermer la commande » : coordonnateur du groupe (`membership`) ou vendeur du lot.
    case manual(user: AppUser, membership: GroupMember?)
    /// Premier appareil qui ouvre la commande après la date limite (RQ-053 a).
    case automatic
}

/// Résultat d'une clôture.
nonisolated struct GroupOrderClosure: Sendable, Equatable {
    /// La commande figée (`closed` ou `cancelled`).
    var order: GroupOrder
    var outcome: TierEngine.ClosureOutcome
    /// Répartition entre les ménages ; nil si la commande est annulée.
    var allocation: ShareAllocator.Allocation?
    /// Parts après la clôture : prix figé, subvention, QR et `isPaid`. Vide si la commande est annulée.
    var shares: [Share]
    /// Une tentative de paiement par part encore impayée ; vide si la commande est annulée.
    var payments: [PaymentRecord]

    var isConfirmed: Bool { order.status == .closed }
    /// Parts payées avec succès à cette clôture.
    var paidCount: Int { payments.filter { $0.status == .succeeded }.count }
    /// Parts dont le paiement simulé a été refusé.
    var declinedCount: Int { payments.filter { $0.status == .declined }.count }
}

nonisolated enum GroupOrderClosing {
    /// Clôture `order` et paie les parts. Fonction pure : le dépôt écrit ensuite le résultat.
    /// - Throws: `.orderClosed` si la commande est déjà fermée (idempotent : aucun second paiement),
    ///   `.invalidInput` si la clôture automatique arrive avant la date limite ou si l'utilisateur n'a pas le droit.
    static func close(
        order: GroupOrder,
        offer: Offer,
        shares: [Share],
        trigger: GroupOrderClosureTrigger,
        now: Date,
        eligibleHouseholdIds: Set<String> = [],
        solidarityFundCents: Cents = 0,
        payments: PaymentSimulator
    ) throws -> GroupOrderClosure {
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        let closed: GroupOrder
        let outcome: TierEngine.ClosureOutcome
        switch trigger {
        case .manual(let user, let membership):
            (closed, outcome) = try ClosurePolicy.close(user: user, membership: membership, offer: offer, order: order)
        case .automatic:
            switch ClosurePolicy.automaticClosure(order: order, offer: offer, now: now) {
            case .notDue:
                throw AppError.invalidInput(String(localized: "La commande se clôture à la date limite du lot."))
            case .alreadyClosed:
                throw AppError.orderClosed
            case .closed(let order, let result):
                (closed, outcome) = (order, result)
            }
        }

        guard case .confirmed(_, let unitPriceCents) = outcome else {
            // Minimum non atteint : commande annulée, personne n'est débité.
            return GroupOrderClosure(order: closed, outcome: outcome, allocation: nil, shares: [], payments: [])
        }
        let allocation = try ShareAllocator.allocate(
            orderId: order.id, offer: offer, shares: shares, unitPriceCents: unitPriceCents,
            eligibleHouseholdIds: eligibleHouseholdIds, solidarityFundCents: solidarityFundCents
        )
        let records = try payments.payAll(shares: allocation.shares, order: closed)
        let paidShares = allocation.shares.map { share in
            records.first { $0.householdId == share.householdId }
                .map { PaymentSimulator.applying($0, to: share) } ?? share
        }
        return GroupOrderClosure(
            order: closed, outcome: outcome, allocation: allocation, shares: paidShares, payments: records
        )
    }
}

extension PaymentSimulator {
    /// Argument de lancement (démo) : le faux terminal refuse tous les paiements à la clôture.
    nonisolated static let demoDeclinedArgument = "-demoPaymentDeclined"

    /// Simulateur de l'app : succès, ou refus avec `-demoPaymentDeclined`.
    nonisolated static func fromLaunchArguments(
        _ arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> PaymentSimulator {
        PaymentSimulator(outcome: arguments.contains(demoDeclinedArgument) ? .declined : .success)
    }
}
