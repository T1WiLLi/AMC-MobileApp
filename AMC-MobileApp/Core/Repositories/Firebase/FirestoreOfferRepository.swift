// FirestoreOfferRepository.swift
// Dépôt Firestore des lots (`offers`) — B-018.
// Même comportement que `FakeOfferRepository` : lots triés par date limite, mêmes erreurs.
// Le fil (`activeOffers(inZone:)`) filtre côté serveur (`status == "active"` + `zones arrayContains`,
// index composite dans `firestore.indexes.json`) et trie en Swift : pas besoin d'un index sur `deadline`.
// `saveOffer` : `firestore.rules` exige le vendeur du lot et un produit existant du même vendeur.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreOfferRepository: OfferRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var offersRef: CollectionReference { db.collection(FirestoreCollection.offers) }

    func activeOffers(inZone zone: String?) async throws -> [Offer] {
        var query: Query = offersRef.whereField("status", isEqualTo: Offer.Status.active.rawValue)
        if let zone { query = query.whereField("zones", arrayContains: zone) }
        return try await PerfSignposts.measure("firestore.activeOffers") { try await fetch(query) }
    }

    func offers(ofVendor vendorId: String) async throws -> [Offer] {
        try await fetch(offersRef.whereField("vendorId", isEqualTo: vendorId))
    }

    func offer(id: String) async throws -> Offer {
        try await FirestoreVendorRepository.fetchOne(Offer.self, offersRef.document(id))
    }

    func saveOffer(_ offer: Offer) async throws {
        guard !offer.tiers.isEmpty else { throw AppError.invalidInput("Ajoute au moins un palier de prix.") }
        do {
            try await offersRef.document(offer.id).setData(try Firestore.Encoder().encode(offer))
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Tri par date limite, puis par id pour un ordre stable.
    private func fetch(_ query: Query) async throws -> [Offer] {
        try await FirestoreVendorRepository.fetch(Offer.self, query)
            .sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
    }
}
#endif
