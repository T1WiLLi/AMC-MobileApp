// FirestoreVendorReviewRepository.swift
// Avis des familles (`vendorReviews/{vendorId}_{householdId}`) et ventes livrées d'un producteur (T-157).
// Ventes : lots du vendeur (`offers`) → commandes groupées livrées (`groupOrders`, lisibles par tout connecté),
// plus les commandes closes dont le ménage lecteur a déjà cueilli sa part.
// Éligibilité : la part du ménage lecteur dans ces commandes (`groupOrders/{id}/shares/{householdId}`) ;
// une part d'un groupe dont il n'est pas membre est illisible (règles) et compte comme « pas acheteur ».
// firestore.rules revérifie tout à l'écriture : membre du ménage, note 1…5, commande livrée du vendeur avec sa part.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreVendorReviewRepository: VendorReviewRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()`.
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var reviewsRef: CollectionReference { db.collection(FirestoreCollection.vendorReviews) }

    func reviews(ofVendor vendorId: String) async throws -> [VendorReview] {
        try await FirestoreVendorRepository.fetch(VendorReview.self, reviewsRef.whereField("vendorId", isEqualTo: vendorId))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveReview(_ review: VendorReview) async throws -> VendorReview {
        guard VendorReview.ratingRange.contains(review.rating) else {
            throw AppError.invalidInput(String(localized: "Choisis une note de 1 à 5 étoiles."))
        }
        guard review.id == VendorReview.documentId(vendorId: review.vendorId, householdId: review.householdId) else {
            throw AppError.permissionDenied
        }
        do {
            try await reviewsRef.document(review.id).setData(try Firestore.Encoder().encode(review))
            return review
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    func sales(ofVendor vendorId: String, viewerHouseholdId: String?) async throws -> [VendorSale] {
        let offers = try await FirestoreVendorRepository.fetch(
            Offer.self, db.collection(FirestoreCollection.offers).whereField("vendorId", isEqualTo: vendorId)
        )
        guard !offers.isEmpty else { return [] }
        let offersById = Dictionary(offers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let products = (try? await FirestoreVendorRepository.fetch(
            Product.self, db.collection(FirestoreCollection.products).whereField("vendorId", isEqualTo: vendorId)
        )) ?? []
        let productNames = Dictionary(products.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        // `in` accepte 30 valeurs au plus.
        var orders: [GroupOrder] = []
        let ids = Array(offersById.keys)
        for start in stride(from: 0, to: ids.count, by: 30) {
            let chunk = Array(ids[start..<min(start + 30, ids.count)])
            orders += try await FirestoreVendorRepository.fetch(
                GroupOrder.self, db.collection(FirestoreCollection.groupOrders).whereField("offerId", in: chunk)
            )
        }

        var sales: [VendorSale] = []
        for order in orders where order.status == .delivered || order.status == .closed {
            guard let offer = offersById[order.offerId] else { continue }
            var buyers: Set<String> = []
            var pickedUpByViewer = false
            if let viewerHouseholdId, !viewerHouseholdId.isEmpty, let share = await share(viewerHouseholdId, in: order.id) {
                pickedUpByViewer = share.isPickedUp
                if order.status == .delivered || share.isPickedUp { buyers.insert(viewerHouseholdId) }
            }
            // Une commande close compte comme vente reçue seulement si le ménage lecteur a cueilli sa part.
            guard order.status == .delivered || pickedUpByViewer else { continue }
            sales.append(VendorSale(
                id: order.id, vendorId: vendorId, offerId: offer.id,
                productName: productNames[offer.productId] ?? String(localized: "Produit"),
                shareLabel: offer.shareUnit, shares: order.committedShares, households: order.committedHouseholds,
                date: offer.deadline, buyerHouseholdIds: buyers
            ))
        }
        return sales.sorted { $0.date > $1.date }
    }

    /// Part du ménage dans la commande. Illisible (autre groupe) ou absente : nil.
    private func share(_ householdId: String, in groupOrderId: String) async -> Share? {
        let ref = db.collection(FirestoreCollection.shares(ofGroupOrder: groupOrderId)).document(householdId)
        guard let snapshot = try? await ref.getDocument(), snapshot.exists else { return nil }
        var data = snapshot.data() ?? [:]
        data["householdId"] = householdId
        return try? Firestore.Decoder().decode(Share.self, from: data)
    }
}
#endif
