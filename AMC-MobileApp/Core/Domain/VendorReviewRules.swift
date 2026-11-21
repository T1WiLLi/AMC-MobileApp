// VendorReviewRules.swift
// Logique pure des avis producteurs (T-157) : moyenne, répartition, éligibilité à noter, indicateurs de confiance.
// Testée dans AMC-MobileAppTests/Domain/VendorReviewRulesTests.swift ; mêmes limites que firestore.rules.

import Foundation

nonisolated enum VendorReviewRules {
    /// Note agrégée d'un producteur.
    struct Summary: Hashable, Sendable {
        /// Moyenne arrondie au dixième ; nil sans avis.
        var average: Double?
        var count: Int
        /// Nombre d'avis par nombre d'étoiles (index 0 = 1 étoile … index 4 = 5 étoiles).
        var distribution: [Int]

        static let empty = Summary(average: nil, count: 0, distribution: Array(repeating: 0, count: 5))

        /// Part (0…1) des avis à `stars` étoiles.
        func share(of stars: Int) -> Double {
            guard count > 0, VendorReview.ratingRange.contains(stars) else { return 0 }
            return Double(distribution[stars - 1]) / Double(count)
        }
    }

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
        let valid = reviews.filter { VendorReview.ratingRange.contains($0.rating) }
        guard !valid.isEmpty else { return .empty }
        var distribution = Array(repeating: 0, count: 5)
        for review in valid { distribution[review.rating - 1] += 1 }
        let mean = Double(valid.reduce(0) { $0 + $1.rating }) / Double(valid.count)
        return Summary(average: (mean * 10).rounded() / 10, count: valid.count, distribution: distribution)
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

    /// Commentaire nettoyé : espaces retirés, vide → nil, coupé à la limite.
    static func normalizedComment(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(VendorReview.maxCommentLength))
    }

    /// « Amina Benali » → « Amina B. » ; vide → « Une famille ».
    static func authorName(fromDisplayName name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        guard let first = parts.first else { return String(localized: "Une famille") }
        let short = parts.count > 1 ? "\(first) \(parts[parts.count - 1].prefix(1))." : first
        return String(short.prefix(VendorReview.maxAuthorNameLength))
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
