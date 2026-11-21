// FirestorePickupPointRepository.swift
// Dépôt Firestore des points de cueillette (`pickupPoints`) — B-018.
// L'hôte gère ses créneaux et sa capacité (`savePickupPoint`, T-077) ; `firestore.rules` vérifie que
// `hostUserId` est l'utilisateur connecté et quels champs changent.

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

    /// Point de l'hôte connecté (T-077, RQ-062). Fusion (`merge`) : les champs inchangés ne comptent pas
    /// comme modifiés pour `firestore.rules`, qui exige `hostUserId == uid` et limite les champs modifiables.
    func savePickupPoint(_ point: PickupPoint) async throws {
        do {
            try await pickupPointsRef.document(point.id)
                .setData(try Firestore.Encoder().encode(point), merge: true)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }
}
#endif
