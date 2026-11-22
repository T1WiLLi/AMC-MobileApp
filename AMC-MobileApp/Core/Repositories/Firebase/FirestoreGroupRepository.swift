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
    private func invitationRef(_ code: String) -> DocumentReference {
        db.collection(FirestoreCollection.groupInvitations).document(code)
    }

    // MARK: - Lectures

    func groups(inNeighborhood neighborhood: String?) async throws -> [NeighborhoodGroup] {
        var query: Query = groupsRef.whereField("isPublic", isEqualTo: true)
        if let neighborhood {
            query = query.whereField("neighborhood", isEqualTo: neighborhood)
        }
        return try await FirestoreDocument.query(NeighborhoodGroup.self, query, idKey: "id")
            .map { $0.resolvingMediaURLs() }
            .sorted { $0.name < $1.name }
    }

    func group(id: String) async throws -> NeighborhoodGroup {
        try await FirestoreDocument.fetch(NeighborhoodGroup.self, groupRef(id), idKey: "id").resolvingMediaURLs()
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
                continuation.yield(try FirestoreDocument.decode(NeighborhoodGroup.self, snapshot, idKey: "id").resolvingMediaURLs())
            } catch {
                continuation.finish(throwing: FirestoreGroupOrderRepository.appError(from: error))
            }
        }
        // Le listener est retiré dès que le flux se termine (vue fermée, tâche annulée, erreur).
        let box = GroupListenerBox(registration: registration)
        continuation.onTermination = { _ in box.registration.remove() }
        return stream
    }

    /// FB-22 : même requête de groupe de collections que `groups(ofHousehold:)`, en écoute. Un membre du
    /// ménage qui rejoint ou quitte un groupe sur son téléphone apparaît chez les autres sans recharger.
    func observeGroupIds(ofHousehold householdId: String) async -> AsyncThrowingStream<Set<String>, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Set<String>, any Error>.makeStream()
        let registration = db.collectionGroup("members")
            .whereField("householdId", isEqualTo: householdId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: FirestoreGroupOrderRepository.appError(from: error))
                    return
                }
                let ids = (snapshot?.documents ?? []).compactMap { $0.reference.parent.parent?.documentID }
                continuation.yield(Set(ids))
            }
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

    /// T-122 : l'image est déjà dans `groups/{id}/media/{photo|banner}` ; on pose `photoUpdatedAt` / `bannerUpdatedAt`
    /// = horodatage serveur (firestore.rules T-132 : coordinateur seulement, `== request.time`, rien d'autre).
    /// L'URL lue ensuite en est déduite (`resolvingMediaURLs()`).
    /// Retirer (url nil) n'est pas encore permis par les règles : refus explicite.
    func updateImage(_ kind: GroupImageKind, url: URL?, ofGroup groupId: String, byUserId userId: String) async throws {
        _ = try await group(id: groupId)
        guard url != nil else {
            throw AppError.invalidInput("Retirer une image n'est pas encore possible : choisis plutôt une autre photo.")
        }
        do {
            try await groupRef(groupId).updateData([NeighborhoodGroup.updatedAtField(kind): FieldValue.serverTimestamp()])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    /// B-036 : remplace tout le champ `branding` (les champs nil sont omis = valeur par défaut).
    /// firestore.rules : coordinateur seulement, rien d'autre ne bouge.
    func updateBranding(_ branding: GroupBranding, ofGroup groupId: String, byUserId userId: String) async throws {
        _ = try await group(id: groupId)
        do {
            let data = try Firestore.Encoder().encode(branding)
            try await groupRef(groupId).updateData(["branding": data])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }

    // MARK: - B-056 Visibilité et invitations
    // Règles : le créateur seul (`createdBy`, sinon le premier coordonnateur) change `isPublic`, crée, liste
    // et révoque les invitations. Rejoindre un groupe privé consomme l'invitation dans la même transaction
    // que l'adhésion et le compteur ; les règles refusent l'un sans l'autre.

    func setVisibility(isPublic: Bool, ofGroup groupId: String, byUserId userId: String) async throws -> NeighborhoodGroup {
        var group = try await group(id: groupId)
        try GroupRules.requireCreator(userId, of: group)
        guard group.isPublic != isPublic else { return group }
        do {
            try await groupRef(groupId).updateData(["isPublic": isPublic])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        group.isPublic = isPublic
        return group
    }

    func invitations(ofGroup groupId: String, byUserId userId: String) async throws -> [GroupInvitation] {
        let group = try await group(id: groupId)
        try GroupRules.requireCreator(userId, of: group)
        // `createdBy` dans la requête : les règles ne laissent lister que ses propres invitations.
        let query = db.collection(FirestoreCollection.groupInvitations)
            .whereField("groupId", isEqualTo: groupId)
            .whereField("createdBy", isEqualTo: userId)
        return GroupRules.sortedForDisplay(try await FirestoreDocument.query(GroupInvitation.self, query, idKey: "code"))
    }

    func createInvitation(forGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation {
        let group = try await group(id: groupId)
        var taken: Set<String> = []
        // Un code déjà pris (rare) : on en tire un autre, au plus trois fois.
        for _ in 0..<3 {
            let invitation = try GroupRules.makeInvitation(for: group, byUserId: userId, existingCodes: taken)
            let ref = invitationRef(invitation.code)
            do {
                if try await ref.getDocument().exists {
                    taken.insert(invitation.code)
                    continue
                }
                // `createdAt` doit valoir `request.time` : horodatage du serveur.
                try await ref.setData([
                    "code": invitation.code,
                    "groupId": groupId,
                    "createdBy": userId,
                    "createdAt": FieldValue.serverTimestamp(),
                ])
            } catch {
                throw FirestoreGroupOrderRepository.appError(from: error)
            }
            return invitation
        }
        throw AppError.unknown("Impossible de créer une invitation pour l'instant. Réessaie.")
    }

    func revokeInvitation(code: String, ofGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation {
        let group = try await group(id: groupId)
        let ref = invitationRef(GroupRules.normalizedInviteCode(code))
        let invitation = try await FirestoreDocument.fetch(GroupInvitation.self, ref, idKey: "code")
        let revoked = try GroupRules.revoking(invitation, in: group, byUserId: userId)
        guard invitation.status == .active else { return revoked }
        do {
            try await ref.updateData(["revokedAt": FieldValue.serverTimestamp()])
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        return revoked
    }

    func join(withCode input: String, householdId: String) async throws -> NeighborhoodGroup {
        let code = try GroupRules.validatedInviteCode(GroupRules.inviteCode(fromUserInput: input) ?? input)
        let ref = invitationRef(code)
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await ref.getDocument()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        if snapshot.exists {
            let invitation = try FirestoreTransactions.decode(GroupInvitation.self, snapshot, idKey: "code")
            try GroupRules.validateForJoining(invitation)
            try await consume(code: code, groupId: invitation.groupId, householdId: householdId)
            return try await group(id: invitation.groupId)
        }
        // Pas d'invitation : code fixe d'un groupe public (RQ-026).
        let query = groupsRef.whereField("isPublic", isEqualTo: true).whereField("inviteCode", isEqualTo: code)
        let matches = try await FirestoreDocument.query(NeighborhoodGroup.self, query, idKey: "id")
        guard let group = matches.first(where: { GroupRules.acceptsFixedCode($0, code: code) }) else {
            throw GroupRules.unknownInviteCodeError
        }
        try await join(groupId: group.id, householdId: householdId)
        return try await self.group(id: group.id)
    }

    /// Invitation relue, adhésion, compteur et `usedBy` / `usedAt` dans une seule transaction : deux voisins
    /// qui utilisent le même lien en même temps, un seul entre. Déjà membre : rien n'est écrit.
    private func consume(code: String, groupId: String, householdId: String) async throws {
        let invitationRef = invitationRef(code)
        let memberRef = membersRef(groupId).document(householdId)
        let groupRef = groupRef(groupId)
        _ = try await FirestoreTransactions.run(db) { transaction -> Bool in
            let invitation = try FirestoreTransactions.decode(
                GroupInvitation.self, try transaction.getDocument(invitationRef), idKey: "code"
            )
            guard invitation.groupId == groupId else { throw AppError.notFound }
            if try transaction.getDocument(memberRef).exists { return false }
            try GroupRules.validateForJoining(invitation)
            transaction.setData([
                "householdId": householdId,
                "role": GroupMember.Role.member.rawValue,
                "joinedAt": FieldValue.serverTimestamp(),
                "invitationCode": code,
            ], forDocument: memberRef)
            transaction.updateData([
                "householdCount": FieldValue.increment(Int64(1)),
                "lastMembershipChange": householdId,
            ], forDocument: groupRef)
            transaction.updateData([
                "usedBy": householdId,
                "usedAt": FieldValue.serverTimestamp(),
            ], forDocument: invitationRef)
            return true
        }
    }

    // MARK: - T-174 Avis des familles

    private func ratingsRef(_ groupId: String) -> CollectionReference {
        db.collection(FirestoreCollection.ratings(ofGroup: groupId))
    }

    func ratings(ofGroup groupId: String) async throws -> [GroupRating] {
        try await FirestoreDocument.query(GroupRating.self, ratingsRef(groupId), idKey: "id")
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Avis et agrégats du groupe dans une seule transaction (relue si deux familles notent en même temps) :
    /// `ratingSum` / `ratingCount` bougent de l'écart exact, avec `lastRatingChange` = le ménage, ce que
    /// firestore.rules revérifie des deux côtés (avis et groupe). Une modification ne réécrit que la note,
    /// le commentaire, la signature et la date : création et preuve d'adhésion ne bougent jamais.
    func saveRating(_ rating: GroupRating) async throws -> NeighborhoodGroup {
        try GroupRatingRules.validate(rating)
        let groupRef = groupRef(rating.groupId)
        let ratingRef = ratingsRef(rating.groupId).document(rating.householdId)
        let encoded = try Firestore.Encoder().encode(rating)
        _ = try await FirestoreTransactions.run(db) { transaction -> Bool in
            guard try transaction.getDocument(groupRef).exists else { throw AppError.notFound }
            let previousSnapshot = try transaction.getDocument(ratingRef)
            let previous = previousSnapshot.exists
                ? try FirestoreTransactions.decode(GroupRating.self, previousSnapshot)
                : nil
            let delta = RatingRules.aggregateDelta(previous: previous?.rating, new: rating.rating)
            if previous != nil {
                transaction.updateData([
                    "authorName": rating.authorName,
                    "rating": rating.rating,
                    "comment": rating.comment.map { $0 as Any } ?? FieldValue.delete(),
                    "updatedAt": Timestamp(date: rating.updatedAt),
                ], forDocument: ratingRef)
            } else {
                transaction.setData(encoded, forDocument: ratingRef)
            }
            transaction.updateData([
                "ratingSum": FieldValue.increment(Int64(delta.sum)),
                "ratingCount": FieldValue.increment(Int64(delta.count)),
                "lastRatingChange": rating.householdId,
            ], forDocument: groupRef)
            return true
        }
        return try await group(id: rating.groupId)
    }

    // MARK: - B-059 Création

    /// Groupe (compteur à 1) et adhésion coordonnateur du ménage créateur dans un seul batch : les règles
    /// exigent les deux ensemble (`isGroupCreation`). La limite de 3 groupes (RQ-030) est vérifiée ici,
    /// les règles ne pouvant pas compter les adhésions d'un ménage.
    func createGroup(_ draft: GroupRules.Draft, byUserId userId: String, householdId: String) async throws -> NeighborhoodGroup {
        let current = try await groups(ofHousehold: householdId)
        try GroupRules.requireRoomToCreate(householdGroupIds: current.map(\.id))
        let creation = try GroupRules.makeGroup(
            from: draft, creatorUserId: userId, creatorHouseholdId: householdId,
            makeId: { self.groupsRef.document().documentID }
        )
        let group = creation.group
        let batch = db.batch()
        batch.setData([
            "name": group.name,
            "neighborhood": group.neighborhood,
            "centerGeohash": group.centerGeohash,
            "radiusMeters": group.radiusMeters,
            "coordinatorIds": group.coordinatorIds,
            "householdCount": group.householdCount,
            "isPublic": group.isPublic,
            "inviteCode": group.inviteCode,
            "createdBy": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "lastMembershipChange": householdId,
        ], forDocument: groupRef(group.id))
        // `joinedAt` doit valoir `request.time` pour les règles : horodatage du serveur.
        batch.setData([
            "householdId": householdId,
            "role": GroupMember.Role.coordinator.rawValue,
            "joinedAt": FieldValue.serverTimestamp(),
        ], forDocument: membersRef(group.id).document(householdId))
        do {
            try await batch.commit()
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
        return group
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
