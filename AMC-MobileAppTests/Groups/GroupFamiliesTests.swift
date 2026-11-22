import Foundation
import Testing
@testable import AMC_MobileApp

/// T-191 : familles membres d'un groupe, retrait réservé au créateur (dépôt fake et ViewModel).
@MainActor
struct GroupFamiliesTests {
    private typealias ID = FakeData.ID
    /// Groupe privé créé par Amina : sa famille (coordonnatrice) et trois voisines.
    private static let groupId = ID.villerayKitchen
    private static let neighbor = "household-voisin-1"

    private func model(_ repositories: AppRepositories, householdId: String = ID.aminaHousehold,
                       userId: String? = ID.amina) -> GroupFamiliesViewModel {
        GroupFamiliesViewModel(repositories: repositories, groupId: Self.groupId, householdId: householdId, userId: userId)
    }

    @Test func listsTheMemberFamiliesWithMineFirst() async {
        let families = model(.fake(behavior: .instant))
        await families.load()
        let list = families.state.value ?? []
        #expect(list.count == 4)
        #expect(list.first?.householdId == ID.aminaHousehold)
        #expect(list.first?.isMine == true)
        #expect(list.dropFirst().allSatisfy { !$0.isMine })
        #expect(list.contains { $0.householdId == Self.neighbor && $0.name == "Voisins 1" })
    }

    @Test func creatorSeesRemovalOnOtherFamiliesButNeverOnHerOwn() async throws {
        let families = model(.fake(behavior: .instant))
        await families.load()
        #expect(families.isCreator)
        let list = try #require(families.state.value)
        for family in list {
            #expect(families.canRemove(family) == (family.householdId != ID.aminaHousehold))
        }
    }

