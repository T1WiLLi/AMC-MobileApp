import Foundation
import Testing
@testable import AMC_MobileApp

/// T-181 : l'hôte (Amina, « Chez Amina, rue Jarry ») remet les parts d'une commande arrivée (livrée).
@MainActor
struct HostPickupViewModelTests {
    private typealias ID = FakeData.ID

    private func makeModel(status: GroupOrder.Status = .delivered, userId: String = ID.amina) -> HostPickupViewModel {
        makeModelAndRepositories(status: status, userId: userId).model
    }

    private func makeModelAndRepositories(
        status: GroupOrder.Status = .delivered, userId: String = ID.amina
    ) -> (model: HostPickupViewModel, repositories: AppRepositories) {
        var data = FakeData.montreal
        data.groupOrders[0].status = status
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let model = HostPickupViewModel(repositories: repos, userId: userId, householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel)
        return (model, repos)
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
        // La famille ouvre son code (jeton privé créé) ; l'hôte le tape.
        let familyCode = try await repos.groupOrders.pickupCode(householdId: household, groupOrderId: FakeData.HostDemoID.deliveredOrder)
        let typed = "  " + PickupDesk.memberCode(familyCode, memberId: "user-voisin-1") + "\n"
        await model.scan(typed)
        #expect(model.outcome?.result.isSuccess == true)
        let stored = try await repos.groupOrders.shares(ofGroupOrder: FakeData.HostDemoID.deliveredOrder).first { $0.householdId == household }
        #expect(stored?.isPickedUp == true)
        #expect(stored?.pickedUpBy == "user-voisin-1")
    }

