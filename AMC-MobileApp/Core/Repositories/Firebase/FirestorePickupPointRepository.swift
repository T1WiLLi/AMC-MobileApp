// FirestorePickupPointRepository.swift
// Dépôt Firestore des points de cueillette (`pickupPoints`) — B-018. Lecture seule, comme le protocole ;
// l'hôte gère ses créneaux et sa capacité (voir `firestore.rules`).

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestorePickupPointRepository: PickupPointRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var pickupPointsRef: CollectionReference { db.collection(FirestoreCollection.pickupPoints) }

    func pickupPoints() async throws -> [PickupPoint] {
        try await FirestoreVendorRepository.fetch(PickupPoint.self, pickupPointsRef).sorted { $0.name < $1.name }
    }

    func pickupPoint(id: String) async throws -> PickupPoint {
        try await FirestoreVendorRepository.fetchOne(PickupPoint.self, pickupPointsRef.document(id))
    }
}
#endif
