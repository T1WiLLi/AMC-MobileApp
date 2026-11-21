// GroupInvitationTests.swift
// B-056 : groupes publics ou privés, invitations à usage unique (domaine, dépôt fake, décodage tolérant,
// ViewModels du créateur, de la feuille « Rejoindre avec un code » et de la liste triée par distance).

import Foundation
import Testing
@testable import AMC_MobileApp

struct GroupInvitationTests {
    private typealias ID = FakeData.ID

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func group(isPublic: Bool = false, coordinatorIds: [String] = ["creator", "helper"],
                              createdBy: String? = "creator", inviteCode: String = "PUB234") -> NeighborhoodGroup {
        NeighborhoodGroup(id: "g1", name: "Cuisine", neighborhood: "Villeray", centerGeohash: "f25du",
                          radiusMeters: 1_000, coordinatorIds: coordinatorIds, householdCount: 1,
                          isPublic: isPublic, inviteCode: inviteCode, createdBy: createdBy)
    }

    private static func invitation(_ code: String = "ABC234", usedBy: String? = nil, revokedAt: Date? = nil) -> GroupInvitation {
        GroupInvitation(code: code, groupId: "g1", createdBy: "creator", createdAt: now,
                        usedBy: usedBy, usedAt: usedBy == nil ? nil : now, revokedAt: revokedAt)
    }

    // MARK: Domaine

    @Test func creatorIsCreatedByThenFirstCoordinator() {
        #expect(Self.group().creatorId == "creator")
        #expect(GroupRules.isCreator("creator", of: Self.group()))
        // Un autre coordonnateur n'est pas le créateur.
        #expect(!GroupRules.isCreator("helper", of: Self.group()))
        #expect(Self.group(createdBy: nil).creatorId == "creator")
        #expect(Self.group(coordinatorIds: [], createdBy: nil).creatorId == nil)
        #expect(!GroupRules.isCreator(nil, of: Self.group()))
        #expect(!GroupRules.isCreator("", of: Self.group(coordinatorIds: [""], createdBy: nil)))
    }

    @Test func makeGroupRecordsItsCreator() throws {
        let creation = try GroupRules.makeGroup(
            from: .init(name: "Cuisine collective", neighborhood: "villeray", centerGeohash: "f25du", isPublic: false),
            creatorUserId: "u1", creatorHouseholdId: "h1", makeId: { "g" }, makeInviteCode: { "ABC234" }
        )
        #expect(creation.group.createdBy == "u1")
        #expect(!creation.group.isPublic)
        #expect(GroupRules.isCreator("u1", of: creation.group))
    }

