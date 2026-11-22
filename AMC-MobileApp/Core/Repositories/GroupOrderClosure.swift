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
    /// T-195 : récapitulatif du versement au vendeur (brut, commission, net, acompte, retenu) ; nil si annulée.
    var vendorPayout: VendorPayoutRecord? = nil
    /// T-195 : ce que le fonds de solidarité a payé de subventions à cette clôture, avant les paniers suspendus.
    var fundUsedCents: Cents = 0
    /// T-195 : paniers suspendus de la commande, versés dans le fonds pour payer les subventions en premier.
    var contributedCents: Cents = 0
    /// T-195 : débit net du fonds de groupe (`fundUsedCents` moins les paniers suspendus), jamais négatif.
    var fundDebitCents: Cents { max(0, fundUsedCents - contributedCents) }
    /// T-195 : ligne d'historique à ajouter au fonds (kind `.application`) ; nil si le fonds n'est pas débité.
    var fundEntry: SolidarityFund.Entry? = nil

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
        fund: SolidarityFund? = nil,
        vendorIsVerified: Bool = false,
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
        // T-195 : les ménages qui se sont déclarés admissibles (leur statut est vérifié par firestore.rules) s'ajoutent
        // à ceux que l'appelant fournit ; le fonds vient de la lecture transactionnelle, sinon du solde passé.
        let eligible = eligibleHouseholdIds.union(shares.filter { $0.solidarityEligible == true }.map(\.householdId))
        let starting = fund ?? SolidarityFund(entries: solidarityFundCents > 0 ? [
            .init(kind: .contribution, orderId: nil, amountCents: solidarityFundCents, basketCount: 0, date: now)
        ] : [])
        let application = try SolidarityLedger.apply(
            orderId: order.id, offer: offer, shares: shares, unitPriceCents: unitPriceCents,
            eligibleHouseholdIds: eligible, fund: starting, date: now
        )
        let allocation = application.allocation
        let records = try payments.payAll(shares: allocation.shares, order: closed)
        let paidShares = allocation.shares.map { share in
            records.first { $0.householdId == share.householdId }
                .map { PaymentSimulator.applying($0, to: share) } ?? share
        }
        let payout = VendorPayout(order: closed, shares: paidShares, vendorIsVerified: vendorIsVerified)
        var closure = GroupOrderClosure(
            order: closed, outcome: outcome, allocation: allocation, shares: paidShares, payments: records,
            vendorPayout: VendorPayoutRecord(
                orderId: order.id, vendorId: offer.vendorId, payout: payout,
                subsidyTotalCents: allocation.fundUsedCents,
                solidarityContributedCents: application.summary.contributedCents,
                paidShareCount: records.filter { $0.status == .succeeded }.count, date: now
            ),
            fundUsedCents: allocation.fundUsedCents,
            contributedCents: application.summary.contributedCents
        )
        if closure.fundDebitCents > 0 {
            closure.fundEntry = .init(
                kind: .application, orderId: order.id, amountCents: closure.fundDebitCents,
                basketCount: application.summary.basketsFunded, date: now
            )
        }
        return closure
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
