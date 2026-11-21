// FirestoreGroupWishRepository.swift
// Dépôt Firestore des envies des familles (`groups/{groupId}/wishes/{wishId}`) — S-07.
// Même comportement que `FakeGroupWishRepository` : les ViewModels ne voient pas la différence.
// Droits (firestore.rules) : un membre du groupe écrit les envies de SON ménage ; les membres du groupe
// et les vendeurs lisent (l'agrégat anonyme se calcule côté client, il n'y a pas de Cloud Functions).

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

/// Transporte un `ListenerRegistration` (non Sendable) dans `onTermination`.
/// Sûr : `remove()` est thread-safe et n'est appelé qu'une fois, à la fin du flux.
private nonisolated struct WishListenerBox: @unchecked Sendable {
    let registration: any ListenerRegistration
}

nonisolated final class FirestoreGroupWishRepository: GroupWishRepository, @unchecked Sendable {
    private let db: Firestore
    private let now: @Sendable () -> Date

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore(), now: @escaping @Sendable () -> Date = { .now }) {
        self.db = db
        self.now = now
    }

    // MARK: - Références

    private func wishesRef(_ groupId: String) -> CollectionReference {
        db.collection(FirestoreCollection.wishes(ofGroup: groupId))
    }

    // MARK: - Lectures

    func wishes(ofGroup groupId: String) async throws -> [GroupWish] {
        try await query(wishesRef(groupId))
    }

    func wishes(ofHousehold householdId: String, inGroup groupId: String) async throws -> [GroupWish] {
        try await query(wishesRef(groupId).whereField("householdId", isEqualTo: householdId))
    }

    func allWishes() async throws -> [GroupWish] {
        // Sans filtre : pas d'index de groupe de collections à déclarer ; filtrer côté client.
        try await query(db.collectionGroup(FirestoreCollection.wishes))
    }

    func observeWishes(ofGroup groupId: String) async -> AsyncThrowingStream<[GroupWish], any Error> {
        let (stream, continuation) = AsyncThrowingStream<[GroupWish], any Error>.makeStream()
        let registration = wishesRef(groupId).addSnapshotListener { snapshot, error in
            if let error {
                continuation.finish(throwing: Self.appError(from: error))
                return
            }
            guard let snapshot else { return }
            do {
                continuation.yield(try Self.sorted(snapshot.documents.map(Self.decode)))
            } catch {
                continuation.finish(throwing: Self.appError(from: error))
            }
        }
        // Le listener est retiré dès que le flux se termine (vue fermée, tâche annulée, erreur).
        let box = WishListenerBox(registration: registration)
        continuation.onTermination = { _ in box.registration.remove() }
        return stream
    }

    // MARK: - Écritures

    @discardableResult
    func addWish(_ wish: GroupWish) async throws -> GroupWish {
        try wish.validate()
        let ref = wish.id.isEmpty ? wishesRef(wish.groupId).document() : wishesRef(wish.groupId).document(wish.id)
        var created = wish
        created.id = ref.documentID
        created.createdAt = now()
        created.updatedAt = created.createdAt
        do {
            // Id choisi par l'appelant : ne pas écraser une envie existante (un id auto est toujours neuf).
            if !wish.id.isEmpty, try await ref.getDocument().exists {
                throw AppError.invalidInput("Cette envie existe déjà.")
            }
            try await ref.setData(try Firestore.Encoder().encode(created))
            return created
        } catch {
            throw Self.appError(from: error)
        }
    }

    @discardableResult
    func updateWish(_ wish: GroupWish) async throws -> GroupWish {
        let ref = wishesRef(wish.groupId).document(wish.id)
        do {
            let snapshot = try await ref.getDocument()
            guard snapshot.exists else { throw AppError.notFound }
            let current = try Self.decode(snapshot)
            guard current.householdId == wish.householdId else { throw AppError.permissionDenied }
            try wish.validate()
            var updated = wish
            updated.createdAt = current.createdAt
            updated.updatedAt = now()
            try await ref.setData(try Firestore.Encoder().encode(updated))
            return updated
        } catch {
            throw Self.appError(from: error)
        }
    }

    func removeWish(id: String, groupId: String) async throws {
        let ref = wishesRef(groupId).document(id)
        do {
            guard try await ref.getDocument().exists else { throw AppError.notFound }
            try await ref.delete()
        } catch {
            throw Self.appError(from: error)
        }
    }

    // MARK: - Requêtes et décodage

    private func query(_ query: Query) async throws -> [GroupWish] {
        do {
            let snapshot = try await query.getDocuments()
            return try Self.sorted(snapshot.documents.map(Self.decode))
        } catch {
            throw Self.appError(from: error)
        }
    }

    private static func sorted(_ wishes: [GroupWish]) -> [GroupWish] {
        wishes.sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id }
    }

    // L'id du document fait foi : un document écrit sans champ `id` (seed, console) se décode quand même.
    private static func decode(_ snapshot: DocumentSnapshot) throws -> GroupWish {
        var data = snapshot.data() ?? [:]
        data["id"] = snapshot.documentID
        do {
            return try Firestore.Decoder().decode(GroupWish.self, from: data)
        } catch {
            throw AppError.unknown("Document \(snapshot.reference.path) illisible : \(error.localizedDescription)")
        }
    }

    private static func appError(from error: any Error) -> AppError {
        FirestoreGroupOrderRepository.appError(from: error)
    }
}
#endif
