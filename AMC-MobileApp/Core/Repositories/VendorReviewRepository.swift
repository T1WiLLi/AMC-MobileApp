// VendorReviewRepository.swift
// Avis des familles sur les producteurs et ventes passées (T-157).
// Deux implémentations : `FakeVendorReviewRepository` (ci-dessous) et `FirestoreVendorReviewRepository`.
// Règles métier : `VendorReviewRules` (Core/Domain).

import Foundation

nonisolated protocol VendorReviewRepository: Sendable {
    /// Avis du producteur, les plus récents d'abord.
    func reviews(ofVendor vendorId: String) async throws -> [VendorReview]

    /// Crée ou remplace l'avis du ménage (`VendorReview.documentId`). Lève `.invalidInput` si la note est hors 1…5,
    /// `.permissionDenied` si le ménage n'a pas reçu la commande `groupOrderId` de ce producteur.
    @discardableResult
    func saveReview(_ review: VendorReview) async throws -> VendorReview

    /// Commandes livrées du producteur, de la plus récente à la plus ancienne. `buyerHouseholdIds` n'est rempli
    /// que pour les commandes des groupes de `viewerHouseholdId` (les autres parts ne sont pas lisibles).
    func sales(ofVendor vendorId: String, viewerHouseholdId: String?) async throws -> [VendorSale]
}

/// Avis et ventes en mémoire (previews, tests, mode fake).
actor FakeVendorReviewRepository: VendorReviewRepository {
    private let behavior: FakeBehavior
    private(set) var reviews: [String: VendorReview]
    private let sales: [VendorSale]

    init(behavior: FakeBehavior = .instant, reviews: [VendorReview] = [], sales: [VendorSale] = []) {
        self.behavior = behavior
        self.reviews = Dictionary(reviews.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.sales = sales
    }

    func reviews(ofVendor vendorId: String) async throws -> [VendorReview] {
        try await behavior.simulate()
        return reviews.values.filter { $0.vendorId == vendorId }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveReview(_ review: VendorReview) async throws -> VendorReview {
        try await behavior.simulate()
        guard VendorReview.ratingRange.contains(review.rating) else {
            throw AppError.invalidInput(String(localized: "Choisis une note de 1 à 5 étoiles."))
        }
        guard review.id == VendorReview.documentId(vendorId: review.vendorId, householdId: review.householdId),
              sales.contains(where: {
                  $0.id == review.groupOrderId && $0.vendorId == review.vendorId
                      && $0.buyerHouseholdIds.contains(review.householdId)
              })
        else { throw AppError.permissionDenied }
        if let existing = reviews[review.id], existing.groupOrderId != review.groupOrderId
            || existing.createdAt != review.createdAt {
            throw AppError.permissionDenied
        }
        reviews[review.id] = review
        return review
    }

    func sales(ofVendor vendorId: String, viewerHouseholdId: String?) async throws -> [VendorSale] {
        try await behavior.simulate()
        return sales.filter { $0.vendorId == vendorId }.sorted { $0.date > $1.date }
    }
}
