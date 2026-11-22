import Foundation
import Testing
@testable import AMC_MobileApp

/// T-181 : l'hôte (Amina, « Chez Amina, rue Jarry ») remet les parts d'une commande arrivée (livrée).
@MainActor
struct HostPickupViewModelTests {
    private typealias ID = FakeData.ID

    private func makeModel(status: GroupOrder.Status = .delivered, userId: String = ID.amina) -> HostPickupViewModel {
        var data = FakeData.montreal
        data.groupOrders[0].status = status
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        return HostPickupViewModel(repositories: repos, userId: userId, householdId: ID.aminaHousehold,
                                   groupId: ID.saintMichel)
    }

    @Test func listsSharesOfClosedOrderAtHostPoint() async throws {
        let model = makeModel(status: .closed)
        await model.load()
        let station = try #require(model.selectedStation)
        #expect(station.order.id == ID.potatoOrder)
        #expect(model.checklist?.totalCount == 11)
        #expect(model.checklist?.pickedUpCount == 0)
    }

    @Test func orderStillOpenShowsNothing() async {
        let model = makeModel(status: .reached)
        await model.load()
        #expect(model.state.value == nil)
    }

    /// Démo (`FakeData.demo`, mode fake de l'app) : la commande de pommes de Villeray est livrée chez Amina,
    /// « Remettre les parts » n'est jamais vide.
    @Test func demoDataHasADeliveredOrderAtAminasPoint() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: .demo)
        let model = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel)
        await model.load()
        let station = try #require(model.selectedStation)
        #expect(station.order.id == FakeData.HostDemoID.deliveredOrder)
        #expect(station.productName == "Pommes Cortland")
        #expect(model.checklist?.totalCount == 3)
        #expect(model.checklist?.pickedUpCount == 1)
    }

    /// Le code tapé dans « Entrer le code » (repli sans caméra) suit le même chemin que le scan.
    @Test func typedFamilyCodeOfDemoOrderMarksShare() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: .demo)
        let model = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel)
        await model.load()
        let household = "household-voisin-1"
        let typed = "  " + PickupDesk.memberCode(ShareAllocator.qrCode(orderId: FakeData.HostDemoID.deliveredOrder, householdId: household),
                                                 memberId: "user-voisin-1") + "\n"
        await model.scan(typed)
        #expect(model.outcome?.result.isSuccess == true)
        let stored = try await repos.groupOrders.shares(ofGroupOrder: FakeData.HostDemoID.deliveredOrder).first { $0.householdId == household }
        #expect(stored?.isPickedUp == true)
        #expect(stored?.pickedUpBy == "user-voisin-1")
    }

    /// Côté famille : Amina est l'hôte de son point, son écran QR ne dit pas « Montre ce code à Amina ».
    @Test func hostSeesGenericInstructionOnHerOwnCode() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        let viewModel = PickupViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel,
                                        userId: ID.amina)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.hostFirstName == nil)
    }

    @Test func nonHostSeesNothing() async {
        let model = makeModel(userId: "user-karim-2")
        await model.load()
        #expect(model.state.value == nil)
    }

    @Test func tapMarksPickedUpOnce() async throws {
        let model = makeModel()
        await model.load()
        let first = try #require(model.checklist?.entries.first)
        await model.markPickedUp(householdId: first.householdId, in: ID.potatoOrder)
        #expect(model.outcome?.result.isSuccess == true)
        #expect(model.successes == 1)
        #expect(model.checklist?.pickedUpCount == 1)
        // Un deuxième tap ne remet pas la part une deuxième fois.
        await model.markPickedUp(householdId: first.householdId, in: ID.potatoOrder)
        #expect(model.successes == 1)
        #expect(model.rejections == 1)
        if case .alreadyPickedUp = try #require(model.outcome?.result) {} else { Issue.record("attendu : déjà cueillie") }
    }

    @Test func scanningFamilyCodeMarksShare() async throws {
        let model = makeModel()
        await model.load()
        let household = try #require(model.checklist?.entries.last).householdId
        let code = PickupDesk.memberCode(ShareAllocator.qrCode(orderId: ID.potatoOrder, householdId: household),
                                         memberId: "user-membre")
        await model.scan(code)
        #expect(model.outcome?.result.isSuccess == true)
        #expect(model.state.value?.stations.first?.shares.first { $0.householdId == household }?.isPickedUp == true)
    }

    @Test func garbageCodeIsRejected() async {
        let model = makeModel()
        await model.load()
        await model.scan("https://example.com")
        #expect(model.outcome?.result == .unknownCode)
        #expect(model.rejections == 1)
    }
}
