// FirestoreUserRepository.swift
// Dépôt Firestore des utilisateurs (`users/{uid}`) et des ménages (`households/{id}`) — B-017.
// Même comportement que `FakeUserRepository` : les ViewModels ne voient pas la différence.
//
// Règles (`firestore.rules`) : un utilisateur ne lit et n'écrit que son propre document, et ne pose
// jamais `vendorId` (réservé au seed) ; un ménage n'est lu et écrit que par ses membres (`userIds`).
// Les écritures fusionnent (`merge: true`) : les champs que le modèle Swift ne porte pas
// (par exemple `households.groupId`, posé par le seed) sont conservés.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

nonisolated final class FirestoreUserRepository: UserRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private func userRef(_ id: String) -> DocumentReference {
        db.collection(FirestoreCollection.users).document(id)
    }

    private func householdRef(_ id: String) -> DocumentReference {
        db.collection(FirestoreCollection.households).document(id)
    }

    func user(id: String) async throws -> AppUser {
        try await FirestoreDocument.fetch(AppUser.self, userRef(id), idKey: "id")
    }

    func saveUser(_ user: AppUser) async throws {
        try await FirestoreDocument.save(user, to: userRef(user.id))
    }

    func household(id: String) async throws -> Household {
        try await FirestoreDocument.fetch(Household.self, householdRef(id), idKey: "id")
    }

    func saveHousehold(_ household: Household) async throws {
        try await FirestoreDocument.save(household, to: householdRef(household.id))
    }
}

/// Lecture, écriture et décodage communs aux dépôts Firestore de B-017 et B-018.
nonisolated enum FirestoreDocument {
    /// Lit un document ; `.notFound` s'il n'existe pas. L'id du document fait foi.
    static func fetch<T: Decodable>(_ type: T.Type, _ ref: DocumentReference, idKey: String) async throws -> T {
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            return try decode(T.self, snapshot, idKey: idKey)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Lit les documents d'une requête.
    static func query<T: Decodable>(_ type: T.Type, _ query: Query, idKey: String) async throws -> [T] {
        do {
            let snapshot = try await query.getDocuments()
            return try snapshot.documents.map { try decode(T.self, $0, idKey: idKey) }
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Écrit un document en fusionnant avec l'existant.
    static func save<T: Encodable>(_ value: T, to ref: DocumentReference) async throws {
        do {
            let data = try Firestore.Encoder().encode(value)
            try await ref.setData(data, merge: true)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Décode un document ; un document écrit sans champ id (seed, console) se décode quand même.
    static func decode<T: Decodable>(_ type: T.Type, _ snapshot: DocumentSnapshot, idKey: String) throws -> T {
        var data = snapshot.data() ?? [:]
        data[idKey] = snapshot.documentID
        do {
            return try Firestore.Decoder().decode(T.self, from: data)
        } catch {
            throw AppError.unknown("Document \(snapshot.reference.path) illisible : \(error.localizedDescription)")
        }
    }
}
#endif
