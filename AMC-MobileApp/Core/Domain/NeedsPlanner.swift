// NeedsPlanner.swift
// E12 Planificateur (RQ-099, RQ-100) : plan mensuel de besoins du ménage et suggestions de lots
// classées selon la couverture des besoins, l'économie vs l'épicerie, le budget restant et la date limite.
// Swift pur : aucune dépendance à Firebase ni à l'UI. Réutilise `OfferPricing` (prix au palier)
// et `SavingsCalculator` / `ShareMeasure` (contenu d'une part, totaux d'économie).

import Foundation

// MARK: - Plan mensuel (RQ-099)

/// Unité d'un besoin.
nonisolated enum NeedUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case kilograms
    case liters
    case units

    /// « kg », « L », « unités ».
    var symbol: String {
        switch self {
        case .kilograms: "kg"
        case .liters: "L"
        case .units: "unités"
        }
    }

    /// Libellé du sélecteur.
    var title: String {
        switch self {
        case .kilograms: "Kilos"
        case .liters: "Litres"
        case .units: "Unités"
        }
    }

    /// Quantité contenue dans une part, dans cette unité ; nil si la part ne se compte pas ainsi
    /// (une caisse « 12 unités » ne se mesure pas en kilos).
    func amount(in measure: ShareMeasure) -> Double? {
        switch (self, measure) {
        case (.kilograms, .mass(let kilograms)): kilograms
        // 1 L ≈ 1 kg : même règle que `ShareMeasure.kilograms`.
        case (.kilograms, .volume(let liters)): liters
        case (.liters, .volume(let liters)): liters
        case (.liters, .mass(let kilograms)): kilograms
        case (.units, .count(let units)): Double(units)
        default: nil
        }
    }
}

/// Un besoin du mois : une catégorie de RQ-039 (« 10 kg de céréales ») ou un produit précis.
nonisolated struct NeedItem: Identifiable, Codable, Sendable, Hashable {
    enum Target: Codable, Sendable, Hashable {
        case category(Product.Category)
        /// Produit précis ; le nom et la catégorie sont gardés pour l'affichage hors ligne.
        case product(id: String, name: String, category: Product.Category)

        var category: Product.Category {
            switch self {
            case .category(let category): category
            case .product(_, _, let category): category
            }
        }

        /// « Céréales » ou « Riz basmati ».
        var title: String {
            switch self {
            case .category(let category): category.title
            case .product(_, let name, _): name
            }
        }

        /// Le produit répond à ce besoin.
        func matches(_ product: Product) -> Bool {
            switch self {
            case .category(let category): product.category == category
            case .product(let id, _, _): product.id == id
            }
        }

        /// Un besoin sur un produit précis passe avant un besoin sur sa catégorie.
        var isSpecific: Bool {
            if case .product = self { true } else { false }
        }
    }

    var id: UUID
    var target: Target
    /// Quantité voulue pour le mois (> 0).
    var quantity: Double
    var unit: NeedUnit

    init(id: UUID = UUID(), target: Target, quantity: Double, unit: NeedUnit) {
        self.id = id
        self.target = target
        self.quantity = quantity
        self.unit = unit
    }
}

/// Plan d'un mois : les besoins du ménage et le budget, en cents.
nonisolated struct MonthlyNeedsPlan: Codable, Sendable, Hashable {
    var needs: [NeedItem]
    var budgetCents: Cents

    init(needs: [NeedItem] = [], budgetCents: Cents = 0) {
        self.needs = needs
        self.budgetCents = budgetCents
    }

    /// Plan de départ d'un ménage qui n'a encore rien saisi : 150 $, légumes, céréales, légumineuses.
    static let starter = MonthlyNeedsPlan(
        needs: [
            NeedItem(target: .category(.produce), quantity: 20, unit: .kilograms),
            NeedItem(target: .category(.grains), quantity: 10, unit: .kilograms),
            NeedItem(target: .category(.legumes), quantity: 4, unit: .kilograms),
        ],
        budgetCents: 15_000
    )
}

// MARK: - Suggestions (RQ-100)

/// Un lot proposé pour un besoin, avec le nombre de parts à prendre.
nonisolated struct LotSuggestion: Identifiable, Sendable, Hashable {
    var offer: Offer
    var product: Product
    /// Besoin couvert.
    var needId: UUID
    /// Parts proposées (0 si le lot dépasse le budget restant).
    var shares: Int
    /// Parts qu'il faudrait pour couvrir le reste du besoin, sans limite de budget.
    var sharesToCoverNeed: Int
    /// Prix d'une part au palier atteint avec les parts proposées.
    var unitPriceCents: Cents
    /// Économie d'une part vs l'épicerie, en %.
    var savingsPercent: Int
    var costCents: Cents
    var savingsCents: Cents
    /// Quantité du besoin couverte par les parts proposées (dans l'unité du besoin), nil si la part
    /// ne se mesure pas dans cette unité.
    var coveredQuantity: Double?
    /// Score de classement entre 0 et 1 (voir `NeedsPlanner.Weights`).
    var score: Double

    var id: String { offer.id }
    /// Le lot tient dans le budget restant.
    var fitsBudget: Bool { shares > 0 }
}

