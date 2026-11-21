// FakeMatchingRepositories.swift
// Dépôts en mémoire des envies des familles (S-07) et des disponibilités des vendeurs (S-08),
// pour les previews et les tests. Même comportement que les dépôts Firestore.

import Foundation

actor FakeGroupWishRepository: GroupWishRepository {
    private let behavior: FakeBehavior
    private let now: @Sendable () -> Date
    /// Envies par id.
    private var wishes: [String: GroupWish]
    /// Écouteurs par id de groupe.
    private var broadcaster = FakeBroadcaster<[GroupWish]>()

    init(behavior: FakeBehavior = .instant, wishes: [GroupWish] = [], now: @escaping @Sendable () -> Date = { .now }) {
        self.behavior = behavior
        self.now = now
        self.wishes = Dictionary(wishes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func wishes(ofGroup groupId: String) async throws -> [GroupWish] {
        try await behavior.simulate()
        return sortedWishes(ofGroup: groupId)
    }

    func wishes(ofHousehold householdId: String, inGroup groupId: String) async throws -> [GroupWish] {
        try await behavior.simulate()
        return sortedWishes(ofGroup: groupId).filter { $0.householdId == householdId }
    }

    func allWishes() async throws -> [GroupWish] {
        try await behavior.simulate()
        return wishes.values.sorted(by: Self.isOrderedBefore)
    }

    @discardableResult
    func addWish(_ wish: GroupWish) async throws -> GroupWish {
        try await behavior.simulate()
        try wish.validate()
        var created = wish
        if created.id.isEmpty { created.id = "wish-\(UUID().uuidString.lowercased())" }
        guard wishes[created.id] == nil else { throw AppError.invalidInput("Cette envie existe déjà.") }
        created.createdAt = now()
        created.updatedAt = created.createdAt
        wishes[created.id] = created
        publish(groupId: created.groupId)
        return created
    }

    @discardableResult
    func updateWish(_ wish: GroupWish) async throws -> GroupWish {
        try await behavior.simulate()
        guard let current = wishes[wish.id] else { throw AppError.notFound }
        // Comme firestore.rules : une envie reste dans son groupe et à son ménage.
        guard current.groupId == wish.groupId, current.householdId == wish.householdId else {
            throw AppError.permissionDenied
        }
        try wish.validate()
        var updated = wish
        updated.createdAt = current.createdAt
        updated.updatedAt = now()
        wishes[wish.id] = updated
        publish(groupId: updated.groupId)
        return updated
    }

    func removeWish(id: String, groupId: String) async throws {
        try await behavior.simulate()
        guard let current = wishes[id], current.groupId == groupId else { throw AppError.notFound }
        wishes[id] = nil
        publish(groupId: groupId)
    }

    func observeWishes(ofGroup groupId: String) async -> AsyncThrowingStream<[GroupWish], any Error> {
        let (stream, continuation) = AsyncThrowingStream<[GroupWish], any Error>.makeStream()
        if let failure = behavior.failure {
            continuation.finish(throwing: failure)
            return stream
        }
        let token = broadcaster.add(continuation, for: groupId)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopObserving(token: token, groupId: groupId) }
        }
        continuation.yield(sortedWishes(ofGroup: groupId))
        return stream
    }

    // MARK: - Interne

    private func sortedWishes(ofGroup groupId: String) -> [GroupWish] {
        wishes.values.filter { $0.groupId == groupId }.sorted(by: Self.isOrderedBefore)
    }

    private func publish(groupId: String) {
        broadcaster.send(sortedWishes(ofGroup: groupId), for: groupId)
    }

    private func stopObserving(token: UUID, groupId: String) {
        broadcaster.remove(token: token, for: groupId)
    }

    private static func isOrderedBefore(_ lhs: GroupWish, _ rhs: GroupWish) -> Bool {
        lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id < rhs.id
    }
}

actor FakeVendorSupplyRepository: VendorSupplyRepository {
    private let behavior: FakeBehavior
    private let now: @Sendable () -> Date
    /// Disponibilités par id.
    private var supplies: [String: VendorSupply]
    /// Écouteurs par id de vendeur.
    private var broadcaster = FakeBroadcaster<[VendorSupply]>()

    init(behavior: FakeBehavior = .instant, supplies: [VendorSupply] = [], now: @escaping @Sendable () -> Date = { .now }) {
        self.behavior = behavior
        self.now = now
        self.supplies = Dictionary(supplies.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func supplies(ofVendor vendorId: String) async throws -> [VendorSupply] {
        try await behavior.simulate()
        return sortedSupplies(ofVendor: vendorId)
    }

    func allSupplies() async throws -> [VendorSupply] {
        try await behavior.simulate()
        return supplies.values.sorted(by: Self.isOrderedBefore)
    }

    @discardableResult
    func addSupply(_ supply: VendorSupply) async throws -> VendorSupply {
        try await behavior.simulate()
        try supply.validate()
        var created = supply
        if created.id.isEmpty { created.id = "supply-\(UUID().uuidString.lowercased())" }
        guard supplies[created.id] == nil else { throw AppError.invalidInput("Cette disponibilité existe déjà.") }
        created.createdAt = now()
        created.updatedAt = created.createdAt
        supplies[created.id] = created
        publish(vendorId: created.vendorId)
        return created
    }

    @discardableResult
    func updateSupply(_ supply: VendorSupply) async throws -> VendorSupply {
        try await behavior.simulate()
        guard let current = supplies[supply.id] else { throw AppError.notFound }
        guard current.vendorId == supply.vendorId else { throw AppError.permissionDenied }
        try supply.validate()
        var updated = supply
        updated.createdAt = current.createdAt
        updated.updatedAt = now()
        supplies[supply.id] = updated
        publish(vendorId: updated.vendorId)
        return updated
    }

    func removeSupply(id: String, vendorId: String) async throws {
        try await behavior.simulate()
        guard let current = supplies[id], current.vendorId == vendorId else { throw AppError.notFound }
        supplies[id] = nil
        publish(vendorId: vendorId)
    }

    func observeSupplies(ofVendor vendorId: String) async -> AsyncThrowingStream<[VendorSupply], any Error> {
        let (stream, continuation) = AsyncThrowingStream<[VendorSupply], any Error>.makeStream()
        if let failure = behavior.failure {
            continuation.finish(throwing: failure)
            return stream
        }
        let token = broadcaster.add(continuation, for: vendorId)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopObserving(token: token, vendorId: vendorId) }
        }
        continuation.yield(sortedSupplies(ofVendor: vendorId))
        return stream
    }

    // MARK: - Interne

    private func sortedSupplies(ofVendor vendorId: String) -> [VendorSupply] {
        supplies.values.filter { $0.vendorId == vendorId }.sorted(by: Self.isOrderedBefore)
    }

    private func publish(vendorId: String) {
        broadcaster.send(sortedSupplies(ofVendor: vendorId), for: vendorId)
    }

    private func stopObserving(token: UUID, vendorId: String) {
        broadcaster.remove(token: token, for: vendorId)
    }

    private static func isOrderedBefore(_ lhs: VendorSupply, _ rhs: VendorSupply) -> Bool {
        lhs.availableFrom != rhs.availableFrom ? lhs.availableFrom < rhs.availableFrom : lhs.id < rhs.id
    }
}
