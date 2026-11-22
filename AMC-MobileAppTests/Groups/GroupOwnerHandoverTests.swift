import Foundation
import Testing
@testable import AMC_MobileApp

/// T-193 : le créateur quitte son groupe et le confie au co-coordonnateur le plus ancien, sinon au membre le plus ancien.
@MainActor
struct GroupOwnerHandoverTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 86_400

    private static func member(_ id: String, _ role: GroupMember.Role, daysAgo: Double) -> GroupMember {
        GroupMember(householdId: id, role: role, joinedAt: now.addingTimeInterval(-daysAgo * day))
    }

    // MARK: - Choix de l'héritier (domaine)

    @Test func oldestCoordinatorInheritsEvenIfAMemberIsOlder() {
        let members = [
            Self.member("creator", .coordinator, daysAgo: 50),
            Self.member("old-member", .member, daysAgo: 40),
            Self.member("coord-recent", .coordinator, daysAgo: 5),
            Self.member("coord-old", .coordinator, daysAgo: 20),
        ]
        #expect(GroupRules.heir(among: members, leaving: "creator")?.householdId == "coord-old")
    }

    @Test func oldestMemberInheritsWhenThereIsNoOtherCoordinator() {
        let members = [
            Self.member("creator", .coordinator, daysAgo: 50),
            Self.member("recent", .member, daysAgo: 3),
            Self.member("oldest", .member, daysAgo: 30),
        ]
        #expect(GroupRules.heir(among: members, leaving: "creator")?.householdId == "oldest")
    }

    @Test func nobodyInheritsWhenTheCreatorIsAlone() {
        #expect(GroupRules.heir(among: [Self.member("creator", .coordinator, daysAgo: 1)], leaving: "creator") == nil)
        #expect(GroupRules.heir(among: [], leaving: "creator") == nil)
    }

    @Test func theLeavingHouseholdIsNeverItsOwnHeir() {
        // Le créateur est le coordonnateur le plus ancien : il est exclu du choix.
        let members = [Self.member("creator", .coordinator, daysAgo: 90), Self.member("only", .member, daysAgo: 1)]
        #expect(GroupRules.heir(among: members, leaving: "creator")?.householdId == "only")
    }

    @Test func tiesAreBrokenByHouseholdIdWhateverTheListOrder() {
        let members = [Self.member("b", .member, daysAgo: 10), Self.member("a", .member, daysAgo: 10)]
        #expect(GroupRules.heir(among: members, leaving: "creator")?.householdId == "a")
        #expect(GroupRules.heir(among: members.reversed(), leaving: "creator")?.householdId == "a")
    }

    @Test func handingOverUpdatesOwnerAndCoordinatorsWithoutDuplicates() {
        let group = NeighborhoodGroup(id: "g", name: "Groupe", neighborhood: "x", centerGeohash: "f25du", radiusMeters: 1_000,
                                      coordinatorIds: ["creator", "heir", "other"], householdCount: 3,
                                      isPublic: true, inviteCode: "", createdBy: "creator")
        let updated = GroupRules.handingOver(group, from: "creator", to: "heir")
        #expect(updated.createdBy == "heir")
        #expect(Set(updated.coordinatorIds) == ["heir", "other"])
        #expect(updated.coordinatorIds.count == 2)
    }

    // MARK: - Sortie du créateur (dépôt fake)

    private static let groupId = "g-passation"

    private static func repository(coordinatorIds: [String] = ["creator-user"]) -> FakeGroupRepository {
        let group = NeighborhoodGroup(id: groupId, name: "Groupe", neighborhood: "villeray", centerGeohash: "f25du",
                                      radiusMeters: 1_000, coordinatorIds: coordinatorIds, householdCount: 3,
                                      isPublic: true, inviteCode: "", createdBy: "creator-user")
        let members = [
            member("household-creator", .coordinator, daysAgo: 60),
            member("household-old", .member, daysAgo: 30),
            member("household-new", .member, daysAgo: 2),
        ]
        return FakeGroupRepository(groups: [group], members: [groupId: members])
    }

    @Test func creatorLeavingHandsTheGroupToTheHeir() async throws {
        let repository = Self.repository()
        let heir = GroupRules.Handover(householdId: "household-old", userId: "old-user")

        try await repository.leave(groupId: Self.groupId, householdId: "household-creator",
                                   byUserId: "creator-user", handingOverTo: heir)

        let group = try await repository.group(id: Self.groupId)
        #expect(group.createdBy == "old-user")
        #expect(group.coordinatorIds == ["old-user"])
        #expect(group.householdCount == 2)
        let members = try await repository.members(ofGroup: Self.groupId)
        #expect(!members.contains { $0.householdId == "household-creator" })
        #expect(members.first { $0.householdId == "household-old" }?.role == .coordinator)
        #expect(members.first { $0.householdId == "household-new" }?.role == .member)
        // L'héritier peut maintenant gérer le groupe ; l'ancien créateur non.
        #expect(GroupRules.isCreator("old-user", of: group))
        #expect(!GroupRules.isCreator("creator-user", of: group))
    }

    @Test func existingCoordinatorHeirKeepsASingleCoordinatorEntry() async throws {
        let repository = Self.repository(coordinatorIds: ["creator-user", "old-user"])
        let heir = GroupRules.Handover(householdId: "household-old", userId: "old-user")
        try await repository.leave(groupId: Self.groupId, householdId: "household-creator",
                                   byUserId: "creator-user", handingOverTo: heir)
        #expect(try await repository.group(id: Self.groupId).coordinatorIds == ["old-user"])
    }

    @Test func lastMemberLeavesLikeBeforeAndTheGroupStaysWithoutMembers() async throws {
        let group = NeighborhoodGroup(id: Self.groupId, name: "Groupe", neighborhood: "villeray", centerGeohash: "f25du",
                                      radiusMeters: 1_000, coordinatorIds: ["creator-user"], householdCount: 1,
                                      isPublic: true, inviteCode: "", createdBy: "creator-user")
        let repository = FakeGroupRepository(groups: [group],
                                             members: [Self.groupId: [Self.member("household-creator", .coordinator, daysAgo: 1)]])
        try await repository.leave(groupId: Self.groupId, householdId: "household-creator",
                                   byUserId: "creator-user", handingOverTo: nil)
        #expect(try await repository.members(ofGroup: Self.groupId).isEmpty)
        let after = try await repository.group(id: Self.groupId)
        #expect(after.householdCount == 0)
        #expect(after.createdBy == "creator-user")
    }

    @Test func onlyTheCreatorCanLeaveWithAHandover() async throws {
        let repository = Self.repository()
        let heir = GroupRules.Handover(householdId: "household-new", userId: "new-user")
        await #expect(throws: AppError.permissionDenied) {
            try await repository.leave(groupId: Self.groupId, householdId: "household-old",
                                       byUserId: "old-user", handingOverTo: heir)
        }
        #expect(try await repository.members(ofGroup: Self.groupId).count == 3)
    }

    @Test func theHeirMustStillBeAMember() async throws {
        let repository = Self.repository()
        let stranger = GroupRules.Handover(householdId: "household-etranger", userId: "stranger")
        await #expect(throws: AppError.notFound) {
            try await repository.leave(groupId: Self.groupId, householdId: "household-creator",
                                       byUserId: "creator-user", handingOverTo: stranger)
        }
        let group = try await repository.group(id: Self.groupId)
        #expect(group.createdBy == "creator-user")
        #expect(group.householdCount == 3)
    }

    // MARK: - Confirmation (ViewModel)

    private func viewModel(heirHousehold: Household?) -> (GroupDetailViewModel, AppRepositories) {
        var repositories = AppRepositories.fake(behavior: .instant)
        if let heirHousehold {
            repositories.users = FakeUserRepository(users: [], households: [heirHousehold])
        }
        let model = GroupDetailViewModel(repositories: repositories, householdId: FakeData.ID.aminaHousehold,
                                         groupId: FakeData.ID.villerayKitchen, userId: FakeData.ID.amina)
        return (model, repositories)
    }

    @Test func confirmationNamesTheFamilyThatWillOwnTheGroup() async throws {
        // Villeray : Amina (coordonnatrice) + 3 voisins arrivés en même temps ; « household-voisin-1 » passe en premier.
        let diallo = Household(id: "household-voisin-1", name: "Famille Diallo", size: 3, geohash: "f25dv",
                               userIds: ["diallo-user"], ownerId: "diallo-user")
        let (model, repositories) = viewModel(heirHousehold: diallo)
        await model.load()
        await model.prepareLeave()
        #expect(model.succession == .heir(familyName: "Famille Diallo",
                                          handover: GroupRules.Handover(householdId: "household-voisin-1", userId: "diallo-user")))
        #expect(model.successionMessage?.contains("Famille Diallo") == true)

        await model.leave()

        let group = try await repositories.groups.group(id: FakeData.ID.villerayKitchen)
        #expect(group.createdBy == "diallo-user")
        #expect(model.state.value?.isMember == false)
    }

    @Test func confirmationSaysWhenNobodyWillInherit() async throws {
        let repositories = AppRepositories.fake(behavior: .instant)
        for member in try await repositories.groups.members(ofGroup: FakeData.ID.villerayKitchen)
        where member.householdId != FakeData.ID.aminaHousehold {
            try await repositories.groups.removeHousehold(member.householdId, fromGroup: FakeData.ID.villerayKitchen,
                                                          byUserId: FakeData.ID.amina,
                                                          creatorHouseholdId: FakeData.ID.aminaHousehold)
        }
        let model = GroupDetailViewModel(repositories: repositories, householdId: FakeData.ID.aminaHousehold,
                                         groupId: FakeData.ID.villerayKitchen, userId: FakeData.ID.amina)
        await model.load()
        await model.prepareLeave()
        #expect(model.succession == .nobody)
        #expect(model.successionMessage != nil)

        await model.leave()
        #expect(try await repositories.groups.members(ofGroup: FakeData.ID.villerayKitchen).isEmpty)
    }

    @Test func aSimpleMemberGetsNoSuccessionMessage() async {
        let repositories = AppRepositories.fake(behavior: .instant)
        let model = GroupDetailViewModel(repositories: repositories, householdId: "household-voisin-1",
                                         groupId: FakeData.ID.villerayKitchen, userId: "voisin-1")
        await model.load()
        await model.prepareLeave()
        #expect(model.succession == nil)
        #expect(model.successionMessage == nil)
    }
}
