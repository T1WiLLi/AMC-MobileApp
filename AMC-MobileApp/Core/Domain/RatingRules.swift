// RatingRules.swift
// Logique pure commune aux notes 1 à 5 étoiles (producteurs T-157, groupes T-174) : moyenne, répartition,
// agrégats tenus sur un document parent, commentaire nettoyé et signature « Prénom I. ».
// Testée dans AMC-MobileAppTests/Domain/RatingRulesTests.swift ; mêmes limites que firestore.rules.

import Foundation

nonisolated enum RatingRules {
    static let range = 1...5

    /// Note agrégée.
    struct Summary: Hashable, Sendable {
        /// Moyenne arrondie au dixième ; nil sans avis.
        var average: Double?
        var count: Int
        /// Nombre d'avis par nombre d'étoiles (index 0 = 1 étoile … index 4 = 5 étoiles). Tout à 0 quand le résumé
        /// vient d'agrégats (`summary(sum:count:)`), qui ne gardent pas la répartition.
        var distribution: [Int]

        static let empty = Summary(average: nil, count: 0, distribution: Array(repeating: 0, count: 5))

        /// Part (0…1) des avis à `stars` étoiles.
        func share(of stars: Int) -> Double {
            guard count > 0, RatingRules.range.contains(stars) else { return 0 }
            return Double(distribution[stars - 1]) / Double(count)
        }

        /// La répartition est connue (résumé calculé à partir des avis eux-mêmes).
        var hasDistribution: Bool { distribution.reduce(0, +) > 0 }
    }

    /// Moyenne et répartition. Les notes hors 1…5 sont ignorées.
    static func summary(ofRatings ratings: [Int]) -> Summary {
        let valid = ratings.filter { range.contains($0) }
        guard !valid.isEmpty else { return .empty }
        var distribution = Array(repeating: 0, count: 5)
        for rating in valid { distribution[rating - 1] += 1 }
        let mean = Double(valid.reduce(0, +)) / Double(valid.count)
        return Summary(average: rounded(mean), count: valid.count, distribution: distribution)
    }

    /// Résumé tiré des agrégats d'un document (`ratingSum`, `ratingCount`). Agrégats incohérents
    /// (moyenne hors 1…5, compte nul ou négatif) : pas de note plutôt qu'une note fausse.
    static func summary(sum: Int?, count: Int?) -> Summary {
        guard let sum, let count, count > 0 else { return .empty }
        let mean = Double(sum) / Double(count)
        guard mean >= Double(range.lowerBound), mean <= Double(range.upperBound) else { return .empty }
        return Summary(average: rounded(mean), count: count, distribution: Array(repeating: 0, count: 5))
    }

    /// Variation des agrégats quand un avis passe de `previous` (nil = pas encore d'avis) à `new`.
    static func aggregateDelta(previous: Int?, new: Int) -> (sum: Int, count: Int) {
        guard let previous else { return (new, 1) }
        return (new - previous, 0)
    }

    /// Commentaire nettoyé : espaces en trop fusionnés et lignes vides retirées (pas de pavé), vide → nil,
    /// coupé à la limite.
    static func normalizedComment(_ text: String, maxLength: Int) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let maxAuthorNameLength = 60

    /// « Amina Benali » → « Amina B. » ; vide → « Une famille ».
    static func authorName(fromDisplayName name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        guard let first = parts.first else { return String(localized: "Une famille") }
        let short = parts.count > 1 ? "\(first) \(parts[parts.count - 1].prefix(1))." : first
        return String(short.prefix(maxAuthorNameLength))
    }

    private static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

// MARK: - Groupes (T-174)

nonisolated enum GroupRatingRules {
    /// Statuts d'une commande terminée : une part dedans prouve qu'on a fait partie du groupe.
    static let finishedStatuses: Set<GroupOrder.Status> = [.delivered, .closed]

    /// Commandes terminées du groupe à vérifier pour un ancien membre (au plus `limit`).
    static func finishedOrders(_ orders: [GroupOrder], ofGroup groupId: String, limit: Int = 10) -> [GroupOrder] {
        Array(orders.filter { $0.groupId == groupId && finishedStatuses.contains($0.status) }.prefix(limit))
    }

    /// Le ménage peut-il noter ? Avis existant → modifier ; membre → noter ; sinon la première commande terminée
    /// où il avait une part (`ordersWithMyShare`) prouve qu'il en a fait partie.
    static func eligibility(householdId: String, isMember: Bool, existing: GroupRating?,
                            ordersWithMyShare: [String]) -> GroupRatingEligibility {
        guard !householdId.isEmpty else { return .notEligible }
        if existing != nil { return .alreadyRated }
        if isMember { return .member }
        if let orderId = ordersWithMyShare.first { return .formerMember(groupOrderId: orderId) }
        return .notEligible
    }

    /// Avis prêt à enregistrer (création, ou modification de l'avis existant du ménage).
    static func makeRating(
        groupId: String, householdId: String, authorName: String, rating: Int, comment: String,
        eligibility: GroupRatingEligibility, existing: GroupRating?, now: Date
    ) throws -> GroupRating {
        guard RatingRules.range.contains(rating) else {
            throw AppError.invalidInput(String(localized: "Choisis une note de 1 à 5 étoiles."))
        }
        guard !householdId.isEmpty, eligibility.canRate else { throw AppError.permissionDenied }
        return GroupRating(
            id: householdId, groupId: groupId, householdId: householdId,
            authorName: String(authorName.prefix(RatingRules.maxAuthorNameLength)), rating: rating,
            comment: RatingRules.normalizedComment(comment, maxLength: GroupRating.maxCommentLength),
            groupOrderId: existing?.groupOrderId ?? eligibility.groupOrderId,
            createdAt: existing?.createdAt ?? now, updatedAt: now
        )
    }

    /// Avis à montrer : ceux avec un commentaire d'abord, puis les plus récents (dernière modification).
    static func recent(_ ratings: [GroupRating], limit: Int = 5) -> [GroupRating] {
        Array(ratings.sorted {
            if ($0.comment != nil) != ($1.comment != nil) { return $0.comment != nil }
            return $0.updatedAt > $1.updatedAt
        }.prefix(limit))
    }

    /// Validation commune aux dépôts (mêmes règles que firestore.rules) : note 1…5, id = ménage, commentaire court.
    static func validate(_ rating: GroupRating) throws {
        guard RatingRules.range.contains(rating.rating) else {
            throw AppError.invalidInput(String(localized: "Choisis une note de 1 à 5 étoiles."))
        }
        guard rating.id == rating.householdId, !rating.householdId.isEmpty, !rating.groupId.isEmpty,
              (rating.comment?.count ?? 0) <= GroupRating.maxCommentLength,
              (1...RatingRules.maxAuthorNameLength).contains(rating.authorName.count)
        else { throw AppError.permissionDenied }
    }

    /// Agrégats à jour du groupe après l'enregistrement de `rating` (qui remplace `previous`).
    static func applying(_ rating: GroupRating, replacing previous: GroupRating?, to group: NeighborhoodGroup) -> NeighborhoodGroup {
        var group = group
        let delta = RatingRules.aggregateDelta(previous: previous?.rating, new: rating.rating)
        group.ratingSum = (group.ratingSum ?? 0) + delta.sum
        group.ratingCount = (group.ratingCount ?? 0) + delta.count
        return group
    }
}