    /// T-198 : le QR d'un groupe porte le code de chaque commande ; l'hôte remet celle qu'il sert, le reste est ignoré.
    @Test func groupCodeHandsOverTheOrderTheHostServes() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: .demo)
        let model = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel)
        await model.load()
        let household = "household-voisin-1"
        let familyCode = try await repos.groupOrders.pickupCode(householdId: household, groupOrderId: FakeData.HostDemoID.deliveredOrder)
        let elsewhere = PickupDesk.pickupCode(orderId: "commande-ailleurs", householdId: household, token: PickupDesk.newPickupToken())
        let bundle = try #require(PickupDesk.bundleCode([PickupDesk.memberCode(elsewhere, memberId: "user-voisin-1"),
                                                         PickupDesk.memberCode(familyCode, memberId: "user-voisin-1")]))
        await model.scan(bundle)
        #expect(model.outcome?.result.isSuccess == true)
        #expect(model.outcome?.otherOrdersHandedOver == 0)
        let stored = try await repos.groupOrders.shares(ofGroupOrder: FakeData.HostDemoID.deliveredOrder).first { $0.householdId == household }
        #expect(stored?.isPickedUp == true)
        #expect(stored?.pickedUpBy == "user-voisin-1")
    }

    /// T-198 de bout en bout : la famille (Voisins 1) a deux commandes livrées chez Amina dans le même groupe. Sa
    /// Cueillette montre UN QR ; l'hôte le scanne une fois et les deux parts sont remises.
    @Test func oneGroupCodeScanHandsOverEveryOrderOfTheGroup() async throws {
        var data = FakeData.demo
        let second = FakeData.HostDemoID.onTheWayOrder
        let index = try #require(data.groupOrders.firstIndex { $0.id == second })
        data.groupOrders[index].status = .delivered
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let household = "household-voisin-1", member = "user-voisin-1"

        // Côté famille : un seul groupe, un seul QR qui porte les deux commandes.
        let family = PickupViewModel(repositories: repos, householdId: household, groupId: ID.villerayKitchen,
                                     userId: member)
        await family.load()
        let content = try #require(family.state.value)
        let group = try #require(content.groups.first { $0.id == ID.villerayKitchen })
        let qr = try #require(group.qrPayload)
        let orderIds = PickupDesk.bundledCodes(qr).compactMap { PickupDesk.parse($0)?.orderId }
        #expect(Set(orderIds) == [FakeData.HostDemoID.deliveredOrder, second])

        // Côté hôte : un scan, deux remises ; le bandeau parle de la commande affichée et de l'autre.
        let host = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                       groupId: ID.saintMichel)
        await host.load()
        await host.scan(qr)
        #expect(host.outcome?.result.isSuccess == true)
        #expect(host.outcome?.otherOrdersHandedOver == 1)
        #expect(host.outcome?.othersMessage == "Aussi remise : 1 autre commande de ce groupe.")
        for orderId in [FakeData.HostDemoID.deliveredOrder, second] {
            let stored = try await repos.groupOrders.shares(ofGroupOrder: orderId).first { $0.householdId == household }
            #expect(stored?.isPickedUp == true)
            #expect(stored?.pickedUpBy == member)
        }

        // Rescanner le même QR : rien n'est remis deux fois.
        await host.scan(qr)
        #expect(host.outcome?.result == .alreadyPickedUp(try #require(
            try await repos.groupOrders.shares(ofGroupOrder: host.selectedOrderId ?? "").first { $0.householdId == household })))
        #expect(host.outcome?.otherOrdersHandedOver == 0)

        // La Cueillette de la famille : tout est récupéré, plus de QR.
        await family.load()
        #expect(family.state.value?.groups.first?.qrPayload == nil)
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
        let (model, repositories) = makeModelAndRepositories()
        await model.load()
        let household = try #require(model.checklist?.entries.last).householdId
        let familyCode = try await repositories.groupOrders.pickupCode(householdId: household, groupOrderId: ID.potatoOrder)
        let code = PickupDesk.memberCode(familyCode, memberId: "user-membre")
        await model.scan(code)
        #expect(model.outcome?.result.isSuccess == true)
        #expect(model.state.value?.stations.first?.shares.first { $0.householdId == household }?.isPickedUp == true)
    }

    /// Sécurité (vol de cueillette) : un membre du groupe recalcule l'ancien code d'une autre famille, ou invente
    /// un jeton : l'hôte le refuse et la part reste à remettre.
    @Test func forgedOrLegacyCodeOfAnotherFamilyIsRejected() async throws {
        let (model, repositories) = makeModelAndRepositories()
        await model.load()
        let victim = try #require(model.checklist?.entries.last).householdId
        _ = try await repositories.groupOrders.pickupCode(householdId: victim, groupOrderId: ID.potatoOrder)
        let forged = PickupDesk.pickupCode(orderId: ID.potatoOrder, householdId: victim, token: PickupDesk.newPickupToken())
        await model.scan(PickupDesk.memberCode(forged, memberId: "user-intrus"))
        #expect(model.outcome?.result == .unknownCode)
        await model.scan("GRENIER:\(ID.potatoOrder):\(victim):0a1b2c3d#user-intrus")
        #expect(model.outcome?.result == .outdatedCode)
        #expect(model.rejections == 2)
        let stored = try await repositories.groupOrders.shares(ofGroupOrder: ID.potatoOrder).first { $0.householdId == victim }
        #expect(stored?.isPickedUp == false)
    }

    /// « Récupéré » à la main : l'hôte est noté comme celui qui a remis la part (firestore.rules exige `pickedUpBy`).
    @Test func tapRecordsTheHostAsConfirmer() async throws {
        let (model, repositories) = makeModelAndRepositories()
        await model.load()
        let household = try #require(model.checklist?.entries.first).householdId
        await model.markPickedUp(householdId: household, in: ID.potatoOrder)
        let stored = try await repositories.groupOrders.shares(ofGroupOrder: ID.potatoOrder).first { $0.householdId == household }
        #expect(stored?.pickedUpBy == ID.amina)
    }

    /// Un code sans membre (`#uid`) : l'hôte qui scanne est noté.
    @Test func codeWithoutMemberRecordsTheHost() async throws {
        let (model, repositories) = makeModelAndRepositories()
        await model.load()
        let household = try #require(model.checklist?.entries.first).householdId
        let code = try await repositories.groupOrders.pickupCode(householdId: household, groupOrderId: ID.potatoOrder)
        await model.scan(code)
        #expect(model.outcome?.result.isSuccess == true)
        let stored = try await repositories.groupOrders.shares(ofGroupOrder: ID.potatoOrder).first { $0.householdId == household }
        #expect(stored?.pickedUpBy == ID.amina)
    }

    /// De bout en bout : la famille ouvre son code (jeton privé, jamais l'ancien code dérivé des ids), l'hôte le
    /// scanne et la part est remise au membre qui le montre.
    @Test func familyQRCarriesAPrivateTokenThatTheHostAccepts() async throws {
        var data = FakeData.montreal
        data.groupOrders[0].status = .delivered
        let orderId = data.groupOrders[0].id
        if !(data.shares[orderId] ?? []).contains(where: { $0.householdId == ID.aminaHousehold }) {
            data.shares[orderId, default: []].append(Share(
                householdId: ID.aminaHousehold, quantity: 1, finalPriceCents: 1_000, isPaid: true,
                suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false
            ))
        }
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let family = PickupViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel,
                                     userId: ID.amina)
        await family.load()
        let payload = try #require(family.state.value?.items.first { $0.groupOrderId == orderId }?.pickupCode)
        let parsed = try #require(PickupDesk.parse(payload))
        #expect(parsed.orderId == orderId)
        #expect(parsed.householdId == ID.aminaHousehold)
        #expect(PickupDesk.isPickupToken(parsed.secret))
        #expect(parsed.memberId == ID.amina)
        // Rouvrir l'écran garde le même jeton.
        await family.load()
        #expect(family.state.value?.items.first { $0.groupOrderId == orderId }?.pickupCode == payload)

        let host = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                       groupId: ID.saintMichel)
        await host.load()
        await host.scan(payload)
        #expect(host.outcome?.result.isSuccess == true)
        #expect(host.outcome?.result.share?.householdId == ID.aminaHousehold)
    }

    @Test func garbageCodeIsRejected() async {
        let model = makeModel()
        await model.load()
        await model.scan("https://example.com")
        #expect(model.outcome?.result == .unknownCode)
        #expect(model.rejections == 1)
    }

    // MARK: T-203 : hôte qui n'est pas membre du groupe

    /// Un compte « hôte » seul (sans ménage ni groupe, comme les hôtes du seed) voit les commandes fermées de son point :
    /// le groupe du point (`PickupPoint.groupId`) est ajouté. Avant, il voyait « Rien à remettre ».
    @Test func hostWhoIsNotAMemberSeesTheClosedOrderOfTheirPoint() async throws {
        var data = FakeData.montreal
        data.groupOrders[0].status = .closed
        data.pickupPoints[0].hostUserId = "user-hote-seul"
        data.pickupPoints[0].groupId = ID.saintMichel
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let stations = try await HostPickupViewModel.stations(
            repositories: repos, userId: "user-hote-seul", householdId: "", groupId: nil
        )
        #expect(stations.map(\.order.id) == [ID.potatoOrder])
        let model = HostPickupViewModel(repositories: repos, userId: "user-hote-seul", householdId: "", groupId: nil)
        await model.load()
        #expect(model.selectedStation?.order.id == ID.potatoOrder)
        #expect(model.checklist?.totalCount == 11)
    }

    /// Point sans groupe : rien de plus qu'avant (pas de commande d'un groupe au hasard).
    @Test func hostOfAPointWithoutGroupSeesNothingNew() async throws {
        var data = FakeData.montreal
        data.groupOrders[0].status = .closed
        data.pickupPoints[0].hostUserId = "user-hote-seul"
        data.pickupPoints[0].groupId = nil
        let stations = try await HostPickupViewModel.stations(
            repositories: .fake(behavior: .instant, data: data), userId: "user-hote-seul", householdId: "", groupId: nil
        )
        #expect(stations.isEmpty)
    }

    /// Un autre compte, ni hôte ni coordonnateur, ne voit toujours rien.
    @Test func strangerStillSeesNothing() async throws {
        var data = FakeData.montreal
        data.groupOrders[0].status = .closed
        data.pickupPoints[0].groupId = ID.saintMichel
        let stations = try await HostPickupViewModel.stations(
            repositories: .fake(behavior: .instant, data: data), userId: "user-inconnu", householdId: "", groupId: nil
        )
        #expect(stations.isEmpty)
    }
}
