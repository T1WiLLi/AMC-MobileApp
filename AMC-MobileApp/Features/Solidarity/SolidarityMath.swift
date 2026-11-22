import Foundation

/// Résultat de la répartition du fonds de solidarité sur les parts admissibles.
nonisolated struct SolidarityAllocation: Equatable, Sendable {
    /// Montant offert à chaque ménage aidé (`householdId` → cents), jamais négatif, jamais plus que ce qu'il doit.
    var subsidies: [String: Cents]
    /// Ce qui reste dans le fonds après la répartition.
    var remainingCents: Cents

    /// Total offert.
    var totalCents: Cents { subsidies.values.reduce(0, +) }
}

/// Calculs purs du panier suspendu et du fonds de solidarité (E10). Tout est en cents entiers : pas d'erreur d'arrondi.
nonisolated enum SolidarityMath {
    /// Montants proposés dans `SuspendedBasketPicker` : 0, 2, 5 et 10 $.
    static let presetsCents: [Cents] = [0, 200, 500, 1_000]
    /// Plafond d'un panier suspendu par commande : 100 $.
    static let maxSuspendedCents: Cents = 10_000

    // MARK: Saisie libre

    /// Lit un montant tapé par la personne (« 3 », « 3,50 », « 3.5 », « 4 $ ») et le convertit en cents.
    /// Champ vide = 0. Refuse les montants négatifs, non numériques, à plus de 2 décimales ou au-delà du plafond,
    /// avec un message clair (`AppError.invalidInput`).
    static func parseAmount(_ raw: String) -> Result<Cents, AppError> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for removable in ["$", " ", "\u{00A0}", "\u{202F}"] {
            text = text.replacingOccurrences(of: removable, with: "")
        }
        if text.isEmpty { return .success(0) }
        if text.hasPrefix("-") || text.hasPrefix("−") {
            return .failure(.invalidInput(String(localized: "Le montant ne peut pas être négatif.")))
        }

        let parts = text.replacingOccurrences(of: ",", with: ".")
            .split(separator: ".", omittingEmptySubsequences: false)
        let isDigits = { (part: Substring) in part.allSatisfy { $0.isASCII && $0.isNumber } }
        guard parts.count <= 2, parts.allSatisfy(isDigits), parts.contains(where: { !$0.isEmpty }) else {
            return .failure(.invalidInput(String(localized: "Écris un montant en chiffres, par exemple 3,50.")))
        }

        let fraction = parts.count == 2 ? parts[1] : ""
        guard fraction.count <= 2 else {
            return .failure(.invalidInput(String(localized: "Au plus deux chiffres après la virgule.")))
        }
        let tooLarge = AppError.invalidInput(String(localized: "Le maximum est \(maxSuspendedCents / 100)\u{00A0}$ par commande."))
        guard parts[0].count <= 6 else { return .failure(tooLarge) }

        let dollars = Int(parts[0]) ?? 0
        let cents = Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let total = dollars * 100 + cents
        guard total <= maxSuspendedCents else { return .failure(tooLarge) }
        return .success(total)
    }

    /// Montant à retenir pour une saisie libre : le montant lu, ou 0 si la saisie est invalide
    /// (jamais l'ancien montant, sinon un texte invalide partirait avec un montant périmé).
    static func amountOrZero(_ raw: String) -> Cents {
        if case .success(let cents) = parseAmount(raw) { return cents }
        return 0
    }

    // MARK: Fonds du groupe

    /// Solde apporté au fonds par un ensemble de parts : somme des paniers suspendus (les montants négatifs comptent pour 0).
    static func contributions(of shares: [Share]) -> Cents {
        shares.reduce(0) { $0 + max(0, $1.suspendedAmountCents) }
    }

    /// Solde du fonds : apports moins ce qui a déjà été offert, jamais sous 0.
    static func balance(contributedCents: Cents, spentCents: Cents) -> Cents {
        max(0, max(0, contributedCents) - max(0, spentCents))
    }

    /// Nombre de paniers entiers que le solde peut encore offrir (0 si le coût d'un panier est invalide).
    static func basketsCovered(balanceCents: Cents, basketCostCents: Cents) -> Int {
        guard basketCostCents > 0, balanceCents > 0 else { return 0 }
        return balanceCents / basketCostCents
    }

    /// Ce que doit une part au prix unitaire donné, avant aide : jamais négatif.
    static func amountDue(of share: Share, unitPriceCents: Cents) -> Cents {
        max(0, share.finalPriceCents ?? max(0, share.quantity) * max(0, unitPriceCents))
    }

    /// Ce qu'il reste à payer à un ménage : sa part moins l'aide reçue, plus son propre panier suspendu. Jamais négatif.
    static func amountToPay(dueCents: Cents, subsidyCents: Cents, suspendedCents: Cents) -> Cents {
        max(0, max(0, dueCents) - max(0, subsidyCents)) + max(0, suspendedCents)
    }

    // MARK: Répartition

    /// Répartit le fonds à parts égales entre les ménages admissibles, sans jamais dépasser ce que chacun doit.
    /// Ce qu'un ménage ne peut pas absorber est redistribué aux autres ; les cents restants vont, un par un,
    /// aux ménages dans l'ordre de leur identifiant (résultat déterministe). Aucun montant n'est négatif
    /// et le total offert ne dépasse jamais le fonds.
    static func allocate(fundCents: Cents, dues: [String: Cents]) -> SolidarityAllocation {
        var remaining = max(0, fundCents)
        var subsidies = dues.mapValues { _ in Cents(0) }
        var open = dues.keys.sorted().filter { (dues[$0] ?? 0) > 0 }

        while remaining > 0, !open.isEmpty {
            let perHousehold = remaining / open.count
            if perHousehold == 0 {
                // Moins d'un cent par ménage : chacun des premiers reçoit 1 cent (chaque ménage ouvert doit encore ≥ 1 cent).
                for id in open.prefix(remaining) { subsidies[id, default: 0] += 1 }
                remaining = 0
                break
            }
            var stillOpen: [String] = []
            for id in open {
                let need = (dues[id] ?? 0) - (subsidies[id] ?? 0)
                let given = min(perHousehold, need)
                subsidies[id, default: 0] += given
                remaining -= given
                if given < need { stillOpen.append(id) }
            }
            open = stillOpen
        }
        return SolidarityAllocation(subsidies: subsidies, remainingCents: remaining)
    }

    /// Répartit le fonds sur les parts des ménages admissibles et renvoie les parts avec `subsidyCents` à jour.
    /// Les parts non admissibles gardent `subsidyCents = 0`.
    static func applying(
        fundCents: Cents,
        to shares: [Share],
        eligible householdIds: Set<String>,
        unitPriceCents: Cents
    ) -> (shares: [Share], allocation: SolidarityAllocation) {
        var dues: [String: Cents] = [:]
        for share in shares where householdIds.contains(share.householdId) {
            dues[share.householdId, default: 0] += amountDue(of: share, unitPriceCents: unitPriceCents)
        }
        let allocation = allocate(fundCents: fundCents, dues: dues)
        let updated = shares.map { share in
            var copy = share
            copy.subsidyCents = allocation.subsidies[share.householdId] ?? 0
            return copy
        }
        return (updated, allocation)
    }
}
