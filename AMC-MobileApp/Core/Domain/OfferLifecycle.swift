// OfferLifecycle.swift
// Cycle de vie d'un lot côté vendeur (E04 : RQ-036 à RQ-038).
// Modifier, mettre en pause, retirer, dupliquer un lot, et créer le lot « invendus de la semaine ».
// Swift pur, sans Firebase : les dépôts (Firestore ou fake) et les ViewModels vendeur l'appellent.
//
// Pause : `Offer.Status` n'a pas de cas `paused`. Un lot en pause est représenté par `PausedOffer`,
// qui garde le lot d'origine et l'heure de la pause. Le lot à enregistrer (`storedOffer`) a le statut
// `.draft` : il disparaît du catalogue et n'accepte plus de nouvelles parts, mais ses commandes ouvertes
// ne sont pas annulées. À la reprise, le lot redevient `.active` et sa date limite est repoussée
// de la durée de la pause.

import Foundation

nonisolated enum OfferLifecycle {
    /// Lot en pause (RQ-036). Voir l'en-tête du fichier pour la correspondance avec `Offer.Status`.
    struct PausedOffer: Sendable, Equatable {
        /// Le lot tel qu'il était avant la pause (statut `.active`).
        var original: Offer
        var pausedAt: Date

        /// Ce qu'on enregistre pendant la pause : le même lot, en brouillon (caché du catalogue).
        var storedOffer: Offer {
            var offer = original
            offer.status = .draft
            return offer
        }
    }

    /// Résultat d'un retrait (RQ-036).
    struct Withdrawal: Sendable, Equatable {
        /// Le lot, au statut `.cancelled`.
        var offer: Offer
        /// Les commandes groupées de ce lot qui étaient ouvertes, maintenant `.cancelled`.
        var cancelledOrders: [GroupOrder]
    }

    static let defaultRecurrenceInterval: TimeInterval = 7 * 24 * 3600
    static let defaultLeftoversDiscountPercent = 30
    static let defaultLeftoversDuration: TimeInterval = 48 * 3600

    // MARK: Validation

    /// Vérifie qu'un lot est cohérent, avec les mêmes règles que l'éditeur de paliers (TierEditorViewModel) :
    /// au moins une part et un palier, prix strictement décroissants quand le seuil augmente (dans l'ordre de
    /// `sortedTiers`, comme TierEngine), seuils distincts,
    /// seuils entre 1 et le total, prix > 0, minimum pour lancer entre 1 et le total, date limite future.
    static func validate(_ offer: Offer, now: Date = .now) throws(AppError) {
        guard offer.totalShares > 0 else { throw .invalidInput(String(localized: "Le lot doit contenir au moins une part.")) }
        guard !offer.shareUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .invalidInput(String(localized: "Indique ce que contient une part (par exemple « sac de 10 kg »)."))
        }
        guard !offer.tiers.isEmpty else { throw .invalidInput(String(localized: "Ajoute au moins un palier de prix.")) }
        let tiers = offer.sortedTiers
        for (index, tier) in tiers.enumerated() {
            let rank = index + 1
            guard tier.minShares >= 1 else {
                throw .invalidInput(String(localized: "Le seuil du palier \(rank) doit être d'au moins 1 part."))
            }
            guard tier.priceCents > 0 else {
                throw .invalidInput(String(localized: "Le prix du palier \(rank) doit être supérieur à 0 $."))
            }
            guard tier.minShares <= offer.totalShares else {
                throw .invalidInput(
                    String(localized: "Le seuil du palier \(rank) (\(tier.minShares) parts) dépasse le total du lot (\(offer.totalShares) parts).")
                )
            }
            if index > 0 {
                let previous = tiers[index - 1]
                guard tier.minShares > previous.minShares else {
                    throw .invalidInput(
                        String(localized: "Le seuil du palier \(rank) doit être plus grand que celui du palier \(rank - 1) (\(previous.minShares) parts).")
                    )
                }
                guard tier.priceCents < previous.priceCents else {
                    throw .invalidInput(
                        String(localized: "Le prix du palier \(rank) doit être plus bas que celui du palier \(rank - 1) (\(format(previous.priceCents))).")
                    )
                }
            }
        }
        guard offer.minimumSharesToLaunch >= 1, offer.minimumSharesToLaunch <= offer.totalShares else {
            throw .invalidInput(String(localized: "Le minimum pour lancer la commande doit être entre 1 et \(offer.totalShares) parts."))
        }
        guard offer.deadline > now else { throw .invalidInput(String(localized: "La date limite doit être dans le futur.")) }
    }

    // MARK: RQ-036 modifier

    /// Applique une modification au lot. Sans part engagée, tout est permis (tant que le lot reste valide).
    /// Dès qu'il y a des parts engagées : même format de part, total ≥ parts engagées, aucun prix plus cher
    /// pour aucune quantité, minimum pour lancer pas plus haut, date limite seulement repoussée, pas de zone retirée.
    static func edited(
        _ original: Offer, to proposed: Offer, committedShares: Int, now: Date = .now
    ) throws(AppError) -> Offer {
        guard original.status == .draft || original.status == .active else {
            throw .invalidInput(String(localized: "Ce lot est \(label(original.status)) : tu ne peux plus le modifier."))
        }
        guard proposed.id == original.id, proposed.vendorId == original.vendorId,
              proposed.productId == original.productId else {
            throw .invalidInput(String(localized: "Tu ne peux pas changer le produit d'un lot. Crée plutôt un nouveau lot."))
        }
        var result = proposed
        result.status = original.status

        if committedShares > 0 {
            guard proposed.shareUnit == original.shareUnit else {
                throw .invalidInput(String(localized: "Des parts sont déjà engagées : tu ne peux plus changer ce que contient une part."))
            }
            guard proposed.totalShares >= committedShares else {
                throw .invalidInput(
                    String(localized: "Des voisins ont déjà engagé \(committedShares) parts : le lot doit en compter au moins autant.")
                )
            }
            let thresholds = Set([0] + original.tiers.map(\.minShares) + proposed.tiers.map(\.minShares))
            for shares in thresholds.sorted() {
                guard let newPrice = unitPrice(proposed, at: shares),
                      let oldPrice = unitPrice(original, at: shares) else { continue }
                guard newPrice <= oldPrice else {
                    throw .invalidInput(
                        String(localized: "Des parts sont déjà engagées : tu ne peux pas augmenter un prix (\(format(oldPrice)) à partir de \(max(shares, 1)) parts).")
                    )
                }
            }
            guard proposed.minimumSharesToLaunch <= original.minimumSharesToLaunch else {
                throw .invalidInput(String(localized: "Des parts sont déjà engagées : tu ne peux pas monter le minimum pour lancer la commande."))
            }
            guard proposed.deadline >= original.deadline else {
                throw .invalidInput(String(localized: "Des parts sont déjà engagées : tu peux seulement repousser la date limite."))
            }
            guard Set(original.zones).isSubset(of: proposed.zones) else {
                throw .invalidInput(String(localized: "Des parts sont déjà engagées : tu ne peux pas retirer une zone de livraison."))
            }
        }
        try validate(result, now: now)
        return result
    }

    // MARK: RQ-036 pause et reprise

    static func pause(_ offer: Offer, now: Date = .now) throws(AppError) -> PausedOffer {
        guard offer.status == .active else {
            throw .invalidInput(String(localized: "Seul un lot publié peut être mis en pause."))
        }
        guard offer.deadline > now else {
            throw .invalidInput(String(localized: "La date limite de ce lot est passée : tu ne peux plus le mettre en pause."))
        }
        return PausedOffer(original: offer, pausedAt: now)
    }

    /// Republie le lot. La date limite est repoussée de la durée de la pause : le temps en pause ne compte pas.
    static func resume(_ paused: PausedOffer, now: Date = .now) throws(AppError) -> Offer {
        guard now >= paused.pausedAt else {
            throw .invalidInput(String(localized: "La reprise ne peut pas précéder la pause."))
        }
        var offer = paused.original
        offer.status = .active
        offer.deadline = offer.deadline.addingTimeInterval(now.timeIntervalSince(paused.pausedAt))
        try validate(offer, now: now)
        return offer
    }

    // MARK: RQ-036 retrait

    /// Retire le lot : il passe à `.cancelled` et ses commandes groupées encore ouvertes sont annulées.
    /// Les commandes d'autres lots ou déjà fermées sont ignorées.
    static func withdraw(_ offer: Offer, orders: [GroupOrder]) throws(AppError) -> Withdrawal {
        guard offer.status == .draft || offer.status == .active else {
            throw .invalidInput(String(localized: "Ce lot est \(label(offer.status)) : tu ne peux plus le retirer."))
        }
        var offer = offer
        offer.status = .cancelled
        let cancelled = orders
            .filter { $0.offerId == offer.id && TierEngine.isOpen($0) }
            .map { order in
                var order = order
                order.status = .cancelled
                return order
            }
        return Withdrawal(offer: offer, cancelledOrders: cancelled)
    }

    // MARK: RQ-037 dupliquer

    /// Recrée le lot pour la semaine suivante : nouvel identifiant, mêmes produit, paliers et zones,
    /// date limite à `now + interval`, aucune commande ni part reprise.
    static func duplicate(
        _ offer: Offer,
        status: Offer.Status = .draft,
        interval: TimeInterval = defaultRecurrenceInterval,
        now: Date = .now,
        makeId: () -> String
    ) throws(AppError) -> Offer {
        guard status == .draft || status == .active else {
            throw .invalidInput(String(localized: "Un lot dupliqué est soit un brouillon, soit publié."))
        }
        guard interval > 0 else { throw .invalidInput(String(localized: "La date limite doit être dans le futur.")) }
        var copy = offer
        copy.id = makeId()
        copy.status = status
        copy.deadline = now.addingTimeInterval(interval)
        guard copy.id != offer.id, !copy.id.isEmpty else {
            throw .invalidInput(String(localized: "Le lot dupliqué doit avoir un nouvel identifiant."))
        }
        try validate(copy, now: now)
        return copy
    }

    // MARK: RQ-038 invendus de la semaine

    /// Construit le lot « invendus de la semaine » avec les parts restantes
    /// (par exemple `ShareAllocator.Allocation.unallocatedShares`).
    /// Prix réduits de `discountPercent` % (arrondis au cent, toujours ≥ 1 ¢ et strictement décroissants),
    /// seuils ramenés au nombre de parts restantes, date limite courte, minimum pour lancer adapté.
    static func leftoversOffer(
        from offer: Offer,
        leftoverShares: Int,
        discountPercent: Int = defaultLeftoversDiscountPercent,
        duration: TimeInterval = defaultLeftoversDuration,
        now: Date = .now,
        makeId: () -> String
    ) throws(AppError) -> Offer {
        guard leftoverShares > 0 else { throw .invalidInput(String(localized: "Il ne reste aucune part à écouler.")) }
        guard leftoverShares <= offer.totalShares else {
            throw .invalidInput(String(localized: "Ce lot ne compte que \(offer.totalShares) parts."))
        }
        guard (0..<100).contains(discountPercent) else {
            throw .invalidInput(String(localized: "Le rabais doit être entre 0 et 99 %."))
        }
        guard duration > 0 else { throw .invalidInput(String(localized: "La date limite doit être dans le futur.")) }

        // Seuils ramenés aux parts restantes ; si plusieurs paliers tombent au même seuil, on garde le meilleur prix.
        var bestPriceByThreshold: [Int: Cents] = [:]
        for tier in offer.sortedTiers {
            let threshold = max(1, min(tier.minShares, leftoverShares))
            let price = discounted(tier.priceCents, percent: discountPercent)
            bestPriceByThreshold[threshold] = min(bestPriceByThreshold[threshold] ?? price, price)
        }
        var tiers: [PriceTier] = []
        for threshold in bestPriceByThreshold.keys.sorted() {
            var price = bestPriceByThreshold[threshold]!
            if let previous = tiers.last {
                // Les arrondis peuvent rendre deux prix égaux : on garde un écart d'au moins 1 ¢,
                // ou on abandonne le palier s'il ne peut plus être moins cher.
                price = min(price, previous.priceCents - 1)
                guard price >= 1 else { continue }
            }
            tiers.append(PriceTier(minShares: threshold, priceCents: price))
        }
        guard let firstTier = tiers.first else { throw .invalidInput(String(localized: "Ajoute au moins un palier de prix.")) }

        var leftovers = offer
        leftovers.id = makeId()
        leftovers.totalShares = leftoverShares
        leftovers.tiers = tiers
        leftovers.minimumSharesToLaunch = min(offer.minimumSharesToLaunch, firstTier.minShares)
        leftovers.deadline = now.addingTimeInterval(duration)
        leftovers.status = .active
        guard leftovers.id != offer.id, !leftovers.id.isEmpty else {
            throw .invalidInput(String(localized: "Le lot d'invendus doit avoir un nouvel identifiant."))
        }
        try validate(leftovers, now: now)
        return leftovers
    }

    /// Prix réduit de `percent` %, arrondi au cent le plus proche, jamais sous 1 ¢.
    static func discounted(_ cents: Cents, percent: Int) -> Cents {
        let scaled = cents * (100 - percent)
        let rounded = (scaled + 50) / 100
        return max(1, rounded)
    }

    // MARK: Aides

    /// Prix d'une part avec `shares` parts engagées : palier atteint, ou premier palier en dessous (prix « si ça part »).
    private static func unitPrice(_ offer: Offer, at shares: Int) -> Cents? {
        let tiers = offer.sortedTiers
        return offer.tierIndex(forCommittedShares: shares).map { tiers[$0].priceCents } ?? tiers.first?.priceCents
    }

    private static func label(_ status: Offer.Status) -> String {
        switch status {
        case .draft: String(localized: "un brouillon")
        case .active: String(localized: "publié")
        case .closed: String(localized: "clôturé")
        case .cancelled: String(localized: "retiré")
        }
    }

    /// « 9,90 $ » : même rendu que `Money.format`, sans en dépendre (isolé au MainActor).
    private static func format(_ cents: Cents) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "CAD").locale(AppLanguage.formattingLocale))
    }
}
