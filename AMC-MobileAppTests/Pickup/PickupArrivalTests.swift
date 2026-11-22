// PickupArrivalTests.swift
// « La livraison est arrivée » : closed → delivered par un coordonnateur ou l'hôte, remise seulement une fois
// arrivée, noms des familles pour l'hôte, et un code QR par commande (et par lieu) côté famille.

import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct PickupArrivalTests {
    private typealias ID = FakeData.ID

    private static func order(_ status: GroupOrder.Status, id: String = "o1") -> GroupOrder {
        GroupOrder(id: id, groupId: "g1", offerId: "x", status: status, currentTierIndex: 0, committedShares: 3,
                   committedHouseholds: 2, pickupPointId: "p1", pickupSlots: [])
    }

    private static func share(_ householdId: String, quantity: Int = 1, name: String? = nil, pickedUp: Bool = false,
                              at date: Date? = nil, slot: Date? = nil, code: String? = nil) -> Share {
        Share(householdId: householdId, quantity: quantity, finalPriceCents: 1_000 * quantity, isPaid: true,
              suspendedAmountCents: 0, subsidyCents: 0, qrCode: code, isPickedUp: pickedUp, pickupSlotStart: slot,
              pickedUpAt: date, householdName: name)
    }

    // MARK: Transition

    @Test func onlyAClosedOrderCanBeMarkedArrived() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let delivered = try OrderArrival.markArrived(Self.order(.closed), at: now)
        #expect(delivered.status == .delivered)
        #expect(delivered.deliveredAt == now)
        for status in [GroupOrder.Status.open, .reached, .delivered, .cancelled] {
            #expect(!OrderArrival.canMark(Self.order(status)))
            #expect(throws: AppError.self) { try OrderArrival.markArrived(Self.order(status), at: now) }
        }
    }

    @Test func coordinatorOrHostMayMarkArrived() {
        #expect(OrderArrival.isAllowed(userId: "u1", coordinatorIds: ["u1"], pointHostUserId: "h"))
        #expect(OrderArrival.isAllowed(userId: "h", coordinatorIds: ["u1"], pointHostUserId: "h"))
        #expect(!OrderArrival.isAllowed(userId: "u2", coordinatorIds: ["u1"], pointHostUserId: "h"))
        #expect(!OrderArrival.isAllowed(userId: "", coordinatorIds: [""], pointHostUserId: ""))
    }

    @Test func stagesFollowStatusAndPickups() {
        #expect(OrderArrival.stage(of: .closed, allPickedUp: false) == .enRoute)
        #expect(OrderArrival.stage(of: .delivered, allPickedUp: false) == .handingOut)
        #expect(OrderArrival.stage(of: .delivered, allPickedUp: true) == .finished)
        #expect(OrderArrival.stage(of: .open, allPickedUp: false) == nil)
    }

    @Test func fakeRepositoryMarksArrivedOnce() async throws {
        let repo = FakeGroupOrderRepository(groupOrders: [Self.order(.closed)])
        let delivered = try await repo.markArrived(groupOrderId: "o1", at: .now)
        #expect(delivered.status == .delivered)
        #expect(try await repo.groupOrder(id: "o1").status == .delivered)
        await #expect(throws: AppError.self) { try await repo.markArrived(groupOrderId: "o1", at: .now) }
    }

    // MARK: Noms des familles

    @Test func householdNameFallsBackToShortId() {
        #expect(ShareHouseholdName.display(householdId: "household-041", householdName: "  Famille Benali ") == "Famille Benali")
        #expect(ShareHouseholdName.display(householdId: "household-041", householdName: nil, known: "Voisins 1") == "Voisins 1")
        #expect(ShareHouseholdName.display(householdId: "household-041", householdName: "  ") == "Famille 041")
        #expect(ShareHouseholdName.display(householdId: "Xk3f9QpL2m", householdName: nil) == "Famille PL2M")
        #expect(ShareHouseholdName.normalized(String(repeating: "a", count: 120))?.count == ShareHouseholdName.maxLength)
    }

    // MARK: Liste de remise

    @Test func boardSplitsToServeAndServed() {
        let early = Date(timeIntervalSince1970: 10_000), late = early.addingTimeInterval(3_600)
        let shares = [
            Self.share("h1", quantity: 2, name: "Zoé", slot: late),
            Self.share("h2", name: "Benali", slot: early),
            Self.share("h3", quantity: 3, name: "Alpha", pickedUp: true, at: early),
            Self.share("h4", name: "Bravo", pickedUp: true, at: late),
            Self.share("h5", name: nil),
        ]
        let board = HostPickupViewModel.Board(shares: shares, displayNames: [:])
        #expect(board.toServe.map(\.householdId) == ["h2", "h1", "h5"])
        #expect(board.served.map(\.householdId) == ["h4", "h3"])
        #expect(board.familiesTotal == 5)
        #expect(board.familiesServed == 2)
        #expect(board.sharesTotal == 8)
        #expect(board.sharesHanded == 4)
        #expect(board.toServe.last?.name == "Famille H5")
        #expect(!board.isComplete)

        let searched = HostPickupViewModel.Board(shares: shares, displayNames: [:], query: "ben")
        #expect(searched.toServe.map(\.householdId) == ["h2"])
        #expect(searched.served.isEmpty)
        #expect(searched.familiesTotal == 5) // la recherche ne change pas les compteurs

        let slotOnly = HostPickupViewModel.Board(shares: shares, displayNames: [:], slot: early)
        #expect(slotOnly.toServe.map(\.householdId) == ["h2"])
        #expect(slotOnly.familiesTotal == 1)
    }

    // MARK: Écran hôte

    @Test func demoHasAnOrderOnTheWayToMarkArrived() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: .demo)
        let model = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel)
        await model.load()
        let stations = try #require(model.state.value?.stations)
        #expect(stations.map(\.id) == [FakeData.HostDemoID.deliveredOrder, FakeData.HostDemoID.onTheWayOrder])
        model.selectOrder(FakeData.HostDemoID.onTheWayOrder)
        let station = try #require(model.selectedStation)
        #expect(station.stage == .enRoute)
        #expect(!station.isArrived)
        #expect(station.board(slot: nil).toServe.map(\.name) == ["Voisins 1", "Voisins 2", "Voisins 3"])
        #expect(station.vendorName == "Ferme Bio-Rive")
        #expect(station.point?.id == ID.jarryPickup)

        // Avant l'arrivée : « Récupéré » est refusé.
        await model.markPickedUp(householdId: "household-voisin-1", in: station.id)
        #expect(model.outcome?.result == .orderNotReady(.closed))

        await model.markArrived(orderId: station.id)
        #expect(model.selectedStation?.stage == .handingOut)
        #expect(model.arrivals == 1)
        #expect(model.arrivedOrderId == station.id)
        #expect(try await repos.groupOrders.groupOrder(id: station.id).status == .delivered)

        await model.markPickedUp(householdId: "household-voisin-1", in: station.id)
        #expect(model.outcome?.result.isSuccess == true)
        #expect(model.board?.served.map(\.householdId) == ["household-voisin-1"])
    }

    @Test func coordinatorSeesOrdersOfHisGroupEvenAtAnotherHost() async throws {
        var data = FakeData.montreal
        data.groupOrders[0].status = .closed
        data.groupOrders[0].pickupPointId = ID.pieIXPickup // chez Karim
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let model = HostPickupViewModel(repositories: repos, userId: ID.amina, householdId: ID.aminaHousehold,
                                        groupId: ID.saintMichel, focusGroupId: ID.saintMichel)
        await model.load()
        #expect(model.state.value?.stations.map(\.id) == [ID.potatoOrder])
    }

    @Test func longFinishedOrdersLeaveTheHostScreen() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = [Self.share("h1", pickedUp: true, at: now.addingTimeInterval(-3 * 86_400))]
        let recent = [Self.share("h1", pickedUp: true, at: now.addingTimeInterval(-3_600))]
        #expect(HostPickupViewModel.isLongFinished(order: Self.order(.delivered), shares: old, now: now))
        #expect(!HostPickupViewModel.isLongFinished(order: Self.order(.delivered), shares: recent, now: now))
        #expect(!HostPickupViewModel.isLongFinished(order: Self.order(.closed), shares: old, now: now))
    }

    // MARK: Cueillette de la famille

    @Test func qrPayloadOnlyOnceTheOrderIsClosed() {
        let code = ShareAllocator.qrCode(orderId: "o1", householdId: "h1")
        let share = Self.share("h1", code: code)
        #expect(PickupViewModel.qrPayload(for: Self.order(.open), share: share, memberId: "u1") == nil)
        #expect(PickupViewModel.qrPayload(for: Self.order(.reached), share: share, memberId: "u1") == nil)
        #expect(PickupViewModel.qrPayload(for: Self.order(.closed), share: Self.share("h1"), memberId: "u1") == nil)
        #expect(PickupViewModel.qrPayload(for: Self.order(.closed), share: share, memberId: "u1")
                == PickupDesk.memberCode(code, memberId: "u1"))
        #expect(PickupViewModel.qrPayload(for: Self.order(.delivered), share: share, memberId: "u1") != nil)
    }

    /// `-demoPickupPlaces -demoArrival` : deux lieux ; rue Jarry a deux commandes (une fermée avec SON code,
    /// une ouverte sans code), la zone de Villeray n'a qu'une commande ouverte (pas de code).
    @Test func eachPlaceAndOrderHasItsOwnCode() async throws {
        let data = FakeData.demo.withPickupPlacesDemo().withArrivalDemo()
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let viewModel = PickupViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel,
                                        userId: ID.amina)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.places.map(\.id) == [ID.jarryPickup, FakeData.PickupPlacesDemoID.villerayZone])

        let jarry = content.places[0]
        guard case .codes(let items, let waiting) = jarry.codeState else {
            Issue.record("attendu : un code à la rue Jarry")
            return
        }
        #expect(items.map(\.groupOrderId) == [FakeData.HostDemoID.onTheWayOrder])
        #expect(waiting == 1)
        let payload = try #require(items.first?.pickupCode)
        #expect(payload.contains(FakeData.HostDemoID.onTheWayOrder))
        #expect(payload.hasSuffix("#\(ID.amina)"))
        #expect(content.places[1].codeState == .awaitingClosure)

        // Le sélecteur limite l'écran au lieu choisi.
        let villeray = content.scoped(to: FakeData.PickupPlacesDemoID.villerayZone)
        #expect(villeray.places.map(\.id) == [FakeData.PickupPlacesDemoID.villerayZone])
        #expect(content.scoped(to: nil).places.map(\.id) == [ID.jarryPickup])

        // En route, puis arrivée.
        #expect(content.arrival == .onTheWay)
        _ = try await repos.groupOrders.markArrived(groupOrderId: FakeData.HostDemoID.onTheWayOrder, at: .now)
        await viewModel.load()
        let arrived = try #require(viewModel.state.value)
        guard case .arrived(let place) = arrived.arrival else {
            Issue.record("attendu : arrivée")
            return
        }
        #expect(place.id == ID.jarryPickup)
    }

    @Test func longDonePickupsLeaveTheFamilyScreen() {
        let now = Date.now
        let picked = Self.share("h1", pickedUp: true, at: now.addingTimeInterval(-3 * 86_400))
        #expect(PickupViewModel.isLongDone(order: Self.order(.delivered), share: picked, now: now))
        #expect(!PickupViewModel.isLongDone(order: Self.order(.closed), share: picked, now: now))
        #expect(!PickupViewModel.isLongDone(order: Self.order(.delivered), share: Self.share("h1"), now: now))
    }
}
