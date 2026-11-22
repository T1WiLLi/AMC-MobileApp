import Foundation
import Testing
import UIKit
@testable import AMC_MobileApp

/// Devenir hôte, choix du point par le coordonnateur, créneaux réservés (T-077), sur `FakeData.montreal`.
/// Amina est coordonnatrice de Saint-Michel et hôte de « Chez Amina, rue Jarry » ; « household-voisin-1 » a une part.
@MainActor
struct HostAndSlotsViewModelTests {
    private typealias ID = FakeData.ID
    private let neighbor = "household-voisin-1"

    private nonisolated struct StubPhotoStore: HostPhotoStore {
        func upload(_ data: Data, pointId: String) async throws -> URL {
            URL(string: "https://example.com/\(pointId).jpg")!
        }
    }

    private nonisolated struct FailingPhotoStore: HostPhotoStore {
        func upload(_ data: Data, pointId: String) async throws -> URL { throw AppError.permissionDenied }
    }

    private static func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 1_200)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 1_200))
        }.jpegData(compressionQuality: 0.9)!
    }

    private func fillNewPoint(_ viewModel: HostSetupViewModel) {
        viewModel.name = "Chez Karim"
        viewModel.address = "8200 boul. Pie-IX"
        viewModel.capacity = 12
        viewModel.photoData = Self.photo()
    }

    // MARK: Devenir hôte (RQ-062)

    @Test func newHostPhotoGoesToMediaStore() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = HostSetupViewModel(repositories: repos, userId: "user-karim-2",
                                           addressValidator: FakeAddressValidator(), makeId: { "pickup-nouveau" })
        await viewModel.load()
        fillNewPoint(viewModel)

        let saved = try #require(await viewModel.save())
        let url = try #require(saved.photoURL)
        #expect(MediaURL.source(of: url) == .media(.pickupPhoto(pointId: "pickup-nouveau")))
        #expect(try await repos.images.imageData(at: .pickupPhoto(pointId: "pickup-nouveau")).isEmpty == false)
        #expect(try await repos.pickupPoints.pickupPoint(id: "pickup-nouveau").photoURL == url)
    }

    @Test func failedPhotoUploadKeepsNewPointAndPhoto() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = HostSetupViewModel(repositories: repos, userId: "user-karim-2", photoStore: FailingPhotoStore(),
                                           addressValidator: FakeAddressValidator(), makeId: { "pickup-nouveau" })
        await viewModel.load()
        fillNewPoint(viewModel)

        #expect(await viewModel.save() == nil)
        #expect(viewModel.saveError != nil)
        #expect(viewModel.isEditing, "le point est créé, sans photo")
        #expect(viewModel.photoData != nil, "la photo choisie reste là pour réessayer")
        #expect(try await repos.pickupPoints.pickupPoint(id: "pickup-nouveau").photoURL == nil)
    }

    @Test func newHostCreatesPoint() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = HostSetupViewModel(repositories: repos, userId: "user-karim-2", photoStore: StubPhotoStore(),
                                           addressValidator: FakeAddressValidator(), makeId: { "pickup-nouveau" })
        await viewModel.load()
        #expect(!viewModel.isEditing)
        #expect(viewModel.validationError != nil)
        #expect(await viewModel.save() == nil)

        viewModel.name = "Chez Karim"
        viewModel.address = "8200 boul. Pie-IX"
        viewModel.capacity = 12
        viewModel.toggle(.stepFree)
        viewModel.toggle(.nearMetro)
        viewModel.photoData = Data([0xFF, 0xD8])
        #expect(viewModel.validationError == nil)

        let saved = try #require(await viewModel.save())
        #expect(saved.id == "pickup-nouveau")
        #expect(saved.photoURL?.lastPathComponent == "pickup-nouveau.jpg")
        #expect(saved.accessibility == [.stepFree, .nearMetro])
        #expect(viewModel.isEditing)
        let stored = try await repos.pickupPoints.pickupPoint(id: "pickup-nouveau")
        #expect(stored.hostUserId == "user-karim-2")
        #expect(stored.capacity == 12)
        // T-185 : adresse vérifiée (fake), position enregistrée en geohash de 7 caractères.
        #expect(stored.geohash?.count == 7)
    }

    @Test func existingHostEditsOwnPoint() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = HostSetupViewModel(repositories: repos, userId: ID.amina, photoStore: StubPhotoStore(),
                                           addressValidator: FakeAddressValidator())
        await viewModel.load()
        #expect(viewModel.isEditing)
        #expect(viewModel.name == "Chez Amina, rue Jarry")
        #expect(viewModel.accessibility == [.stepFree, .nearMetro])

        viewModel.capacity = 30
        viewModel.toggle(.nearMetro)
        _ = try #require(await viewModel.save())
        let stored = try await repos.pickupPoints.pickupPoint(id: ID.jarryPickup)
        #expect(stored.capacity == 30)
        #expect(stored.accessibility == [.stepFree])
        #expect(!stored.slots.isEmpty, "les créneaux du point sont gardés")
    }

    @Test func anotherUserCannotOverwritePoint() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        var stolen = try await repos.pickupPoints.pickupPoint(id: ID.jarryPickup)
        stolen.hostUserId = "intrus"
        await #expect(throws: AppError.permissionDenied) { try await repos.pickupPoints.savePickupPoint(stolen) }
    }

    @Test func offlineSaveShowsError() async {
        let repos = AppRepositories.fake(behavior: .failing(.offline))
        let viewModel = HostSetupViewModel(repositories: repos, userId: "u", addressValidator: FakeAddressValidator())
        viewModel.name = "Chez moi"
        viewModel.address = "8200 boul. Pie-IX"
        #expect(await viewModel.save() == nil)
        #expect(viewModel.saveError == .offline)
    }

    // MARK: Point du groupe (RQ-063)

    @Test func coordinatorChoosesPointAndSlots() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = PickupPointPickerViewModel(repositories: repos, userId: ID.amina, groupOrderId: ID.potatoOrder)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.isCoordinator)
        #expect(content.points.count == 3)
        #expect(viewModel.selectedPointId == ID.jarryPickup)
        #expect(!viewModel.hasChanges)

        viewModel.selectPoint(id: ID.communityPickup)
        viewModel.addSlot()
        #expect(viewModel.slots.count == 2)
        let added = try #require(viewModel.slots.last)
        viewModel.setCapacity(start: added.start, capacity: 4)
        #expect(viewModel.canSave)

        let order = try #require(await viewModel.save())
        #expect(order.pickupPointId == ID.communityPickup)
        #expect(order.pickupSlots.count == 2)
        #expect(order.pickupSlots.last?.capacity == 4)
        #expect(try await repos.groupOrders.groupOrder(id: ID.potatoOrder).pickupPointId == ID.communityPickup)
    }

    @Test func overlappingSlotsCannotBeSaved() async throws {
        let viewModel = PickupPointPickerViewModel(repositories: .fake(behavior: .instant), userId: ID.amina,
                                                   groupOrderId: ID.potatoOrder)
        await viewModel.load()
        viewModel.addSlot()
        let second = try #require(viewModel.slots.last)
        viewModel.moveSlot(start: second.start, to: try #require(viewModel.slots.first).start.addingTimeInterval(600))
        #expect(viewModel.validationError != nil)
        #expect(!viewModel.canSave)
    }

    @Test func memberIsNotCoordinator() async throws {
        let viewModel = PickupPointPickerViewModel(repositories: .fake(behavior: .instant), userId: "user-voisin",
                                                   groupOrderId: ID.potatoOrder)
        await viewModel.load()
        #expect(viewModel.state.value?.isCoordinator == false)
        viewModel.addSlot()
        #expect(!viewModel.canSave)
    }

    @Test func removingSlotClearsReservations() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let order = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        let slot = try #require(order.pickupSlots.first)
        try await repos.groupOrders.reservePickupSlot(start: slot.start, householdId: neighbor, groupOrderId: ID.potatoOrder)

        let later = PickupSlot(start: slot.end, end: slot.end.addingTimeInterval(3_600), capacity: 5)
        try await repos.groupOrders.setPickupPoint(ID.jarryPickup, slots: [later], groupOrderId: ID.potatoOrder)
        let shares = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(shares.allSatisfy { $0.pickupSlotStart == nil })
    }

    // MARK: Créneaux (RQ-064)

    @Test func householdReservesAndCancelsSlot() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let viewModel = SlotBookingViewModel(repositories: repos, householdId: neighbor, groupOrderId: ID.potatoOrder)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.pickupPoint?.id == ID.jarryPickup)
        #expect(content.reservedStart == nil)
        let first = try #require(content.availability.first)
        #expect(viewModel.canReserve(first))

        await viewModel.reserve(first.slot.start)
        #expect(viewModel.state.value?.reservedStart == first.slot.start)
        #expect(viewModel.state.value?.availability.first?.reserved == 1)
        #expect(viewModel.confirmations == 1)

        await viewModel.cancelReservation()
        #expect(viewModel.state.value?.reservedStart == nil)
        #expect(viewModel.confirmations == 1)
    }

    @Test func fullSlotShowsErrorAndKeepsState() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let order = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        var slot = try #require(order.pickupSlots.first)
        slot.capacity = 1
        try await repos.groupOrders.setPickupPoint(ID.jarryPickup, slots: [slot], groupOrderId: ID.potatoOrder)
        try await repos.groupOrders.reservePickupSlot(start: slot.start, householdId: "household-voisin-2",
                                                      groupOrderId: ID.potatoOrder)

        let viewModel = SlotBookingViewModel(repositories: repos, householdId: neighbor, groupOrderId: ID.potatoOrder)
        await viewModel.load()
        let full = try #require(viewModel.state.value?.availability.first)
        #expect(full.isFull)
        #expect(!viewModel.canReserve(full))
        await viewModel.reserve(slot.start)
        #expect(viewModel.actionError != nil)
        #expect(viewModel.state.value?.reservedStart == nil)
    }

    @Test func householdWithoutShareCannotReserve() async throws {
        let viewModel = SlotBookingViewModel(repositories: .fake(behavior: .instant), householdId: ID.aminaHousehold,
                                             groupOrderId: ID.potatoOrder)
        await viewModel.load()
        let content = try #require(viewModel.state.value)
        #expect(content.myShare == nil)
        #expect(!viewModel.canReserve(try #require(content.availability.first)))
    }

    @Test func noSlotsMeansEmpty() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        try await repos.groupOrders.setPickupPoint(nil, slots: [], groupOrderId: ID.potatoOrder)
        let viewModel = SlotBookingViewModel(repositories: repos, householdId: neighbor, groupOrderId: ID.potatoOrder)
        await viewModel.load()
        #expect(viewModel.state == .empty)
    }

    @Test func reservationKeepsSlotWhenQuantityChanges() async throws {
        let repos = AppRepositories.fake(behavior: .instant)
        let order = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        let slot = try #require(order.pickupSlots.first)
        try await repos.groupOrders.reservePickupSlot(start: slot.start, householdId: neighbor, groupOrderId: ID.potatoOrder)
        try await repos.groupOrders.setShare(quantity: 3, householdId: neighbor, groupOrderId: ID.potatoOrder)
        let mine = try #require(try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
            .first { $0.householdId == neighbor })
        #expect(mine.pickupSlotStart == slot.start)
        #expect(mine.quantity == 3)
    }

    @Test func slotFormatIsFrench() {
        #expect(SlotFormat.duration(minutes: 30) == "30 min")
        #expect(SlotFormat.duration(minutes: 60) == "1 h")
        #expect(SlotFormat.duration(minutes: 90) == "1 h 30")
    }
}
