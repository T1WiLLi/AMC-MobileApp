import Foundation
import Testing
@testable import AMC_MobileApp

/// FB-22 (suite de T-159) : le propriétaire cède son rôle avant de partir, et tous les membres voient
/// en direct les changements du ménage (membres, propriétaire, demandes).
@MainActor
struct HouseholdOwnershipLiveTests {
    private static let shared = Household(
        id: "household-amina", name: "Famille Benali", size: 4, geohash: "f25du",
        userIds: ["amina", "karim"], ownerId: "amina",
        memberNames: ["amina": "Amina Benali", "karim": "Karim Benali"]
    )

    private static func user(_ id: String) -> AppUser {
        AppUser(id: id, displayName: id == "karim" ? "Karim Benali" : "Amina Benali", photoURL: nil, language: .french,
                roles: [.family], neighborhood: "Villeray", dietaryPreferences: [], seniorMode: false,
                householdId: "household-amina", vendorId: nil, onboardingCompleted: true)
    }

    private static func fixture() -> (AppRepositories, FakeUserRepository) {
        let users = FakeUserRepository(users: [user("amina"), user("karim")], households: [shared])
        var repositories = AppRepositories.empty()
        repositories.users = users
        return (repositories, users)
    }

    private static func model(_ userId: String, _ repositories: AppRepositories) -> HouseholdProfileViewModel {
        HouseholdProfileViewModel(repositories: repositories, privateStore: FakeHouseholdPrivateStore(),
                                  userId: userId, householdId: "household-amina")
    }

    private static func request(_ userId: String) -> HouseholdJoinRequest {
        HouseholdJoinRequest(householdId: "household-amina", userId: userId, displayName: "Nadia Benali",
                             createdAt: Date(timeIntervalSince1970: 2_000), status: .pending)
    }

    /// Attend qu'une condition devienne vraie (les flux du fake passent par l'acteur du dépôt).
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    // MARK: Règles pures

    @Test func ownerTransfersToAnotherMember() throws {
        let updated = try HouseholdMembership.transferringOwnership(to: "karim", in: Self.shared, byUserId: "amina")
        #expect(updated.ownerId == "karim")
        #expect(updated.userIds == Self.shared.userIds)
        #expect(updated.memberNames == Self.shared.memberNames)
    }

