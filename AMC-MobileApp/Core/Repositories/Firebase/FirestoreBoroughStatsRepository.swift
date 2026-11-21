// FirestoreBoroughStatsRepository.swift
// Dépôt Firestore des agrégats d'arrondissement (`boroughStats/{boroughId}`) — RQ-093, T-114.
// Lecture seule : firestore.rules refuse toute écriture client ; le seed (Admin SDK) remplit la collection.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreBoroughStatsRepository: BoroughStatsRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func boroughStats() async throws -> [BoroughStats] {
        do {
            let snapshot = try await db.collection(FirestoreCollection.boroughStats).getDocuments()
            // Un document illisible (champ manquant dans une saisie manuelle) est ignoré plutôt que de tout bloquer.
            return snapshot.documents.compactMap(Self.decode).sorted { $0.id < $1.id }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    // L'id du document fait foi : un document écrit sans champ `id` se décode quand même.
    private static func decode(_ snapshot: QueryDocumentSnapshot) -> BoroughStats? {
        var data = snapshot.data()
        data["id"] = snapshot.documentID
        return try? Firestore.Decoder().decode(BoroughStats.self, from: data)
    }
}
#endif
