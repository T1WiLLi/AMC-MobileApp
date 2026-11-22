// PickupPlacesTests.swift
// Retour samuel : la Cueillette range les articles par lieu (une section par point de cueillette, « Lieu à confirmer »
// pour les commandes sans point) ; un groupe a sa zone de livraison, lieu par défaut de ses commandes.

import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct PickupPlacesTests {
    private typealias ID = FakeData.ID

    // MARK: Regroupement pur

    private static func item(_ orderId: String, cents: Cents, pickedUp: Bool = false) -> PickupViewModel.Item {
        let data = FakeData.montreal
        return PickupViewModel.Item(groupOrderId: orderId, product: data.products[0], offer: data.offers[0], quantity: 1,
                                    totalCents: cents, isPickedUp: pickedUp)
    }

    private static func point(_ id: String, slots: [PickupSlot] = []) -> PickupPoint {
        PickupPoint(id: id, hostUserId: "host-\(id)", name: "Point \(id)", address: "\(id) rue Jarry", photoURL: nil,
                    capacity: 20, accessibility: [.wheelchair], slots: slots)
    }

    @Test func itemsAreGroupedByPlaceInOrderOfAppearance() {
        let now = Date.now
        let soon = PickupSlot(start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(7_200))
        let later = PickupSlot(start: now.addingTimeInterval(86_400), end: now.addingTimeInterval(90_000))
        let entries = [
            PickupViewModel.Entry(item: Self.item("o1", cents: 1_000), pickupPointId: "b", slots: [later]),
            PickupViewModel.Entry(item: Self.item("o2", cents: 500), pickupPointId: nil, slots: []),
            PickupViewModel.Entry(item: Self.item("o3", cents: 250, pickedUp: true), pickupPointId: "a", slots: []),
            PickupViewModel.Entry(item: Self.item("o4", cents: 300), pickupPointId: "b", slots: [soon]),
        ]
        let places = PickupViewModel.places(
            from: entries, points: ["a": Self.point("a"), "b": Self.point("b")], hostFirstNames: ["b": "Karim"], now: now
        )
        // Ordre d'apparition (groupe actif d'abord), « Lieu à confirmer » en dernier.
        #expect(places.map(\.id) == ["b", "a", DeliveryManifest.unassignedStopId])
        #expect(places[0].items.map(\.groupOrderId) == ["o1", "o4"])
        #expect(places[0].totalCents == 1_300)
        #expect(places[0].slot == soon)
        #expect(places[0].hostFirstName == "Karim")
        #expect(places[1].pickedUpCount == 1)
        #expect(places[1].totalCents == 250)
        #expect(places[2].pickupPoint == nil)
        #expect(places[2].items.map(\.groupOrderId) == ["o2"])
    }

    @Test func unknownPointGoesToPlaceToConfirm() {
        let entries = [PickupViewModel.Entry(item: Self.item("o1", cents: 100), pickupPointId: "supprimé", slots: [])]
        let places = PickupViewModel.places(from: entries, points: [:])
        #expect(places.map(\.id) == [DeliveryManifest.unassignedStopId])
    }

    @Test func pastSlotsAreIgnoredAndPointSlotsCount() {
        let now = Date.now
        let past = PickupSlot(start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600))
        let pointSlot = PickupSlot(start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600))
        let entries = [PickupViewModel.Entry(item: Self.item("o1", cents: 100), pickupPointId: "a", slots: [past])]
        let places = PickupViewModel.places(from: entries, points: ["a": Self.point("a", slots: [pointSlot])], now: now)
        #expect(places.first?.slot == pointSlot)
    }

    @Test func contentSummarizesAllPlaces() {
        let places = PickupViewModel.places(
            from: [
                PickupViewModel.Entry(item: Self.item("o1", cents: 1_000), pickupPointId: "a", slots: []),
                PickupViewModel.Entry(item: Self.item("o2", cents: 500), pickupPointId: "b", slots: []),
            ],
            points: ["a": Self.point("a"), "b": Self.point("b")], hostFirstNames: ["a": "Amina", "b": "Karim"]
        )
        let content = PickupViewModel.Content(places: places, qrPayload: "qr", orderCode: "GRN-1000")
        #expect(content.items.count == 2)
        #expect(content.totalCents == 1_500)
        #expect(content.pointCount == 2)
        #expect(content.pickupPoint?.id == "a")
        // Plusieurs hôtes : « Montre ce code à l'hôte ».
        #expect(content.hostFirstName == nil)
    }

    // MARK: Zone de livraison du groupe

    @Test func orderWithoutPointFallsBackToTheGroupZone() {
        var zone = Self.point("zone")
        zone.groupId = "g1"
        let order = GroupOrder(id: "o", groupId: "g1", offerId: "x", status: .open, currentTierIndex: nil,
                               committedShares: 0, committedHouseholds: 0, pickupPointId: nil, pickupSlots: [])
        #expect(PickupPoint.resolvedId(for: order, in: [Self.point("autre"), zone]) == "zone")
        var chosen = order
        chosen.pickupPointId = "autre"
        #expect(PickupPoint.resolvedId(for: chosen, in: [zone]) == "autre")
        var elsewhere = order
        elsewhere.groupId = "g2"
        #expect(PickupPoint.resolvedId(for: elsewhere, in: [zone]) == nil)
    }

    // MARK: ViewModel (dépôts fake)

    /// Démo `-demoPickupPlaces` : pommes de terre chez Amina (rue Jarry) et riz à la zone de Villeray.
    @Test func pickupScreenShowsOneSectionPerPlace() async throws {
        let repos = AppRepositories.fake(behavior: .instant, data: FakeData.demo.withPickupPlacesDemo())
        let viewModel = PickupViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel,
                                        userId: ID.amina)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.places.map(\.id) == [ID.jarryPickup, FakeData.PickupPlacesDemoID.villerayZone])
        #expect(content.places[0].items.map(\.groupOrderId) == [ID.potatoOrder])
        #expect(content.places[1].items.map(\.groupOrderId) == [FakeData.PickupPlacesDemoID.villerayRiceOrder])
        #expect(content.places[1].pickupPoint?.name == "Centre communautaire de Villeray")
        #expect(content.places[1].slot != nil)
        #expect(content.totalCents == content.places[0].totalCents + content.places[1].totalCents)
    }

    @Test func orderWithoutAnyPointIsInPlaceToConfirm() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        _ = try await repos.groupOrders.setPickupPoint(nil, slots: [], groupOrderId: ID.potatoOrder)
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.lafleurRiceOrder)
        let viewModel = PickupViewModel(repositories: repos, householdId: ID.aminaHousehold, groupId: ID.saintMichel)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.places.map(\.id) == [ID.jarryPickup, DeliveryManifest.unassignedStopId])
        #expect(content.places[1].items.map(\.groupOrderId) == [ID.potatoOrder])
    }

    @Test func pickerPreselectsTheGroupZone() async throws {
        let data = FakeData.demo.withPickupPlacesDemo()
        let repos = AppRepositories.fake(behavior: .instant, data: data)
        let picker = PickupPointPickerViewModel(repositories: repos, userId: ID.amina,
                                                groupOrderId: FakeData.PickupPlacesDemoID.villerayRiceOrder)
        await picker.load()
        #expect(picker.selectedPointId == FakeData.PickupPlacesDemoID.villerayZone)
        #expect(!picker.slots.isEmpty)
    }

    @Test func manifestDeliversToTheGroupZone() {
        var zone = Self.point("zone")
        zone.groupId = "g1"
        let offer = FakeData.montreal.offers[0]
        let product = FakeData.montreal.products.first { $0.id == offer.productId }!
        let order = GroupOrder(id: "o", groupId: "g1", offerId: offer.id, status: .closed, currentTierIndex: nil,
                               committedShares: 4, committedHouseholds: 2, pickupPointId: nil, pickupSlots: [])
        let manifest = DeliveryManifest(orders: [order], offers: [offer], products: [product], pickupPoints: [zone])
        #expect(manifest.stops.map(\.id) == ["zone"])
    }
}
