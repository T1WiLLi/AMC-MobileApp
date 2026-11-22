// ShareAllocator.swift
// Répartition d'une commande groupée confirmée entre les ménages (E06 : RQ-055).
// Prix final de chaque part, fonds de solidarité, arrondis au cent près.
// Le code de cueillette n'est plus posé ici : il dépend d'un jeton secret du ménage (`PickupDesk.pickupCode`).

import Foundation

nonisolated enum ShareAllocator {
    struct Allocation: Sendable, Equatable {
        /// Parts avec `finalPriceCents` et `subsidyCents` remplis, triées par ménage (`qrCode` reste tel quel).
        var shares: [Share]
        /// Montant pris dans le fonds de solidarité (fonds du groupe + paniers suspendus de cette commande).
        var fundUsedCents: Cents
        /// Ce qui reste dans le fonds après la répartition.
        var fundRemainingCents: Cents
        /// Parts du lot que personne n'a prises (le vendeur les garde).
        var unallocatedShares: Int
        /// Total à encaisser auprès des familles : prix finaux − subventions + paniers suspendus,
        /// soit la somme des `PaymentSimulator.amountDue` des parts.
        var totalDueCents: Cents
    }

    /// - Parameters:
    ///   - unitPriceCents: prix figé d'une part, issu de `TierEngine.closureOutcome`.
    ///   - eligibleHouseholdIds: ménages admissibles à la solidarité (statut subventionné, RQ du E10).
    ///   - solidarityFundCents: solde du fonds du groupe avant cette commande.
    static func allocate(
        orderId: String,
        offer: Offer,
        shares: [Share],
        unitPriceCents: Cents,
        eligibleHouseholdIds: Set<String> = [],
        solidarityFundCents: Cents = 0
    ) throws -> Allocation {
        guard unitPriceCents >= 0, solidarityFundCents >= 0 else {
            throw AppError.invalidInput(String(localized: "Montants négatifs."))
        }
        let active = shares.filter { $0.quantity > 0 }.sorted { $0.householdId < $1.householdId }
        let committed = active.reduce(0) { $0 + $1.quantity }
        guard committed <= offer.totalShares else {
            throw AppError.invalidInput(String(localized: "Ce lot ne compte que \(offer.totalShares) parts."))
        }

        // Prix final de chaque part.
        var result = active.map { share in
            var share = share
            share.finalPriceCents = share.quantity * unitPriceCents
            share.subsidyCents = 0
            return share
        }

        // Solidarité : le fonds paie les parts admissibles, en entier s'il suffit, sinon au prorata.
        let contributedCents = active.reduce(0) { $0 + $1.suspendedAmountCents }
        let fund = solidarityFundCents + contributedCents
        let eligibleIndices = result.indices.filter { eligibleHouseholdIds.contains(result[$0].householdId) }
        let eligibleTotal = eligibleIndices.reduce(0) { $0 + (result[$1].finalPriceCents ?? 0) }
        let budget = min(fund, eligibleTotal)
        let subsidies = proportionalSplit(
            budget, weights: eligibleIndices.map { result[$0].finalPriceCents ?? 0 }
        )
        for (index, subsidy) in zip(eligibleIndices, subsidies) {
            result[index].subsidyCents = subsidy
        }

        let totalPrice = result.reduce(0) { $0 + ($1.finalPriceCents ?? 0) }
        return Allocation(
            shares: result,
            fundUsedCents: budget,
            fundRemainingCents: fund - budget,
            unallocatedShares: offer.totalShares - committed,
            // Les familles paient aussi les paniers suspendus qu'elles ont ajoutés (T-093 : ils manquaient).
            totalDueCents: totalPrice - budget + contributedCents
        )
    }

    /// Partage `amount` cents au prorata de `weights`, sans perdre de cent (méthode du plus fort reste).
    /// La somme du résultat vaut toujours `amount` (si au moins un poids est positif) et aucune part ne dépasse son poids.
    static func proportionalSplit(_ amount: Cents, weights: [Cents]) -> [Cents] {
        let total = weights.reduce(0, +)
        guard amount > 0, total > 0 else { return weights.map { _ in 0 } }
        let amount = min(amount, total)
        var parts = weights.map { $0 * amount / total }
        var remainder = amount - parts.reduce(0, +)
        // Les cents restants vont aux plus forts restes ; à égalité, au premier dans l'ordre.
        let order = weights.indices.sorted {
            let left = weights[$0] * amount % total, right = weights[$1] * amount % total
            return left != right ? left > right : $0 < $1
        }
        for index in order where remainder > 0 && parts[index] < weights[index] {
            parts[index] += 1
            remainder -= 1
        }
        return parts
    }

    /// Préfixe de tout code QR de cueillette (`PickupDesk.pickupCode`).
    static let qrCodePrefix = "GRENIER:"
}
