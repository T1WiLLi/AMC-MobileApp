// FirestoreUserGroupRepositoryTests.swift
// B-017 : tests d'intégration des dépôts Firestore users/households et groups/members, contre l'émulateur
// local (règles de `firestore.rules` comprises). Sautés quand l'émulateur ne répond pas (CI, Mac sans Node).
// Réutilise `FirestoreEmulator` et `EmulatorDevice` de `FirestoreGroupOrderRepositoryTests.swift`.
//
// Lancer l'émulateur depuis la racine du repo :
//   npx -y firebase-tools@latest emulators:start --project demo-grenier --only auth,firestore

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import Foundation
import Testing
import FirebaseFirestore
@testable import AMC_MobileApp

@Suite(.serialized, .enabled(if: FirestoreEmulator.isAvailable, "Émulateur Firebase absent (127.0.0.1:8080 et :9099)"))
struct FirestoreUserGroupRepositoryTests {
    private static func makeUser(_ uid: String, householdId: String?) -> AppUser {
        AppUser(
            id: uid, displayName: "Amina", photoURL: nil, language: .french, roles: [.family],
            neighborhood: "Parc-Extension", dietaryPreferences: [], seniorMode: false,
            householdId: householdId, vendorId: nil
        )
    }

    private static func seedGroup(_ id: String, name: String, neighborhood: String, isPublic: Bool = true) async throws {
        try await FirestoreEmulator.seed("groups/\(id)", [
            "id": id, "name": name, "neighborhood": neighborhood, "centerGeohash": "f25dv",
            "radiusMeters": 800, "coordinatorIds": [String](), "householdCount": 0, "isPublic": isPublic,
            "inviteCode": "CODE",
        ])
    }

    // MARK: - Utilisateurs et ménages

    @Test func userAndHouseholdRoundTripForTheirOwner() async throws {
        let amina = try await EmulatorDevice.signIn()
        let users = FirestoreUserRepository(db: amina.db)
        let householdId = "household-\(amina.uid)"

        try await users.saveUser(Self.makeUser(amina.uid, householdId: householdId))
        let household = Household(id: householdId, name: "Famille Haddad", size: 4, geohash: "f25dv", userIds: [amina.uid])
        try await users.saveHousehold(household)

        #expect(try await users.user(id: amina.uid).displayName == "Amina")
        #expect(try await users.household(id: householdId) == household)

        var renamed = household
        renamed.size = 5
        try await users.saveHousehold(renamed)
        #expect(try await users.household(id: householdId).size == 5)
    }

    @Test func savingKeepsFieldsTheModelDoesNotCarry() async throws {
        let amina = try await EmulatorDevice.signIn()
        let householdId = "household-\(amina.uid)"
        // Le seed pose `groupId`, que `Household` ne porte pas : une écriture ne doit pas l'effacer.
        try await FirestoreEmulator.seed("households/\(householdId)", [
            "id": householdId, "name": "Famille", "size": 2, "geohash": "f25dv",
            "userIds": [amina.uid], "groupId": "group-seed",
        ])
        let users = FirestoreUserRepository(db: amina.db)
        var household = try await users.household(id: householdId)
        household.name = "Famille Haddad"
        try await users.saveHousehold(household)

        let raw = try await amina.db.document("households/\(householdId)").getDocument().data()
        #expect(raw?["groupId"] as? String == "group-seed")
        #expect(raw?["name"] as? String == "Famille Haddad")
    }

