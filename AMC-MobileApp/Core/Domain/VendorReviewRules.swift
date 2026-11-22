// VendorReviewRules.swift
// Logique pure des avis producteurs (T-157) : éligibilité à noter, indicateurs de confiance.
// Moyenne, répartition, commentaire et signature : `RatingRules` (commun aux notes de groupes, T-174).
// Testée dans AMC-MobileAppTests/Domain/VendorReviewRulesTests.swift ; mêmes limites que firestore.rules.

import Foundation

nonisolated enum VendorReviewRules {
    /// Note agrégée d'un producteur (type commun à toutes les notes, `RatingRules`).
    typealias Summary = RatingRules.Summary

    /// Indicateurs qui donnent confiance aux familles.
    struct Trust: Hashable, Sendable {
        var deliveredLots: Int
        var familiesServed: Int
        /// Depuis quand le producteur vend sur LeGrenier ; nil si inconnu.
        var since: Date?
        var lastSale: VendorSale?
    }

    /// Moyenne et répartition. Les notes hors 1…5 sont ignorées.
    static func summary(of reviews: [VendorReview]) -> Summary {
        RatingRules.summary(ofRatings: reviews.map(\.rating))
    }

    /// Avis les plus récents d'abord (dernière modification).
    static func recent(_ reviews: [VendorReview], limit: Int = 5) -> [VendorReview] {
        Array(reviews.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    /// Vente la plus récente du producteur où le ménage a acheté : c'est elle qui permet de noter.
    /// nil = le ménage n'a jamais reçu de lot de ce producteur, il ne peut pas noter.
    static func eligibleSale(for householdId: String, vendorId: String, in sales: [VendorSale]) -> VendorSale? {
        guard !householdId.isEmpty else { return nil }
        return sales
            .filter { $0.vendorId == vendorId && $0.buyerHouseholdIds.contains(householdId) }
            .max { $0.date < $1.date }
    }

    static func trust(sales: [VendorSale], memberSince: Date?) -> Trust {
        Trust(
            deliveredLots: sales.count,
            familiesServed: sales.reduce(0) { $0 + $1.households },
            since: memberSince ?? sales.map(\.date).min(),
            lastSale: sales.max { $0.date < $1.date }
        )
    }

    /// Commentaire nettoyé (`RatingRules.normalizedComment`) : vide → nil, coupé à la limite.
    static func normalizedComment(_ text: String) -> String? {
        RatingRules.normalizedComment(text, maxLength: VendorReview.maxCommentLength)
    }

    /// « Amina Benali » → « Amina B. » ; vide → « Une famille ».
    static func authorName(fromDisplayName name: String) -> String {
        RatingRules.authorName(fromDisplayName: name)
    }

    /// Avis prêt à enregistrer (création ou modification de l'avis existant du ménage).
    static func makeReview(
        vendorId: String, householdId: String, authorName: String, rating: Int, comment: String,
        groupOrderId: String, existing: VendorReview?, now: Date
    ) throws -> VendorReview {
        guard VendorReview.ratingRange.contains(rating) else {
            throw AppError.invalidInput(String(localized: "Choisis une note de 1 à 5 étoiles."))
        }
        return VendorReview(
            id: VendorReview.documentId(vendorId: vendorId, householdId: householdId),
            vendorId: vendorId, householdId: householdId, authorName: authorName, rating: rating,
            comment: normalizedComment(comment), groupOrderId: existing?.groupOrderId ?? groupOrderId,
            createdAt: existing?.createdAt ?? now, updatedAt: now
        )
    }
}
