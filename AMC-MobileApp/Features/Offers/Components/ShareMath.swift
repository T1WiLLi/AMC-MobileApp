import Foundation

/// Calcul pur de la part d'une famille sur un lot (fiche F3) : total, économie, bornes, pas et libellés.
///
/// Une part (`Offer.shareUnit`, ex. « kg » ou « sac de 10 kg ») coûte `PriceTier.priceCents` au palier courant ;
/// le prix d'épicerie de référence (`Product.referenceGroceryPriceCents`) est donné pour la même unité.
nonisolated enum ShareMath {
    /// Résumé chiffré d'une part.
    struct Quote: Equatable, Sendable {
        var shares: Int
        /// Total à payer : parts × prix du palier courant.
        var totalCents: Cents
        /// Ce que la même quantité coûterait en épicerie.
        var groceryCents: Cents
        /// Économie vs épicerie, jamais négative.
        var savingsCents: Cents
    }

    /// Total à payer : parts × prix du palier courant (0 si aucune part).
    static func total(shares: Int, tier: PriceTier) -> Cents {
        max(0, shares) * tier.priceCents
    }

    /// Économie vs épicerie pour `shares` parts ; 0 si le palier n'est pas moins cher que l'épicerie.
    static func savings(shares: Int, tier: PriceTier, referencePriceCents: Cents) -> Cents {
        max(0, max(0, shares) * (referencePriceCents - tier.priceCents))
    }

    static func quote(shares: Int, tier: PriceTier, referencePriceCents: Cents) -> Quote {
        let shares = max(0, shares)
        return Quote(
            shares: shares,
            totalCents: total(shares: shares, tier: tier),
            groceryCents: shares * referencePriceCents,
            savingsCents: savings(shares: shares, tier: tier, referencePriceCents: referencePriceCents)
        )
    }

    static func quote(shares: Int, tier: PriceTier, product: Product) -> Quote {
        quote(shares: shares, tier: tier, referencePriceCents: product.referenceGroceryPriceCents)
    }

    // MARK: Bornes et pas

    /// Bornes de la part d'une famille : au moins `minimum` (1 par défaut), au plus `maximum` (par défaut les parts du lot).
    static func bounds(for offer: Offer, minimum: Int = 1, maximum: Int? = nil) -> ClosedRange<Int> {
        let lower = max(1, minimum)
        let upper = max(lower, min(maximum ?? offer.totalShares, offer.totalShares > 0 ? offer.totalShares : lower))
        return lower...upper
    }

    /// Ramène une quantité dans les bornes.
    static func clamp(_ quantity: Int, to range: ClosedRange<Int>) -> Int {
        min(max(quantity, range.lowerBound), range.upperBound)
    }

    /// Pas proposés dans le Picker segmenté : 5 / 10 / 20 pour une part d'un kilo (maquette F3),
    /// 1 / 2 / 3 pour une part plus grosse (sac, caisse…). Gardés seulement s'ils sont dans les bornes.
    static func defaultSteps(for unit: String, in range: ClosedRange<Int>) -> [Int] {
        let candidates: [Int]
        if let weight = unitWeightKg(unit), weight <= 1 {
            candidates = [5, 10, 20]
        } else {
            candidates = [1, 2, 3]
        }
        let kept = candidates.filter(range.contains)
        return kept.isEmpty ? [range.lowerBound] : kept
    }

    // MARK: Libellés

    /// Poids d'une part en kg si l'unité en parle : « kg » → 1, « 10 kg » → 10, « sac de 10 kg » → 10, « 2,5 kg » → 2,5.
    static func unitWeightKg(_ unit: String) -> Double? {
        let text = unit.trimmingCharacters(in: .whitespaces).lowercased()
        guard text.hasSuffix("kg") else { return nil }
        let head = text.dropLast(2).trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty else { return 1 }
        guard let number = head.split(separator: " ").last,
              let value = Double(number.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }

    /// Quantité lisible : « 10 kg » (poids total si l'unité est en kg), sinon « 3 douzaines ».
    static func quantityLabel(shares: Int, unit: String) -> String {
        if let weight = unitWeightKg(unit) {
            let total = Double(shares) * weight
            let number = total.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.formattingLocale))
            return "\(number) kg"
        }
        return "\(shares) \(shares > 1 ? pluralized(unit) : unit)"
    }

    /// Met le premier mot au pluriel : « caisse de 5 kg » → « caisses de 5 kg », « douzaine » → « douzaines ».
    static func pluralized(_ unit: String) -> String {
        var words = unit.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let first = words.first, !first.isEmpty else { return unit }
        if let last = first.last, !"sxz".contains(last) {
            words[0] = first + "s"
        }
        return words.joined(separator: " ")
    }
}
