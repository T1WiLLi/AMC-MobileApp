// OrganizationLedger.swift
// Portail Organismes (T-116, RQ-081) — Swift pur, sans Firebase.
// Financer un groupe (don au fonds ou N paniers suspendus), besoin d'un groupe, et impact cumulé de l'organisme.
// Réutilise `SolidarityLedger` : un don d'organisme est une contribution du fonds du groupe, sans commande.
// Paiements simulés : rien ici ne touche à de l'argent réel.

import Foundation

nonisolated enum OrganizationLedger {
    /// Plafond d'un financement simulé : 5 000 $.
    static let maxDonationCents: Cents = 500_000
    /// Plafond de paniers suspendus en une fois.
    static let maxBasketsPerDonation = 200
    /// Montants proposés pour un don au fonds : 25, 50, 100 et 250 $.
    static let amountPresetsCents: [Cents] = [2_500, 5_000, 10_000, 25_000]
    /// Nombres de paniers proposés.
    static let basketPresets: [Int] = [1, 5, 10, 25]
    /// Objectifs mensuels proposés pour un parrainage.
    static let sponsorshipGoalPresets: [Int] = [5, 10, 20, 40]
    /// Rabais moyen de l'achat groupé par rapport à l'épicerie (paliers des lots de démo) : 28 %.
    static let averageGroupDiscount = 0.28

    // MARK: Financer

    /// Ce que va produire un financement : montant, paniers et ménages couverts.
    struct Plan: Sendable, Equatable {
        var kind: OrganizationDonation.Kind
        var amountCents: Cents
        var basketCount: Int
        var householdsReached: Int
    }

    /// Valide la demande et calcule le montant, les paniers entiers et les ménages couverts pour ce groupe.
    /// Lève `.invalidInput` si le montant ou le nombre de paniers est nul, négatif ou trop grand.
    static func plan(_ request: DonationRequest, for profile: GroupSolidarityProfile) throws -> Plan {
        let price = profile.basketPriceCents
        switch request {
        case .fund(let amountCents):
            guard amountCents > 0 else { throw AppError.invalidInput(String(localized: "Choisis un montant plus grand que 0 $.")) }
            guard amountCents <= maxDonationCents else {
                throw AppError.invalidInput(String(localized: "Un financement simulé est limité à 5 000 $ à la fois."))
            }
            let baskets = SolidarityLedger.baskets(in: amountCents, unitPriceCents: price)
            return Plan(
                kind: .fund, amountCents: amountCents, basketCount: baskets,
                householdsReached: reached(baskets: baskets, in: profile)
            )
        case .suspendedBaskets(let count):
            guard count > 0 else { throw AppError.invalidInput(String(localized: "Choisis au moins 1 panier.")) }
            guard count <= maxBasketsPerDonation else {
                throw AppError.invalidInput(String(localized: "Tu peux financer jusqu'à \(maxBasketsPerDonation) paniers à la fois."))
            }
            guard price > 0 else { throw AppError.invalidInput(String(localized: "Ce groupe n'a pas encore de prix de panier.")) }
            let amount = count * price
            guard amount <= maxDonationCents else {
                throw AppError.invalidInput(String(localized: "Un financement simulé est limité à 5 000 $ à la fois."))
            }
            return Plan(
                kind: .suspendedBaskets, amountCents: amount, basketCount: count,
                householdsReached: reached(baskets: count, in: profile)
            )
        }
    }

    /// Applique le financement : nouvelle ligne de contribution dans le fonds et trace du don pour l'organisme.
    static func record(
        _ request: DonationRequest,
        to profile: GroupSolidarityProfile,
        organizationId: String,
        donationId: String,
        date: Date = .now
    ) throws -> (donation: OrganizationDonation, fund: SolidarityFund) {
        let plan = try plan(request, for: profile)
        let fund = try SolidarityLedger.donating(plan.amountCents, to: profile.fund, date: date)
        let donation = OrganizationDonation(
            id: donationId, organizationId: organizationId, groupId: profile.groupId, groupName: profile.groupName,
            kind: plan.kind, amountCents: plan.amountCents, basketCount: plan.basketCount,
            householdsReached: plan.householdsReached, date: date
        )
        return (donation, fund)
    }

    /// Ménages subventionnés couverts : un panier par ménage, au plus le nombre de ménages qui manquent encore.
    private static func reached(baskets: Int, in profile: GroupSolidarityProfile) -> Int {
        min(max(0, baskets), profile.basketsMissing)
    }

    // MARK: Besoin d'un groupe

    /// Indicateur de besoin : part des ménages subventionnés que le fonds couvre déjà.
    enum NeedLevel: Int, Sendable, Comparable, CaseIterable {
        case covered = 0
        case moderate = 1
        case urgent = 2

        static func < (lhs: NeedLevel, rhs: NeedLevel) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .covered: String(localized: "Couvert")
            case .moderate: String(localized: "Besoin modéré")
            case .urgent: String(localized: "Besoin urgent")
            }
        }

        var systemImage: String {
            switch self {
            case .covered: "checkmark.seal.fill"
            case .moderate: "exclamationmark.circle.fill"
            case .urgent: "exclamationmark.triangle.fill"
            }
        }
    }

    /// Moins de la moitié des ménages subventionnés couverts : urgent ; moins de tous : modéré ; sinon couvert.
    static func needLevel(for profile: GroupSolidarityProfile) -> NeedLevel {
        guard profile.subsidizedHouseholds > 0 else { return .covered }
        let coverage = Double(profile.basketsFundable) / Double(profile.subsidizedHouseholds)
        if coverage < 0.5 { return .urgent }
        if coverage < 1 { return .moderate }
        return .covered
    }

    /// Couverture de 0 à 1 (1 si aucun ménage subventionné).
    static func coverage(of profile: GroupSolidarityProfile) -> Double {
        guard profile.subsidizedHouseholds > 0 else { return 1 }
        return min(1, Double(profile.basketsFundable) / Double(profile.subsidizedHouseholds))
    }

    /// Groupes à financer en premier : besoin décroissant, puis paniers manquants, puis distance, puis nom.
    static func prioritized(
        _ profiles: [GroupSolidarityProfile],
        from originGeohash: String? = nil
    ) -> [GroupSolidarityProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.needLevel != rhs.needLevel { return lhs.needLevel > rhs.needLevel }
            if lhs.basketsMissing != rhs.basketsMissing { return lhs.basketsMissing > rhs.basketsMissing }
            if let originGeohash {
                let left = distanceMeters(from: originGeohash, to: lhs) ?? .infinity
                let right = distanceMeters(from: originGeohash, to: rhs) ?? .infinity
                if left != right { return left < right }
            }
            return lhs.groupName.localizedStandardCompare(rhs.groupName) == .orderedAscending
        }
    }

    /// Distance entre le siège de l'organisme et le centre du groupe ; nil si un geohash est invalide.
    static func distanceMeters(from originGeohash: String, to profile: GroupSolidarityProfile) -> Double? {
        Geohash.distanceMeters(from: originGeohash, to: profile.centerGeohash)
    }

    // MARK: Impact

    /// Impact cumulé d'un organisme (onglets Tableau et Impact).
    struct ImpactSummary: Sendable, Equatable {
        struct Month: Sendable, Equatable, Identifiable {
            /// Premier jour du mois.
            var start: Date
            var amountCents: Cents
            var baskets: Int
            var id: Date { start }
        }

        struct GroupShare: Sendable, Equatable, Identifiable {
            var groupId: String
            var groupName: String
            var amountCents: Cents
            var baskets: Int
            var id: String { groupId }
        }

        var totalGivenCents: Cents
        var basketsFunded: Int
        var familiesHelped: Int
        var groupsSponsored: Int
        /// Groupes différents financés au moins une fois.
        var groupsReached: Int
        /// Ce que les paniers financés auraient coûté à l'épicerie : l'argent que les familles n'ont pas eu à dépenser.
        var groceryValueCents: Cents
        /// Derniers mois, du plus ancien au plus récent (mois sans don inclus, à 0).
        var months: [Month]
        /// Répartition par groupe, montant décroissant.
        var byGroup: [GroupShare]

        static let empty = ImpactSummary(
            totalGivenCents: 0, basketsFunded: 0, familiesHelped: 0, groupsSponsored: 0, groupsReached: 0,
            groceryValueCents: 0, months: [], byGroup: []
        )
    }

    /// Valeur en épicerie d'un montant dépensé en achat groupé (rabais moyen `averageGroupDiscount`).
    static func groceryValue(ofGroupSpend cents: Cents) -> Cents {
        guard cents > 0 else { return 0 }
        return Int((Double(cents) / (1 - averageGroupDiscount)).rounded())
    }

    static func summarize(
        donations: [OrganizationDonation],
        sponsorships: [Sponsorship],
        monthCount: Int = 6,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ImpactSummary {
        let total = donations.reduce(0) { $0 + $1.amountCents }
        let baskets = donations.reduce(0) { $0 + $1.basketCount }
        let families = donations.reduce(0) { $0 + $1.householdsReached }

        var months: [ImpactSummary.Month] = []
        if monthCount > 0, let currentMonth = calendar.dateInterval(of: .month, for: now)?.start {
            for offset in stride(from: monthCount - 1, through: 0, by: -1) {
                guard let start = calendar.date(byAdding: .month, value: -offset, to: currentMonth),
                      let interval = calendar.dateInterval(of: .month, for: start) else { continue }
                let inMonth = donations.filter { interval.contains($0.date) }
                months.append(.init(
                    start: interval.start,
                    amountCents: inMonth.reduce(0) { $0 + $1.amountCents },
                    baskets: inMonth.reduce(0) { $0 + $1.basketCount }
                ))
            }
        }

        var byGroup: [String: ImpactSummary.GroupShare] = [:]
        for donation in donations {
            var share = byGroup[donation.groupId]
                ?? .init(groupId: donation.groupId, groupName: donation.groupName, amountCents: 0, baskets: 0)
            share.amountCents += donation.amountCents
            share.baskets += donation.basketCount
            byGroup[donation.groupId] = share
        }

        return ImpactSummary(
            totalGivenCents: total,
            basketsFunded: baskets,
            familiesHelped: families,
            groupsSponsored: sponsorships.count,
            groupsReached: byGroup.count,
            groceryValueCents: groceryValue(ofGroupSpend: total),
            months: months,
            byGroup: byGroup.values.sorted {
                $0.amountCents != $1.amountCents ? $0.amountCents > $1.amountCents : $0.groupName < $1.groupName
            }
        )
    }
}