    @Test func someoneElsesProfileIsDenied() async throws {
        let amina = try await EmulatorDevice.signIn()
        let bruno = try await EmulatorDevice.signIn()
        try await FirestoreUserRepository(db: amina.db).saveUser(Self.makeUser(amina.uid, householdId: nil))

        await #expect(throws: AppError.permissionDenied) {
            _ = try await FirestoreUserRepository(db: bruno.db).user(id: amina.uid)
        }
    }

    @Test func missingUserIsNotFound() async throws {
        let amina = try await EmulatorDevice.signIn()
        await #expect(throws: AppError.notFound) {
            _ = try await FirestoreUserRepository(db: amina.db).user(id: amina.uid)
        }
    }

    // MARK: - Groupes

    @Test func publicGroupsAreFilteredByNeighborhoodAndSorted() async throws {
        let suffix = UUID().uuidString.prefix(6).lowercased()
        let neighborhood = "quartier-\(suffix)"
        try await Self.seedGroup("g-b-\(suffix)", name: "Voisins B", neighborhood: neighborhood)
        try await Self.seedGroup("g-a-\(suffix)", name: "Voisins A", neighborhood: neighborhood)
        try await Self.seedGroup("g-p-\(suffix)", name: "Privé", neighborhood: neighborhood, isPublic: false)
        let amina = try await EmulatorDevice.signIn()
        let groups = FirestoreGroupRepository(db: amina.db)

        let names = try await groups.groups(inNeighborhood: neighborhood).map(\.name)
        #expect(names == ["Voisins A", "Voisins B"])
        #expect(try await groups.group(id: "g-p-\(suffix)").isPublic == false)
    }

    @Test func joinIsIdempotentAndLeaveRemovesTheMembership() async throws {
        // T-099 : join / leave tiennent aussi householdCount (batch atomique avec l'adhésion).
        let suffix = UUID().uuidString.prefix(6).lowercased()
        let groupId = "g-\(suffix)"
        try await Self.seedGroup(groupId, name: "Parc-Ex Nord", neighborhood: "Parc-Extension")
        let amina = try await EmulatorDevice.signIn()
        let householdId = "household-\(amina.uid)"
        try await FirestoreUserRepository(db: amina.db).saveHousehold(
            Household(id: householdId, name: "Famille", size: 3, geohash: "f25dv", userIds: [amina.uid])
        )
        let groups = FirestoreGroupRepository(db: amina.db)

        try await groups.join(groupId: groupId, householdId: householdId)
        try await groups.join(groupId: groupId, householdId: householdId)
        let members = try await groups.members(ofGroup: groupId)
        #expect(members.map(\.householdId) == [householdId])
        #expect(members.first?.role == .member)
        #expect(try await groups.groups(ofHousehold: householdId).map(\.id) == [groupId])
        #expect(try await groups.group(id: groupId).householdCount == 1)

        try await groups.leave(groupId: groupId, householdId: householdId)
        try await groups.leave(groupId: groupId, householdId: householdId)
        #expect(try await groups.members(ofGroup: groupId).isEmpty)
        #expect(try await groups.groups(ofHousehold: householdId).isEmpty)
        #expect(try await groups.group(id: groupId).householdCount == 0)
    }

    @Test func joiningForAnotherHouseholdIsDenied() async throws {
        let suffix = UUID().uuidString.prefix(6).lowercased()
        let groupId = "g-\(suffix)"
        try await Self.seedGroup(groupId, name: "Verdun", neighborhood: "Verdun")
        let bruno = try await EmulatorDevice.signIn()

        await #expect(throws: AppError.permissionDenied) {
            try await FirestoreGroupRepository(db: bruno.db).join(groupId: groupId, householdId: "household-quelqu-un")
        }
    }

    @Test func unknownGroupIsNotFound() async throws {
        let amina = try await EmulatorDevice.signIn()
        await #expect(throws: AppError.notFound) {
            try await FirestoreGroupRepository(db: amina.db).join(groupId: "g-inconnu-\(UUID())", householdId: "h")
        }
    }

    @Test func observeGroupStreamsChanges() async throws {
        let suffix = UUID().uuidString.prefix(6).lowercased()
        let groupId = "g-\(suffix)"
        try await Self.seedGroup(groupId, name: "Rosemont", neighborhood: "Rosemont")
        let amina = try await EmulatorDevice.signIn()
        let stream = await FirestoreGroupRepository(db: amina.db).observeGroup(id: groupId)
        var iterator = stream.makeAsyncIterator()

        #expect(try await iterator.next()?.householdCount == 0)
        try await FirestoreEmulator.seed("groups/\(groupId)", [
            "id": groupId, "name": "Rosemont", "neighborhood": "Rosemont", "centerGeohash": "f25dv",
            "radiusMeters": 800, "coordinatorIds": [String](), "householdCount": 7, "isPublic": true,
            "inviteCode": "CODE",
        ])
        #expect(try await iterator.next()?.householdCount == 7)
    }
}
#endif