/// Résultat du planificateur : suggestions classées et totaux.
nonisolated struct NeedsPlanResult: Sendable, Hashable {
    /// Du meilleur score au moins bon ; les lots hors budget sont à la fin.
    var suggestions: [LotSuggestion]
    var budgetCents: Cents
    /// Σ coût des parts proposées.
    var usedBudgetCents: Cents
    /// Économie totale vs l'épicerie (`SavingsCalculator.summary`).
    var savings: SavingsSummary
    /// Part couverte de chaque besoin, entre 0 et 1.
    var coverage: [UUID: Double]
    /// Besoins pour lesquels aucun lot actif n'existe.
    var unmatchedNeedIds: [UUID]

    static let empty = NeedsPlanResult(
        suggestions: [], budgetCents: 0, usedBudgetCents: 0, savings: .empty, coverage: [:], unmatchedNeedIds: []
    )

    var remainingBudgetCents: Cents { max(0, budgetCents - usedBudgetCents) }
    var savingsCents: Cents { savings.savingsCents }
    /// Part du budget utilisée, entre 0 et 1.
    var budgetUsage: Double { budgetCents > 0 ? min(1, Double(usedBudgetCents) / Double(budgetCents)) : 0 }
    /// Couverture moyenne des besoins, entre 0 et 1.
    var overallCoverage: Double {
        coverage.isEmpty ? 0 : coverage.values.reduce(0, +) / Double(coverage.count)
    }
}

