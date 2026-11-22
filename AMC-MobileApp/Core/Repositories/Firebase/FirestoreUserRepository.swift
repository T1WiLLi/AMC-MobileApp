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

    // MARK: T-159 — ménage partagé

    private func addressRef(_ lookupId: String) -> DocumentReference {
        db.collection(FirestoreCollection.householdAddresses).document(lookupId)
    }

    private func joinRequestRef(householdId: String, userId: String) -> DocumentReference {
        db.collection(FirestoreCollection.joinRequests(ofHousehold: householdId)).document(userId)
    }

    func householdAddress(lookupId: String) async throws -> HouseholdAddressEntry? {
        do {
            return try await FirestoreDocument.fetch(HouseholdAddressEntry.self, addressRef(lookupId), idKey: "id")
        } catch AppError.notFound {
            return nil
        }
    }

    func registerHouseholdAddress(_ entry: HouseholdAddressEntry) async throws {
        // Adresse déjà prise par un autre ménage : la règle refuse l'écriture, et c'est voulu (le premier reste).
        if let existing = try await householdAddress(lookupId: entry.id), existing.ownerId != entry.ownerId { return }
        try await FirestoreDocument.save(entry, to: addressRef(entry.id))
    }

    func requestToJoin(_ request: HouseholdJoinRequest) async throws {
        var pending = request
        pending.status = .pending
        // Écrase une ancienne demande de la même personne (pas de merge : statut et date repartent à neuf).
        do {
            let data = try Firestore.Encoder().encode(pending)
            try await joinRequestRef(householdId: request.householdId, userId: request.userId).setData(data)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    func joinRequest(householdId: String, userId: String) async throws -> HouseholdJoinRequest? {
        do {
            return try await FirestoreDocument.fetch(HouseholdJoinRequest.self,
                                                     joinRequestRef(householdId: householdId, userId: userId),
                                                     idKey: "userId")
        } catch AppError.notFound {
            return nil
        }
    }

    func joinRequests(ofHousehold householdId: String, byUserId userId: String) async throws -> [HouseholdJoinRequest] {
        let query = db.collection(FirestoreCollection.joinRequests(ofHousehold: householdId))
            .whereField("status", isEqualTo: HouseholdJoinRequest.Status.pending.rawValue)
        return try await FirestoreDocument.query(HouseholdJoinRequest.self, query, idKey: "userId")
            .sorted { $0.createdAt < $1.createdAt }
    }

    func deleteJoinRequest(householdId: String, userId: String) async throws {
        do {
            try await joinRequestRef(householdId: householdId, userId: userId).delete()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Un batch : ménage (userIds + memberNames) et demande (`accepted`) bougent ensemble (la règle du ménage
    /// vérifie que la demande existe, celle de la demande que l'uid est bien entré dans le ménage).
    func acceptJoinRequest(householdId: String, userId: String, byUserId ownerId: String) async throws -> Household {
        let household = try await household(id: householdId)
        guard let request = try await joinRequest(householdId: householdId, userId: userId) else { throw AppError.notFound }
        let updated = try HouseholdMembership.accepting(request, in: household, byUserId: ownerId)
        let batch = db.batch()
        batch.updateData([
            "userIds": FieldValue.arrayUnion([userId]),
            "memberNames.\(userId)": request.displayName,
        ], forDocument: householdRef(householdId))
        batch.updateData(["status": HouseholdJoinRequest.Status.accepted.rawValue],
                         forDocument: joinRequestRef(householdId: householdId, userId: userId))
        do {
            try await batch.commit()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        return updated
    }

    func removeMember(_ userId: String, fromHousehold householdId: String, byUserId callerId: String) async throws -> Household {
        let household = try await household(id: householdId)
        let updated = try HouseholdMembership.removing(userId, from: household, byUserId: callerId)
        do {
            try await householdRef(householdId).updateData([
                "userIds": FieldValue.arrayRemove([userId]),
                "memberNames.\(userId)": FieldValue.delete(),
            ])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        return updated
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