    @Test func onlyOwnerTransfersAndOnlyToAMember() {
        #expect(throws: AppError.permissionDenied) {
            try HouseholdMembership.transferringOwnership(to: "amina", in: Self.shared, byUserId: "karim")
        }
        #expect(throws: AppError.notFound) {
            try HouseholdMembership.transferringOwnership(to: "inconnu", in: Self.shared, byUserId: "amina")
        }
        #expect(throws: AppError.self) {
            try HouseholdMembership.transferringOwnership(to: "amina", in: Self.shared, byUserId: "amina")
        }
    }

    @Test func formerOwnerCanLeaveAfterTransfer() throws {
        #expect(throws: AppError.self) {
            try HouseholdMembership.removing("amina", from: Self.shared, byUserId: "amina")
        }
        let transferred = try HouseholdMembership.transferringOwnership(to: "karim", in: Self.shared, byUserId: "amina")
        let left = try HouseholdMembership.removing("amina", from: transferred, byUserId: "amina")
        #expect(left.userIds == ["karim"])
        #expect(left.ownerId == "karim")
    }

    // MARK: Dépôt fake

    @Test func repositoryTransfersOwnershipAndPendingRequestsMoveToNewOwner() async throws {
        let (_, users) = Self.fixture()
        try await users.requestToJoin(Self.request("nadia"))
        _ = try await users.transferOwnership(ofHousehold: "household-amina", to: "karim", byUserId: "amina")
        #expect(try await users.household(id: "household-amina").ownerId == "karim")
        #expect(try await users.joinRequests(ofHousehold: "household-amina", byUserId: "karim").map(\.userId) == ["nadia"])
        await #expect(throws: AppError.permissionDenied) {
            try await users.joinRequests(ofHousehold: "household-amina", byUserId: "amina")
        }
    }

    @Test func householdStreamEmitsEveryChange() async throws {
        let (_, users) = Self.fixture()
        var iterator = await users.observeHousehold(id: "household-amina").makeAsyncIterator()
        let value1 = try await iterator.next()?.userIds
        #expect(value1 == ["amina", "karim"])
        _ = try await users.removeMember("karim", fromHousehold: "household-amina", byUserId: "amina")
        let value2 = try await iterator.next()?.userIds
        #expect(value2 == ["amina"])
    }

    @Test func requestStreamEndsForFormerOwner() async throws {
        let (_, users) = Self.fixture()
        var iterator = await users.observeJoinRequests(ofHousehold: "household-amina", byUserId: "amina").makeAsyncIterator()
        let value3 = try await iterator.next()?.isEmpty
        #expect(value3 == true)
        try await users.requestToJoin(Self.request("nadia"))
        let value4 = try await iterator.next()?.map(\.userId)
        #expect(value4 == ["nadia"])
        _ = try await users.transferOwnership(ofHousehold: "household-amina", to: "karim", byUserId: "amina")
        do {
            _ = try await iterator.next()
            Issue.record("Le flux aurait dû se terminer en .permissionDenied")
        } catch {
            #expect(error as? AppError == .permissionDenied)
        }
    }

    // MARK: ViewModel « Mon ménage »

    @Test func ownerCannotLeaveBeforeTransferring() async {
        let (repositories, _) = Self.fixture()
        let amina = Self.model("amina", repositories)
        await amina.load()
        #expect(amina.mustTransferBeforeLeaving)
        await amina.leave()
        #expect(!amina.didLeave)
        #expect(amina.membershipError != nil)
    }

    @Test func transferThenLeave() async throws {
        let (repositories, users) = Self.fixture()
        let amina = Self.model("amina", repositories)
        await amina.load()
        let karim = try #require(amina.members.first { $0.id == "karim" })
        await amina.transferOwnership(to: karim)
        #expect(!amina.isOwner)
        #expect(amina.ownershipChangeCount == 1)
        #expect(amina.ownerName == "Karim Benali")
        await amina.leave()
        #expect(amina.didLeave)
        #expect(try await users.household(id: "household-amina").userIds == ["karim"])
    }

    @Test func otherMemberSeesNewRequestAndNewOwnerLive() async throws {
        let (repositories, users) = Self.fixture()
        let amina = Self.model("amina", repositories)
        let karim = Self.model("karim", repositories)
        await amina.load()
        await karim.load()
        let watchAmina = Task { await amina.observe() }
        let watchKarim = Task { await karim.observe() }
        defer { watchAmina.cancel(); watchKarim.cancel() }

        // Une demande arrive : la propriétaire la voit sans recharger.
        try await users.requestToJoin(Self.request("nadia"))
        try await eventually { amina.joinRequests.map(\.userId) == ["nadia"] }
        #expect(karim.joinRequests.isEmpty)

        // Amina cède son rôle : Karim devient propriétaire et voit la demande, Amina ne la voit plus.
        _ = try await users.transferOwnership(ofHousehold: "household-amina", to: "karim", byUserId: "amina")
        try await eventually { karim.isOwner && karim.joinRequests.map(\.userId) == ["nadia"] }
        try await eventually { !amina.isOwner && amina.joinRequests.isEmpty }
        #expect(karim.ownershipChangeCount >= 1)
    }

    @Test func removedMemberIsNotifiedLive() async throws {
        let (repositories, users) = Self.fixture()
        let karim = Self.model("karim", repositories)
        await karim.load()
        let watch = Task { await karim.observe() }
        defer { watch.cancel() }
        _ = try await users.removeMember("karim", fromHousehold: "household-amina", byUserId: "amina")
        try await eventually { karim.wasRemoved }
    }

    // MARK: Groupes du ménage en direct

    private static let jarry = NeighborhoodGroup(
        id: "group-jarry", name: "Parc Jarry", neighborhood: "Villeray", centerGeohash: "f25dvk",
        radiusMeters: 800, coordinatorIds: [], householdCount: 3, isPublic: true, inviteCode: "JARRY1"
    )

    @Test func householdGroupStreamFollowsJoinAndLeave() async throws {
        let groups = FakeGroupRepository(groups: [Self.jarry])
        var iterator = await groups.observeGroupIds(ofHousehold: "household-amina").makeAsyncIterator()
        let value5 = try await iterator.next()
        #expect(value5 == [])
        try await groups.join(groupId: "group-jarry", householdId: "household-amina")
        let value6 = try await iterator.next()
        #expect(value6 == ["group-jarry"])
        try await groups.leave(groupId: "group-jarry", householdId: "household-amina")
        let value7 = try await iterator.next()
        #expect(value7 == [])
    }

    @Test func otherMemberSeesGroupJoinedOnAnotherPhone() async throws {
        let groups = FakeGroupRepository(groups: [Self.jarry])
        var repositories = AppRepositories.empty()
        repositories.groups = groups
        // Karim regarde l'onglet Groupes ; Amina rejoint le groupe sur son téléphone (même ménage).
        let karim = GroupsViewModel(repositories: repositories, householdId: "household-amina")
        await karim.load()
        #expect(karim.myGroups.isEmpty)
        let watch = Task { await karim.observeHouseholdGroups() }
        defer { watch.cancel() }

        try await groups.join(groupId: "group-jarry", householdId: "household-amina")
        try await eventually { karim.myGroups.map(\.id) == ["group-jarry"] }
        #expect(karim.householdMembershipChangeCount == 1)

        try await groups.leave(groupId: "group-jarry", householdId: "household-amina")
        try await eventually { karim.myGroups.isEmpty }
    }

    @Test func cachedListIsReadAgainWhenAnotherMemberJoins() async throws {
        let base = FakeGroupRepository(groups: [Self.jarry])
        let cached = CachedGroupRepository(base: base, cache: RepositoryCache())
        #expect(try await cached.groups(ofHousehold: "household-amina").isEmpty)
        var iterator = await cached.observeGroupIds(ofHousehold: "household-amina").makeAsyncIterator()
        _ = try await iterator.next()
        // Écriture faite ailleurs (autre téléphone) : seule l'écoute peut vider le cache.
        try await base.join(groupId: "group-jarry", householdId: "household-amina")
        let value8 = try await iterator.next()
        #expect(value8 == ["group-jarry"])
        #expect(try await cached.groups(ofHousehold: "household-amina").map(\.id) == ["group-jarry"])
    }
}
