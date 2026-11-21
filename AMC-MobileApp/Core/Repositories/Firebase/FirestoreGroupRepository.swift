// FirestoreGroupRepository.swift
// Dépôt Firestore des groupes de quartier (`groups/{id}`) et de leurs membres
// (`groups/{id}/members/{householdId}`) — B-017.
// Même comportement que `FakeGroupRepository`.
//
// Règles (`firestore.rules`) : tout utilisateur connecté lit les groupes et leurs membres ;
// un ménage s'ajoute (rôle `member`) ou se retire lui-même. Sans serveur, `join` / `leave` tiennent
// `householdCount` eux-mêmes (T-099) : un batch atomique écrit l'adhésion et `householdCount` ±1,
// avec `lastMembershipChange` = le ménage concerné, que les règles vérifient. Le compteur et les
// adhésions ne peuvent donc pas diverger.

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

    /// Ajoute le ménage au groupe et incrémente `householdCount` ; sans effet s'il en fait déjà partie.
    func join(groupId: String, householdId: String) async throws {
        try await changeMembership(groupId: groupId, householdId: householdId, joining: true)
    }

    /// Retire le ménage du groupe et décrémente `householdCount` ; sans effet s'il n'en fait pas partie.
    func leave(groupId: String, householdId: String) async throws {
        try await changeMembership(groupId: groupId, householdId: householdId, joining: false)
    }

    /// T-122 : URL versionnée de la photo ou de la bannière (l'image est dans `groups/{id}/media/…`).
    /// firestore.rules : un coordinateur seulement, et rien d'autre ne change dans la même écriture.
    func updateImage(_ kind: GroupImageKind, url: URL?, ofGroup groupId: String, byUserId userId: String) async throws {
        _ = try await group(id: groupId)
        do {
            try await groupRef(groupId).updateData([kind.field: url?.absoluteString ?? FieldValue.delete()])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// Adhésion + compteur dans un seul batch : les règles refusent l'un sans l'autre.
    private func changeMembership(groupId: String, householdId: String, joining: Bool) async throws {
        _ = try await group(id: groupId)
        let memberRef = membersRef(groupId).document(householdId)
        do {
            let isMember = try await memberRef.getDocument().exists
            guard isMember != joining else { return }
            let batch = db.batch()
            if joining {
                // `joinedAt` doit valoir `request.time` pour les règles : horodatage du serveur.
                batch.setData([
                    "householdId": householdId,
                    "role": GroupMember.Role.member.rawValue,
                    "joinedAt": FieldValue.serverTimestamp(),
                ], forDocument: memberRef)
            } else {
                batch.deleteDocument(memberRef)
            }
            batch.updateData([
                "householdCount": FieldValue.increment(Int64(joining ? 1 : -1)),
                "lastMembershipChange": householdId,
            ], forDocument: groupRef(groupId))
            try await batch.commit()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }
}
#endif
