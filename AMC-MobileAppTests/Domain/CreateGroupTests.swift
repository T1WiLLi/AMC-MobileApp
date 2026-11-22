// CreateGroupTests.swift
// B-059 : créer un groupe depuis l'app. Règle de limite (RQ-030), dépôt fake (groupe, créateur coordonnateur
// et premier membre ensemble), ViewModel du formulaire (préremplissage, validation, création, limite).

import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct CreateGroupTests {
    private typealias ID = FakeData.ID

    private static func draft(name: String = "Voisins de la rue Jarry", isPublic: Bool = true) -> GroupRules.Draft {
        GroupRules.Draft(name: name, neighborhood: "Villeray", centerGeohash: "f25dvk7", radiusMeters: 1_200, isPublic: isPublic)
    }

    /// T-180 : Amina est aussi membre de Parc-Extension (parcours de démo) ; ces tests partent d'Amina dans
    /// 2 groupes (limite de 3 pas atteinte), on retire donc son entrée de Parc-Extension.
    private static var data: FakeData {
        var data = FakeData.montreal
        data.members[ID.parcExtension] = data.members[ID.parcExtension]?.filter { $0.householdId != ID.aminaHousehold }
        return data
    }

    private static func repository() -> FakeGroupRepository {
        let data = Self.data
        return FakeGroupRepository(groups: data.groups, members: data.members, invitations: data.invitations)
    }

    // MARK: Domaine

    @Test func aHouseholdCreatesUpToThreeGroups() throws {
        #expect(GroupRules.canCreateGroup(householdGroupIds: []))
        #expect(GroupRules.canCreateGroup(householdGroupIds: ["a", "b"]))
        #expect(!GroupRules.canCreateGroup(householdGroupIds: ["a", "b", "c"]))
        #expect(throws: AppError.self) { try GroupRules.requireRoomToCreate(householdGroupIds: ["a", "b", "c"]) }
    }

    // MARK: Dépôt fake

    @Test func theCreatorBecomesCoordinatorAndFirstMember() async throws {
        let repository = Self.repository()
        let group = try await repository.createGroup(Self.draft(), byUserId: ID.amina, householdId: ID.aminaHousehold)
        #expect(group.name == "Voisins de la rue Jarry")
        #expect(group.createdBy == ID.amina)
        #expect(group.coordinatorIds == [ID.amina])
        #expect(group.householdCount == 1)
        #expect(group.radiusMeters == 1_200)
        #expect(GroupRules.isValidInviteCode(group.inviteCode))
        let members = try await repository.members(ofGroup: group.id)
        #expect(members.map(\.householdId) == [ID.aminaHousehold])
        #expect(members.first?.role == .coordinator)
        #expect(try await repository.groups(ofHousehold: ID.aminaHousehold).contains { $0.id == group.id })
        #expect(try await repository.groups(inNeighborhood: nil).contains { $0.id == group.id })
    }

    @Test func aPrivateGroupIsCreatedButNotListed() async throws {
        let repository = Self.repository()
        let group = try await repository.createGroup(Self.draft(isPublic: false), byUserId: ID.amina, householdId: ID.aminaHousehold)
        #expect(!group.isPublic)
        #expect(try await !repository.groups(inNeighborhood: nil).contains { $0.id == group.id })
        // Sa créatrice gère ses invitations.
        let invitation = try await repository.createInvitation(forGroup: group.id, byUserId: ID.amina)
        #expect(invitation.groupId == group.id)
    }

    @Test func aFourthGroupIsRefused() async throws {
        let repository = Self.repository()
        // Amina fait déjà partie de 2 groupes de démo.
        #expect(try await repository.groups(ofHousehold: ID.aminaHousehold).count == 2)
        _ = try await repository.createGroup(Self.draft(), byUserId: ID.amina, householdId: ID.aminaHousehold)
        await #expect(throws: AppError.self) {
            try await repository.createGroup(Self.draft(name: "Encore un groupe"), byUserId: ID.amina, householdId: ID.aminaHousehold)
        }
        #expect(try await repository.groups(ofHousehold: ID.aminaHousehold).count == 3)
    }

    @Test func anInvalidDraftIsRefused() async throws {
        let repository = Self.repository()
        await #expect(throws: AppError.self) {
            try await repository.createGroup(Self.draft(name: "A"), byUserId: ID.amina, householdId: ID.aminaHousehold)
        }
        var tooWide = Self.draft()
        tooWide.radiusMeters = 2_500
        await #expect(throws: AppError.self) {
            try await repository.createGroup(tooWide, byUserId: ID.amina, householdId: ID.aminaHousehold)
        }
    }

    // MARK: ViewModel

    private static func viewModel(householdId: String = ID.aminaHousehold) -> CreateGroupViewModel {
        CreateGroupViewModel(repositories: .fake(behavior: .instant, data: Self.data), userId: ID.amina, householdId: householdId)
    }

    @Test func formIsPrefilledFromTheHousehold() async {
        let model = Self.viewModel()
        await model.load()
        #expect(model.neighborhood == "Saint-Michel")
        let origin = Geohash.center(of: "f25dv")
        #expect(model.center == origin)
        #expect(model.householdGroupCount == 2)
        #expect(model.hasRoomForAnotherGroup)
    }

    /// T-188 : le bouton « Chez moi » de la carte ramène le centre sur le ménage ; inactif tant qu'on n'a pas bougé.
    @Test func homeCenterFollowsTheHousehold() async throws {
        let model = Self.viewModel()
        #expect(model.homeCenter == nil && model.isCenteredAtHome)
        await model.load()
        let home = try #require(model.homeCenter)
        #expect(model.center == home && model.isCenteredAtHome)
        model.center = Geohash.Coordinate(latitude: home.latitude + 0.01, longitude: home.longitude)
        #expect(!model.isCenteredAtHome)
    }

    @Test func nameCountIgnoresSurroundingSpaces() {
        let model = Self.viewModel()
        model.name = "  Voisins  "
        #expect(model.trimmedNameCount == 7)
    }

    @Test func createIsEnabledOnceTheFormIsValid() async {
        let model = Self.viewModel()
        await model.load()
        #expect(!model.canCreate)
        #expect(model.validationMessage != nil)
        model.name = "Voisins de la rue Jarry"
        #expect(model.canCreate)
        #expect(model.draft.radiusMeters == 1_500)
        #expect(model.draft.centerGeohash.count == 7)
    }

    @Test func createReturnsTheGroup() async {
        let model = Self.viewModel()
        await model.load()
        model.name = "Voisins de la rue Jarry"
        model.isPublic = false
        model.radiusMeters = 2_000
        await model.create()
        #expect(model.submitError == nil)
        #expect(model.createdGroup?.isPublic == false)
        #expect(model.createdGroup?.radiusMeters == 2_000)
        #expect(model.createdGroup?.creatorId == ID.amina)
    }

    @Test func theLimitBlocksTheForm() async {
        let repositories = AppRepositories.fake(behavior: .instant, data: Self.data)
        _ = try? await repositories.groups.createGroup(Self.draft(), byUserId: ID.amina, householdId: ID.aminaHousehold)
        let model = CreateGroupViewModel(repositories: repositories, userId: ID.amina, householdId: ID.aminaHousehold)
        await model.load()
        model.name = "Un quatrième groupe"
        #expect(model.householdGroupCount == 3)
        #expect(!model.hasRoomForAnotherGroup)
        #expect(!model.canCreate)
    }

    @Test(arguments: [(1_000, "1 km"), (1_200, "1,2 km"), (1_500, "1,5 km"), (2_000, "2 km")])
    func radiusIsShortAndFrench(meters: Int, text: String) {
        #expect(CreateGroupViewModel.radiusText(meters: meters) == text)
    }
}