    @Test func memberAndOutsiderNeverSeeRemoval() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        for (household, user) in [(Self.neighbor, "voisin-1"), ("household-etranger", "etranger")] {
            let families = model(repositories, householdId: household, userId: user)
            await families.load()
            #expect(!families.isCreator)
            let list = try #require(families.state.value)
            #expect(list.allSatisfy { !families.canRemove($0) })
        }
    }

    @Test func anotherCoordinatorIsNotTheCreator() async throws {
        // Le groupe a `createdBy` = Amina : un autre coordonnateur (même famille de rôle) ne retire personne.
        var data = FakeData.montreal
        let index = try #require(data.groups.firstIndex { $0.id == Self.groupId })
        data.groups[index].coordinatorIds = [ID.amina, "autre-coordo"]
        let groups = FakeGroupRepository(groups: data.groups, members: data.members, invitations: data.invitations)
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.groups = groups
        let families = model(repositories, householdId: Self.neighbor, userId: "autre-coordo")
        await families.load()
        #expect(!families.isCreator)
        let list = try #require(families.state.value)
        #expect(list.allSatisfy { !families.canRemove($0) })
    }

    @Test func removalUpdatesTheList() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let families = model(repositories)
        await families.load()
        let target = try #require(families.state.value?.first { $0.householdId == Self.neighbor })

        #expect(await families.remove(target))

        let list = try #require(families.state.value)
        #expect(list.count == 3)
        #expect(!list.contains { $0.householdId == Self.neighbor })
        #expect(families.removalCount == 1)
        #expect(families.actionError == nil)
    }

    @Test func creatorCannotRemoveOwnFamily() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let families = model(repositories)
        await families.load()
        let mine = try #require(families.state.value?.first { $0.isMine })

        #expect(await families.remove(mine) == false)

        #expect(families.state.value?.count == 4)
        let members = try await repositories.groups.members(ofGroup: Self.groupId)
        #expect(members.contains { $0.householdId == ID.aminaHousehold })
    }

    @Test func memberCannotRemoveThroughTheViewModel() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let families = model(repositories, householdId: "household-voisin-2", userId: "voisin-2")
        await families.load()
        let target = try #require(families.state.value?.first { $0.householdId == Self.neighbor })
        #expect(await families.remove(target) == false)
        #expect(try await repositories.groups.members(ofGroup: Self.groupId).count == 4)
    }

    @Test func emptyAndFailedStates() async throws {
        // Un seul membre retiré à la fois : on vide le groupe avec le dépôt, puis on recharge.
        let repositories = AppRepositories.fake(behavior: .instant)
        for member in try await repositories.groups.members(ofGroup: Self.groupId) where member.householdId != ID.aminaHousehold {
            try await repositories.groups.removeHousehold(member.householdId, fromGroup: Self.groupId, byUserId: ID.amina,
                                                          creatorHouseholdId: ID.aminaHousehold)
        }
        try await repositories.groups.leave(groupId: Self.groupId, householdId: ID.aminaHousehold)
        let emptied = model(repositories)
        await emptied.load()
        #expect(emptied.state == .empty)

        let missing = GroupFamiliesViewModel(repositories: repositories, groupId: "group-inconnu",
                                             householdId: ID.aminaHousehold, userId: ID.amina)
        await missing.load()
        #expect(missing.state.error != nil)
    }

    // MARK: - Dépôt fake

    @Test func fakeRepositoryRemovesTheFamilyAndDecrementsTheCount() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let before = try await repositories.groups.group(id: Self.groupId)

        try await repositories.groups.removeHousehold(Self.neighbor, fromGroup: Self.groupId, byUserId: ID.amina,
                                                      creatorHouseholdId: ID.aminaHousehold)

        let members = try await repositories.groups.members(ofGroup: Self.groupId)
        #expect(!members.contains { $0.householdId == Self.neighbor })
        #expect(try await repositories.groups.group(id: Self.groupId).householdCount == before.householdCount - 1)
        #expect(try await repositories.groups.groups(ofHousehold: Self.neighbor).allSatisfy { $0.id != Self.groupId })
    }

    @Test func fakeRepositoryRefusesEveryoneButTheCreatorAndNeverHerFamily() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        // Un membre.
        await #expect(throws: AppError.permissionDenied) {
            try await repositories.groups.removeHousehold("household-voisin-2", fromGroup: Self.groupId, byUserId: "voisin-1",
                                                          creatorHouseholdId: Self.neighbor)
        }
        // Le créateur sur sa propre famille.
        await #expect(throws: AppError.permissionDenied) {
            try await repositories.groups.removeHousehold(ID.aminaHousehold, fromGroup: Self.groupId, byUserId: ID.amina,
                                                          creatorHouseholdId: ID.aminaHousehold)
        }
        // Groupe inconnu.
        await #expect(throws: AppError.notFound) {
            try await repositories.groups.removeHousehold(Self.neighbor, fromGroup: "group-inconnu", byUserId: ID.amina,
                                                          creatorHouseholdId: ID.aminaHousehold)
        }
        #expect(try await repositories.groups.members(ofGroup: Self.groupId).count == 4)
    }

    @Test func removingANonMemberChangesNothing() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        let before = try await repositories.groups.group(id: Self.groupId).householdCount
        try await repositories.groups.removeHousehold("household-voisin-9", fromGroup: Self.groupId, byUserId: ID.amina,
                                                      creatorHouseholdId: ID.aminaHousehold)
        #expect(try await repositories.groups.group(id: Self.groupId).householdCount == before)
    }

    // MARK: - Règles du domaine

    @Test func domainRule() throws {
        let group = try #require(FakeData.montreal.groups.first { $0.id == Self.groupId })
        #expect(GroupRules.canRemoveHousehold(Self.neighbor, byUserId: ID.amina, creatorHouseholdId: ID.aminaHousehold, from: group))
        #expect(!GroupRules.canRemoveHousehold(ID.aminaHousehold, byUserId: ID.amina, creatorHouseholdId: ID.aminaHousehold, from: group))
        #expect(!GroupRules.canRemoveHousehold(Self.neighbor, byUserId: "voisin-1", creatorHouseholdId: Self.neighbor, from: group))
        #expect(!GroupRules.canRemoveHousehold(Self.neighbor, byUserId: nil, creatorHouseholdId: nil, from: group))
    }
}
