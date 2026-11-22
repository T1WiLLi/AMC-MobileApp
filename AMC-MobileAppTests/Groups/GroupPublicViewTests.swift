import Foundation
import Testing
@testable import AMC_MobileApp

/// T-172 (FB-13) : un ménage qui n'est pas membre voit la fiche publique du groupe au lieu de « Action non permise ».
/// Les règles Firestore réservent `groupOrders/{id}/shares` aux membres : `SharesForMembersOnly` reproduit ce refus.
@MainActor
struct GroupPublicViewTests {
    private typealias ID = FakeData.ID
    private static let visitor = "household-visiteur"

    private func viewModel(householdId: String, groupId: String) -> GroupDetailViewModel {
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.groupOrders = SharesForMembersOnly(base: repositories.groupOrders, groups: repositories.groups,
                                                        reader: householdId)
        return GroupDetailViewModel(repositories: repositories, householdId: householdId, groupId: groupId)
    }

    // MARK: Routage membre / visiteur

    @Test func audienceRoutesMembersToTheFullSheetAndVisitorsToThePublicOne() {
        typealias Audience = GroupDetailViewModel.Audience
        #expect(Audience(isMember: true, isPublic: true) == .member)
        #expect(Audience(isMember: true, isPublic: false) == .member)
        #expect(Audience(isMember: false, isPublic: true) == .publicVisitor)
        #expect(Audience(isMember: false, isPublic: false) == .privateVisitor)
        #expect(Audience.member.isMember)
        #expect(!Audience.publicVisitor.isMember)
        #expect(!Audience.privateVisitor.isMember)
    }

    @Test func visitorOfAPublicGroupLoadsItsPublicSheet() async throws {
        let model = viewModel(householdId: Self.visitor, groupId: ID.saintMichel)
        await model.load()

        // Avant : la lecture des parts était refusée et la fiche affichait « Action non permise ».
        let content = try #require(model.state.value)
        #expect(content.audience == .publicVisitor)
        #expect(!content.isMember)
        #expect(content.group.householdCount == 12)
        #expect(content.openOrders.map(\.offer.id) == [ID.potatoOffer])
        #expect(content.openOrders.allSatisfy { $0.myShareQuantity == 0 })
        #expect(content.coordinatorName == "Famille Benali")
    }

    @Test func visitorOfAPrivateGroupIsAskedForAnInvitation() async throws {
        let model = viewModel(householdId: Self.visitor, groupId: ID.villerayKitchen)
        await model.load()
        let content = try #require(model.state.value)
        #expect(content.audience == .privateVisitor)
        #expect(GroupPublicContent.invitationRequest(for: content.group).contains("Cuisine collective Villeray"))
    }

    @Test func memberStillGetsTheFullSheetWithHisShares() async throws {
        let model = viewModel(householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await model.load()
        let content = try #require(model.state.value)
        #expect(content.audience == .member)
        #expect(content.openOrders.map(\.offer.id) == [ID.potatoOffer])
    }

    @Test func joiningSwitchesTheVisitorToTheMemberSheet() async throws {
        let model = viewModel(householdId: Self.visitor, groupId: ID.hochelaga)
        await model.load()
        #expect(model.state.value?.audience == .publicVisitor)
        let before = try #require(model.state.value?.group.householdCount)

        await model.join()
        #expect(model.actionError == nil)
        #expect(model.state.value?.audience == .member)
        #expect(model.state.value?.group.householdCount == before + 1)
    }

    @Test func neighborhoodSlugIsShownAsAName() {
        #expect(NeighborhoodName.display("hochelaga-maisonneuve") == "Hochelaga-Maisonneuve")
        #expect(NeighborhoodName.display("Saint-Michel") == "Saint-Michel")
        #expect(NeighborhoodName.display("") == nil)
    }
}

/// Doublure : les parts d'une commande ne se lisent que par un membre du groupe (comme `firestore.rules`).
/// `reader` est le ménage connecté (Firestore le connaît par `request.auth`).
private struct SharesForMembersOnly: GroupOrderRepository {
    let base: any GroupOrderRepository
    let groups: any GroupRepository
    let reader: String

    private func isReaderMember(of order: GroupOrder) async -> Bool {
        let members = (try? await groups.members(ofGroup: order.groupId)) ?? []
        return members.contains { $0.householdId == reader }
    }

    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder] { try await base.groupOrders(ofGroup: groupId) }
    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder] { try await base.groupOrders(ofOffer: offerId) }
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder {
        try await base.openGroupOrder(groupId: groupId, offerId: offerId)
    }
    func groupOrder(id: String) async throws -> GroupOrder { try await base.groupOrder(id: id) }
    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share] {
        let order = try await base.groupOrder(id: groupOrderId)
        guard await isReaderMember(of: order) else { throw AppError.permissionDenied }
        return try await base.shares(ofGroupOrder: groupOrderId)
    }
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder {
        try await base.setShare(quantity: quantity, householdId: householdId, groupOrderId: groupOrderId)
    }
    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error> {
        await base.observeGroupOrder(id: id)
    }
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder {
        try await base.setPickupPoint(pickupPointId, slots: slots, groupOrderId: groupOrderId)
    }
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share {
        try await base.reservePickupSlot(start: start, householdId: householdId, groupOrderId: groupOrderId)
    }
}