    @Test func onlyTheCreatorMakesAnInvitation() throws {
        var rng = GroupRulesTests.SeededGenerator(state: 7)
        let invitation = try GroupRules.makeInvitation(for: Self.group(), byUserId: "creator", existingCodes: [],
                                                       now: Self.now, using: &rng)
        #expect(invitation.status == .active)
        #expect(invitation.groupId == "g1")
        #expect(invitation.createdBy == "creator")
        #expect(GroupRules.isValidInviteCode(invitation.code))
        #expect(invitation.shareURL?.absoluteString == "https://grenier.app/join/\(invitation.code)")
        #expect(throws: AppError.permissionDenied) {
            try GroupRules.makeInvitation(for: Self.group(), byUserId: "helper")
        }
    }

    @Test func statusFollowsUseAndRevocation() {
        #expect(Self.invitation().status == .active)
        #expect(Self.invitation(usedBy: "h1").status == .used)
        #expect(Self.invitation(revokedAt: Self.now).status == .revoked)
        // Utilisée puis révoquée (impossible côté règles) : on la montre utilisée.
        #expect(Self.invitation(usedBy: "h1", revokedAt: Self.now).status == .used)
    }

    @Test func aUsedOrRevokedInvitationIsRefusedWithAClearMessage() throws {
        let used = try GroupRules.consuming(Self.invitation(), byHousehold: "h2", now: Self.now)
        #expect(used.usedBy == "h2")
        #expect(used.usedAt == Self.now)
        #expect(throws: GroupRules.usedInvitationError) { try GroupRules.consuming(used, byHousehold: "h3") }
        #expect(throws: GroupRules.revokedInvitationError) {
            try GroupRules.validateForJoining(Self.invitation(revokedAt: Self.now))
        }
        #expect(GroupRules.usedInvitationError.message.contains("déjà servi"))
        #expect(GroupRules.revokedInvitationError.message.contains("annulée"))
    }

    @Test func onlyTheCreatorRevokesAnUnusedInvitation() throws {
        let revoked = try GroupRules.revoking(Self.invitation(), in: Self.group(), byUserId: "creator", now: Self.now)
        #expect(revoked.status == .revoked)
        // Révoquer deux fois : sans effet.
        #expect(try GroupRules.revoking(revoked, in: Self.group(), byUserId: "creator") == revoked)
        #expect(throws: AppError.permissionDenied) {
            try GroupRules.revoking(Self.invitation(), in: Self.group(), byUserId: "helper")
        }
        #expect(throws: (any Error).self) {
            try GroupRules.revoking(Self.invitation(usedBy: "h1"), in: Self.group(), byUserId: "creator")
        }
    }

    @Test func theFixedCodeOpensOnlyAPublicGroup() {
        #expect(GroupRules.acceptsFixedCode(Self.group(isPublic: true), code: "pub-234"))
        #expect(!GroupRules.acceptsFixedCode(Self.group(isPublic: false), code: "PUB234"))
        #expect(!GroupRules.acceptsFixedCode(Self.group(isPublic: true, inviteCode: ""), code: ""))
    }

    @Test func activeInvitationsComeFirstThenTheNewest() {
        let old = GroupInvitation(code: "OLD234", groupId: "g1", createdBy: "creator", createdAt: Self.now)
        let new = GroupInvitation(code: "NEW234", groupId: "g1", createdBy: "creator", createdAt: Self.now.addingTimeInterval(60))
        let used = GroupInvitation(code: "USE234", groupId: "g1", createdBy: "creator",
                                   createdAt: Self.now.addingTimeInterval(120), usedBy: "h1")
        #expect(GroupRules.sortedForDisplay([used, old, new]).map(\.code) == ["NEW234", "OLD234", "USE234"])
    }

    // MARK: Décodage tolérant

    @Test func aGroupWithoutVisibilityIsPublic() throws {
        let json = #"{"id":"g","name":"Ancien","neighborhood":"Verdun","centerGeohash":"f25d","radiusMeters":1500,"coordinatorIds":[],"householdCount":3}"#
        let group = try JSONDecoder().decode(NeighborhoodGroup.self, from: Data(json.utf8))
        #expect(group.isPublic)
        #expect(group.inviteCode.isEmpty)
        #expect(group.createdBy == nil)

        let minimal = try JSONDecoder().decode(NeighborhoodGroup.self, from: Data(#"{"id":"g","name":"x"}"#.utf8))
        #expect(minimal.isPublic)
        #expect(minimal.coordinatorIds.isEmpty)
    }

    @Test func aPrivateGroupRoundTrips() throws {
        let group = Self.group()
        let decoded = try JSONDecoder().decode(NeighborhoodGroup.self, from: JSONEncoder().encode(group))
        #expect(decoded == group)
        #expect(!decoded.isPublic)
    }

    @Test func invitationRoundTrips() throws {
        let invitation = Self.invitation(usedBy: "h1")
        #expect(try JSONDecoder().decode(GroupInvitation.self, from: JSONEncoder().encode(invitation)) == invitation)
    }

    // MARK: Dépôt fake

    private static func repository() -> FakeGroupRepository {
        let data = FakeData.montreal
        return FakeGroupRepository(groups: data.groups, members: data.members, invitations: data.invitations)
    }

    @Test func privateGroupsAreNeverListed() async throws {
        let repository = Self.repository()
        let listed = try await repository.groups(inNeighborhood: nil)
        #expect(!listed.contains { $0.id == ID.villerayKitchen })
        #expect(try await repository.group(id: ID.villerayKitchen).isPublic == false)
        // Amina le voit dans ses groupes.
        #expect(try await repository.groups(ofHousehold: ID.aminaHousehold).contains { $0.id == ID.villerayKitchen })
    }

    @Test func aPrivateGroupOpensOnlyWithAnInvitationUsedOnce() async throws {
        let repository = Self.repository()
        await #expect(throws: AppError.permissionDenied) {
            try await repository.join(groupId: ID.villerayKitchen, householdId: "household-new")
        }
        let invitation = try await repository.createInvitation(forGroup: ID.villerayKitchen, byUserId: ID.amina)
        let before = try await repository.group(id: ID.villerayKitchen).householdCount
        let joined = try await repository.join(withCode: invitation.shareURL!.absoluteString, householdId: "household-new")
        #expect(joined.id == ID.villerayKitchen)
        #expect(joined.householdCount == before + 1)
        let members = try await repository.members(ofGroup: ID.villerayKitchen)
        #expect(members.contains { $0.householdId == "household-new" })
        // Seconde utilisation : refusée, avec le message clair.
        await #expect(throws: GroupRules.usedInvitationError) {
            try await repository.join(withCode: invitation.code, householdId: "household-other")
        }
        let listed = try await repository.invitations(ofGroup: ID.villerayKitchen, byUserId: ID.amina)
        #expect(listed.first { $0.code == invitation.code }?.usedBy == "household-new")
    }

    @Test func aRevokedInvitationNoLongerWorks() async throws {
        let repository = Self.repository()
        let invitation = try await repository.createInvitation(forGroup: ID.villerayKitchen, byUserId: ID.amina)
        let revoked = try await repository.revokeInvitation(code: invitation.code, ofGroup: ID.villerayKitchen, byUserId: ID.amina)
        #expect(revoked.status == .revoked)
        await #expect(throws: GroupRules.revokedInvitationError) {
            try await repository.join(withCode: invitation.code, householdId: "household-new")
        }
        // Les invitations de démo : utilisée et révoquée, refusées elles aussi.
        await #expect(throws: GroupRules.usedInvitationError) {
            try await repository.join(withCode: "VILR2M", householdId: "household-new")
        }
        await #expect(throws: GroupRules.revokedInvitationError) {
            try await repository.join(withCode: "VILX9P", householdId: "household-new")
        }
    }

    @Test func onlyTheCreatorManagesVisibilityAndInvitations() async throws {
        let repository = Self.repository()
        await #expect(throws: AppError.permissionDenied) {
            try await repository.setVisibility(isPublic: true, ofGroup: ID.villerayKitchen, byUserId: "user-karim")
        }
        await #expect(throws: AppError.permissionDenied) {
            try await repository.invitations(ofGroup: ID.villerayKitchen, byUserId: "user-karim")
        }
        await #expect(throws: AppError.permissionDenied) {
            try await repository.createInvitation(forGroup: ID.villerayKitchen, byUserId: "user-karim")
        }
        await #expect(throws: AppError.permissionDenied) {
            try await repository.revokeInvitation(code: "VIL4K7", ofGroup: ID.villerayKitchen, byUserId: "user-karim")
        }
        let opened = try await repository.setVisibility(isPublic: true, ofGroup: ID.villerayKitchen, byUserId: ID.amina)
        #expect(opened.isPublic)
        #expect(try await repository.groups(inNeighborhood: nil).contains { $0.id == ID.villerayKitchen })
    }

    @Test func aPublicGroupOpensWithItsFixedCode() async throws {
        let repository = Self.repository()
        let joined = try await repository.join(withCode: "ho-2026", householdId: "household-new")
        #expect(joined.id == ID.hochelaga)
        // Déjà membre : sans effet.
        let again = try await repository.join(withCode: "HO2026", householdId: "household-new")
        #expect(again.householdCount == joined.householdCount)
        await #expect(throws: GroupRules.unknownInviteCodeError) {
            try await repository.join(withCode: "ZZZ999", householdId: "household-new")
        }
        await #expect(throws: (any Error).self) {
            try await repository.join(withCode: "abc", householdId: "household-new")
        }
    }

    @Test func aMemberDoesNotBurnAnInvitation() async throws {
        let repository = Self.repository()
        _ = try await repository.join(withCode: "VIL4K7", householdId: ID.aminaHousehold)
        let invitations = try await repository.invitations(ofGroup: ID.villerayKitchen, byUserId: ID.amina)
        #expect(invitations.first { $0.code == "VIL4K7" }?.status == .active)
    }

    // MARK: ViewModels

    @Test @MainActor func creatorCreatesSharesAndRevokesInvitations() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let group = try await repositories.groups.group(id: ID.villerayKitchen)
        let model = GroupInvitationsViewModel(repositories: repositories, group: group, userId: ID.amina)
        await model.load()
        #expect(model.isPrivate)
        #expect(model.items.map(\.code) == ["VIL4K7", "VILX9P", "VILR2M"])
        #expect(model.activeCount == 1)

        let created = try #require(await model.create())
        #expect(model.lastCreated == created)
        #expect(model.items.first == created)
        #expect(model.activeCount == 2)
        let message = GroupInvitationsViewModel.shareMessage(groupName: group.name, invitation: created)
        #expect(message.contains("https://grenier.app/join/\(created.code)"))

        await model.revoke(created)
        #expect(model.lastCreated == nil)
        #expect(model.items.first { $0.code == created.code }?.status == .revoked)
        #expect(model.activeCount == 1)

        let opened = await model.setPrivate(false)
        #expect(opened?.isPublic == true)
        #expect(!model.isPrivate)
    }

    @Test @MainActor func someoneElseCannotManageInvitations() async {
        let repositories = AppRepositories.fake(behavior: .instant)
        let group = FakeData.montreal.groups.first { $0.id == ID.villerayKitchen }!
        let model = GroupInvitationsViewModel(repositories: repositories, group: group, userId: "user-karim")
        await model.load()
        #expect(model.state.error == .permissionDenied)
        #expect(await model.create() == nil)
        #expect(model.actionError == .permissionDenied)
    }

    @Test @MainActor func joinSheetExplainsAUsedInvitation() async throws {
        let model = JoinWithCodeViewModel(repositories: .fake(behavior: .instant), householdId: "household-voisin-9")
        #expect(!model.canJoin)
        model.input = "vil-r2m"
        #expect(model.code == "VILR2M")
        await model.join()
        #expect(model.joinedGroup == nil)
        #expect(model.errorMessage == GroupRules.usedInvitationError.message)
        model.inputChanged()
        #expect(model.errorMessage == nil)

        model.input = "https://grenier.app/join/VIL4K7"
        await model.join()
        #expect(model.joinedGroup?.id == ID.villerayKitchen)
    }

    @Test func publicGroupsAreSortedByDistance() throws {
        let origin = try #require(Geohash.center(of: "f25dv"))
        func group(_ id: String, _ geohash: String, isPublic: Bool = true) -> NeighborhoodGroup {
            NeighborhoodGroup(id: id, name: id, neighborhood: "n", centerGeohash: geohash, radiusMeters: 1_000,
                              coordinatorIds: [], householdCount: 1, isPublic: isPublic, inviteCode: "")
        }
        let far = group("far", "f25ej"), near = group("near", "f25dv"), unknown = group("unknown", "")
        let mine = group("mine", "f25ej"), hidden = group("hidden", "f25dv", isPublic: false)
        let items = GroupsViewModel.items(publicGroups: [unknown, far, near, mine, hidden], householdGroups: [mine],
                                          neighborhood: nil, origin: origin)
        #expect(items.map(\.id) == ["mine", "near", "far", "unknown"])
        #expect(items[1].distanceMeters! < items[2].distanceMeters!)
        #expect(items[3].distanceText == nil)
    }
}
