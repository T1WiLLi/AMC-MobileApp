// FirestoreGroupRepository.swift
// Dépôt Firestore des groupes de quartier (`groups/{id}`) et de leurs membres
// (`groups/{id}/members/{householdId}`) — B-017.
// Même comportement que `FakeGroupRepository`, à une différence près (voir `join`).
//
// Règles (`firestore.rules`) : tout utilisateur connecté lit les groupes et leurs membres ;
// un ménage s'ajoute (rôle `member`) ou se retire lui-même ; le document du groupe n'est jamais
// écrit par le client. Conséquence : `householdCount` est tenu par le seed (ou un futur processus
// de confiance), pas par `join` / `leave`.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

/// Transporte un `ListenerRegistration` (non Sendable) dans `onTermination`.
/// Sûr : `remove()` est thread-safe et n'est appelé qu'une fois, à la fin du flux.
private nonisolated struct GroupListenerBox: @unchecked Sendable {
    let registration: any ListenerRegistration
}

nonisolated final class FirestoreGroupRepository: GroupRepository, @unchecked Sendable {
    private let db: Firestore

    /// À créer APRÈS `FirebaseApp.configure()` (voir docs/firebase.md, § 3).
    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    // MARK: - Références

    private var groupsRef: CollectionReference { db.collection(FirestoreCollection.groups) }
    private func groupRef(_ id: String) -> DocumentReference { groupsRef.document(id) }
    private func membersRef(_ groupId: String) -> CollectionReference {
        db.collection(FirestoreCollection.members(ofGroup: groupId))
    }

    // MARK: - Lectures

    func groups(inNeighborhood neighborhood: String?) async throws -> [NeighborhoodGroup] {
        var query: Query = groupsRef.whereField("isPublic", isEqualTo: true)
        if let neighborhood {
            query = query.whereField("neighborhood", isEqualTo: neighborhood)
        }
        return try await FirestoreDocument.query(NeighborhoodGroup.self, query, idKey: "id")
            .sorted { $0.name < $1.name }
    }

    func group(id: String) async throws -> NeighborhoodGroup {
        try await FirestoreDocument.fetch(NeighborhoodGroup.self, groupRef(id), idKey: "id")
    }

    func groups(ofHousehold householdId: String) async throws -> [NeighborhoodGroup] {
        // Une adhésion vit sous son groupe : la requête de groupe de collections les retrouve toutes.
        let memberships: [DocumentSnapshot]
        do {
            memberships = try await db.collectionGroup("members")
                .whereField("householdId", isEqualTo: householdId)
                .getDocuments()
                .documents
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        let groupIds = Set(memberships.compactMap { $0.reference.parent.parent?.documentID })
        var groups: [NeighborhoodGroup] = []
        for groupId in groupIds {
            do {
                groups.append(try await group(id: groupId))
            } catch AppError.notFound {
                continue // Adhésion orpheline (groupe supprimé) : ignorée, comme dans le fake.
            }
        }
        return groups.sorted { $0.name < $1.name }
    }

    func members(ofGroup groupId: String) async throws -> [GroupMember] {
        _ = try await group(id: groupId)
        return try await FirestoreDocument.query(GroupMember.self, membersRef(groupId), idKey: "householdId")
            .sorted { $0.joinedAt < $1.joinedAt }
    }

    func observeGroup(id: String) async -> AsyncThrowingStream<NeighborhoodGroup, any Error> {
        let (stream, continuation) = AsyncThrowingStream<NeighborhoodGroup, any Error>.makeStream()
        let registration = groupRef(id).addSnapshotListener { snapshot, error in
            if let error {
                continuation.finish(throwing: FirestoreGroupOrderRepository.appError(from: error))
                return
            }
            guard let snapshot, snapshot.exists else {
                continuation.finish(throwing: AppError.notFound)
                return
            }
            do {
                continuation.yield(try FirestoreDocument.decode(NeighborhoodGroup.self, snapshot, idKey: "id"))
            } catch {
                continuation.finish(throwing: FirestoreGroupOrderRepository.appError(from: error))
            }
        }
        // Le listener est retiré dès que le flux se termine (vue fermée, tâche annulée, erreur).
        let box = GroupListenerBox(registration: registration)
        continuation.onTermination = { _ in box.registration.remove() }
        return stream
    }

    // MARK: - Écritures

    /// Ajoute le ménage au groupe ; sans effet s'il en fait déjà partie.
    /// Contrairement au fake, `householdCount` ne bouge pas : les règles interdisent au client
    /// d'écrire le document du groupe.
    func join(groupId: String, householdId: String) async throws {
        _ = try await group(id: groupId)
        let ref = membersRef(groupId).document(householdId)
        do {
            if try await ref.getDocument().exists { return }
            // `joinedAt` doit valoir `request.time` pour les règles : horodatage du serveur.
            try await ref.setData([
                "householdId": householdId,
                "role": GroupMember.Role.member.rawValue,
                "joinedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Retire le ménage du groupe ; sans effet s'il n'en fait pas partie.
    func leave(groupId: String, householdId: String) async throws {
        _ = try await group(id: groupId)
        let ref = membersRef(groupId).document(householdId)
        do {
            guard try await ref.getDocument().exists else { return }
            try await ref.delete()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }
}
#endif