nonisolated enum NeedsPlanner {
    /// Poids du score (somme = 1).
    enum Weights {
        /// Le lot couvre-t-il le besoin ?
        static let coverage = 0.45
        /// Économie vs l'épicerie (50 % d'économie ou plus = plein score).
        static let savings = 0.30
        /// Le lot tient-il dans le budget ?
        static let budget = 0.15
        /// Date limite proche : à décider maintenant (14 jours ou plus = 0).
        static let urgency = 0.10
    }

    /// Classe les lots actifs pour le plan et répartit le budget, du meilleur score au moins bon.
    ///
    /// - Parameters:
    ///   - offers: lots candidats ; seuls les lots `.active` dont la date limite n'est pas passée sont gardés.
    ///   - products: produits des lots (les lots sans produit connu sont ignorés).
    ///   - plan: besoins du mois.
    ///   - budget: budget disponible ; par défaut `plan.budgetCents`.
    ///   - committedShares: parts déjà engagées par le groupe, par id de lot (pour le palier).
    ///   - now: injecté pour des tests déterministes.
    ///
    /// Un lot répond au premier besoin qui lui correspond (un produit précis avant une catégorie).
    /// La répartition est gourmande : dans l'ordre du score, chaque lot prend les parts qui couvrent
    /// le reste de son besoin, dans la limite du budget restant et des parts encore disponibles.
    static func suggestions(
        offers: [Offer],
        products: [Product],
        plan: MonthlyNeedsPlan,
        budget: Cents? = nil,
        committedShares: [String: Int] = [:],
        now: Date = .now
    ) -> NeedsPlanResult {
        let budget = max(0, budget ?? plan.budgetCents)
        let productsById = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let needs = plan.needs.filter { $0.quantity > 0 }
        let orderedNeeds = needs.filter(\.target.isSpecific) + needs.filter { !$0.target.isSpecific }

        // 1. Candidats : un lot actif, un produit connu, un besoin qui lui correspond.
        struct Candidate {
            var offer: Offer
            var product: Product
            var need: NeedItem
            var perShare: Double?
            var committed: Int
            var score: Double
        }
        var candidates: [Candidate] = []
        for offer in offers where offer.status == .active && offer.deadline > now {
            guard let product = productsById[offer.productId],
                  let need = orderedNeeds.first(where: { $0.target.matches(product) }) else { continue }
            let committed = committedShares[offer.id] ?? 0
            let perShare = need.unit.amount(in: ShareMeasure.parse(offer.shareUnit))
            let wanted = sharesFor(quantity: need.quantity, perShare: perShare)
            let pricing = OfferPricing(offer: offer, product: product, committedShares: committed + wanted)
            let score = score(
                perShare: perShare, need: need, savingsPercent: pricing.savingsPercent,
                costCents: pricing.totalCents(forShares: wanted), budget: budget,
                deadline: offer.deadline, now: now
            )
            candidates.append(Candidate(offer: offer, product: product, need: need, perShare: perShare,
                                        committed: committed, score: score))
        }
        candidates.sort {
            ($0.score, $1.offer.deadline, $1.offer.id) > ($1.score, $0.offer.deadline, $0.offer.id)
        }

        // 2. Répartition du budget dans l'ordre du score.
        var remainingNeed = Dictionary(needs.map { ($0.id, $0.quantity) }, uniquingKeysWith: { first, _ in first })
        var remainingBudget = budget
        var suggestions: [LotSuggestion] = []
        var entries: [SavingsEntry] = []
        for candidate in candidates {
            let left = remainingNeed[candidate.need.id] ?? 0
            // Besoin déjà couvert par un meilleur lot : on n'en propose pas un second.
            guard left > 1e-9 else { continue }
            let toCover = sharesFor(quantity: left, perShare: candidate.perShare)
            let available = max(0, candidate.offer.totalShares - candidate.committed)
            var shares = min(toCover, available)
            // Le prix baisse quand on ajoute des parts : on cherche le plus grand nombre de parts abordable.
            let base = OfferPricing(offer: candidate.offer, product: candidate.product, committedShares: candidate.committed)
            while shares > 0, base.with(committedShares: candidate.committed + shares).totalCents(forShares: shares) > remainingBudget {
                shares -= 1
            }
            let priced = base.with(committedShares: candidate.committed + max(shares, 1))
            let cost = priced.totalCents(forShares: shares)
            remainingBudget -= cost
            let covered = candidate.perShare.map { min(left, $0 * Double(shares)) }
            if shares > 0 {
                // Part qui ne se mesure pas dans l'unité du besoin : on la compte comme couvrant le besoin.
                remainingNeed[candidate.need.id] = left - (covered ?? left)
                entries.append(SavingsEntry(
                    householdId: "plan", groupOrderId: candidate.offer.id, groupId: "plan", neighborhood: "",
                    productId: candidate.product.id, category: candidate.product.category, date: now,
                    quantity: shares, referenceUnitPriceCents: candidate.product.referenceGroceryPriceCents,
                    finalUnitPriceCents: priced.currentPriceCents,
                    measure: ShareMeasure.parse(candidate.offer.shareUnit)
                ))
            }
            suggestions.append(LotSuggestion(
                offer: candidate.offer, product: candidate.product, needId: candidate.need.id,
                shares: shares, sharesToCoverNeed: toCover, unitPriceCents: priced.currentPriceCents,
                savingsPercent: priced.savingsPercent, costCents: cost,
                savingsCents: priced.savingsCents(forShares: shares), coveredQuantity: covered,
                score: candidate.score
            ))
        }
        // Les lots hors budget restent visibles, mais après ceux qu'on peut prendre.
        suggestions = suggestions.filter(\.fitsBudget) + suggestions.filter { !$0.fitsBudget }

        let coverage = Dictionary(needs.map { need in
            (need.id, min(1, max(0, 1 - (remainingNeed[need.id] ?? 0) / need.quantity)))
        }, uniquingKeysWith: { first, _ in first })
        let matched = Set(candidates.map(\.need.id))
        return NeedsPlanResult(
            suggestions: suggestions,
            budgetCents: budget,
            usedBudgetCents: budget - remainingBudget,
            savings: SavingsCalculator.summary(of: entries),
            coverage: coverage,
            unmatchedNeedIds: needs.map(\.id).filter { !matched.contains($0) }
        )
    }

    /// Parts pour couvrir `quantity` : ⌈quantité ÷ contenu d'une part⌉, au moins 1 ;
    /// 1 si la part ne se mesure pas dans l'unité du besoin.
    static func sharesFor(quantity: Double, perShare: Double?) -> Int {
        guard let perShare, perShare > 0 else { return 1 }
        return max(1, Int((quantity / perShare - 1e-9).rounded(.up)))
    }

    /// Score entre 0 et 1 : couverture, économie, budget et urgence pondérés par `Weights`.
    static func score(
        perShare: Double?, need: NeedItem, savingsPercent: Int, costCents: Cents, budget: Cents,
        deadline: Date, now: Date
    ) -> Double {
        // Une part qui ne se mesure pas dans l'unité du besoin couvre à moitié (on ne sait pas).
        let coverage = perShare.map { perShare in
            let shares = sharesFor(quantity: need.quantity, perShare: perShare)
            let bought = perShare * Double(shares)
            // Trop acheter pénalise un peu : 10 kg voulus, part de 25 kg → 0,4.
            return bought <= need.quantity ? bought / need.quantity : need.quantity / bought
        } ?? 0.5
        let savings = min(1, Double(savingsPercent) / 50)
        let budgetFit = costCents <= 0 ? 1 : min(1, Double(budget) / Double(costCents))
        let days = deadline.timeIntervalSince(now) / 86_400
        let urgency = min(1, max(0, 1 - days / 14))
        return Weights.coverage * coverage + Weights.savings * savings
            + Weights.budget * budgetFit + Weights.urgency * urgency
    }
}
