import Foundation
import Synchronization
import Testing
@testable import AMC_MobileApp

/// Cache mémoire des dépôts invalidé par les snapshots temps réel (T-112).
struct RepositoryCacheTests {
    private typealias ID = FakeData.ID

    // MARK: RepositoryCache

    @Test func storesAndReturnsAValue() async {
        let cache = RepositoryCache(ttl: 60)
        await cache.store(42, for: .offer("a"))
        let value: Int? = await cache.value(for: .offer("a"))
        #expect(value == 42)
        let wrongType: String? = await cache.value(for: .offer("a"))
        #expect(wrongType == nil)
    }

    @Test func expiredEntriesAreIgnored() async {
        let clock = TestClock()
        let cache = RepositoryCache(ttl: 30, now: { clock.now })
        await cache.store(1, for: .offer("a"))
        clock.advance(by: 29)
        #expect(await cache.value(for: .offer("a")) as Int? == 1)
        clock.advance(by: 2)
        #expect(await cache.value(for: .offer("a")) as Int? == nil)
    }

    @Test func invalidateRemovesEntries() async {
        let cache = RepositoryCache(ttl: 60)
        await cache.store(1, for: .offer("a"))
        await cache.store(2, for: .offer("b"))
        await cache.store(3, for: .group("g"))
        await cache.invalidate(.offer("a"))
        #expect(await cache.value(for: .offer("a")) as Int? == nil)
        #expect(await cache.value(for: .offer("b")) as Int? == 2)
        await cache.invalidateAll()
        #expect(await cache.value(for: .offer("b")) as Int? == nil)
        #expect(await cache.value(for: .group("g")) as Int? == nil)
    }

    @Test func changesStreamAnnouncesReplacedKeys() async {
        let cache = RepositoryCache(ttl: 60)
        let changes = await cache.changes()
        var iterator = changes.makeAsyncIterator()
        await cache.store(1, for: .offer("a"))
        await cache.invalidate(.group("g"))
        #expect(await iterator.next() == .offer("a"))
        #expect(await iterator.next() == .group("g"))
    }

    // MARK: Lectures

    @Test func secondReadIsServedByTheCache() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let spy = SpyOfferRepository(base: base.offers)
        var spied = base
        spied.offers = spy
        let repos = spied.cached()

        let first = try await repos.offers.offer(id: ID.potatoOffer)
        let second = try await repos.offers.offer(id: ID.potatoOffer)
        #expect(first == second)
        #expect(await spy.calls("offer") == 1)

        _ = try await repos.offers.activeOffers(inZone: nil)
        _ = try await repos.offers.activeOffers(inZone: nil)
        #expect(await spy.calls("activeOffers") == 1)
    }

    @Test func expiredTTLReadsAgain() async throws {
        let clock = TestClock()
        let base = AppRepositories.fake(behavior: .instant)
        let spy = SpyOfferRepository(base: base.offers)
        var spied = base
        spied.offers = spy
        let repos = spied.cached(by: RepositoryCache(ttl: 30, now: { clock.now }))

        _ = try await repos.offers.offer(id: ID.potatoOffer)
        clock.advance(by: 31)
        _ = try await repos.offers.offer(id: ID.potatoOffer)
        #expect(await spy.calls("offer") == 2)
    }

    // MARK: Temps réel

    @Test func snapshotFromAnotherClientReplacesTheCachedEntry() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let cache = RepositoryCache(ttl: 3_600)
        let repos = base.cached(by: cache)

        #expect(try await repos.groupOrders.groupOrder(id: ID.potatoOrder).committedShares == 19)
        #expect(try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel).first?.committedShares == 19)

        var snapshots = await repos.groupOrders.observeGroupOrder(id: ID.potatoOrder).makeAsyncIterator()
        #expect(try await snapshots.next()?.committedShares == 19)

        // Un « second client » écrit directement dans le dépôt sous-jacent.
        try await base.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        #expect(try await snapshots.next()?.committedShares == 20)

        #expect(try await repos.groupOrders.groupOrder(id: ID.potatoOrder).committedShares == 20)
        #expect(try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel).first?.committedShares == 20)
        #expect(try await repos.groupOrders.groupOrders(ofOffer: ID.potatoOffer).first?.committedShares == 20)
        // Les parts ont changé : elles sont relues.
        let shares = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(shares.contains { $0.householdId == ID.aminaHousehold })
    }

    @Test func groupSnapshotReplacesTheGroupInLists() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let repos = base.cached()
        let before = try await repos.groups.group(id: ID.hochelaga)
        _ = try await repos.groups.groups(inNeighborhood: nil)

        var snapshots = await repos.groups.observeGroup(id: ID.hochelaga).makeAsyncIterator()
        _ = try await snapshots.next()
        try await base.groups.join(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        let updated = try #require(try await snapshots.next())
        #expect(updated.householdCount == before.householdCount + 1)

        #expect(try await repos.groups.group(id: ID.hochelaga) == updated)
        let listed = try await repos.groups.groups(inNeighborhood: nil).first { $0.id == ID.hochelaga }
        #expect(listed == updated)
    }

    @MainActor
    @Test func viewModelOnCachedRepositoriesRepublishesTheNewValue() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let repos = base.cached()
        let viewModel = OfferDetailViewModel(
            repositories: repos, offerId: ID.potatoOffer, householdId: ID.aminaHousehold, groupId: ID.saintMichel
        )
        await viewModel.load()
        #expect(viewModel.state.value?.committedShares == 19)

        let observation = Task { await viewModel.observe() }
        defer { observation.cancel() }
        try await waitUntil { viewModel.state.value?.groupOrder != nil }
        // Laisse l'écoute s'abonner avant l'écriture du second client.
        for _ in 0..<20 { await Task.yield() }

        // Le voisin 1 avait 2 parts, un second client passe à 5 : 19 - 2 + 5 = 22.
        try await base.groupOrders.setShare(quantity: 5, householdId: "household-voisin-1", groupOrderId: ID.potatoOrder)
        try await waitUntil { viewModel.state.value?.committedShares == 22 }

        // Un rechargement passe par le cache déjà rafraîchi par le snapshot.
        await viewModel.load()
        #expect(viewModel.state.value?.committedShares == 22)
    }

    // MARK: Écritures

    @Test func openingAnOrderThroughTheDecoratorInvalidatesTheList() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let spy = SpyGroupOrderRepository(base: base.groupOrders)
        var spied = base
        spied.groupOrders = spy
        let repos = spied.cached()

        #expect(try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel).count == 1)
        _ = try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel)
        #expect(await spy.calls("groupOrdersOfGroup") == 1)

        let opened = try await repos.groupOrders.openGroupOrder(groupId: ID.saintMichel, offerId: ID.riceOffer)
        let list = try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel)
        #expect(await spy.calls("groupOrdersOfGroup") == 2)
        #expect(list.contains { $0.id == opened.id })
        // La commande ouverte est servie par le cache.
        _ = try await repos.groupOrders.groupOrder(id: opened.id)
        #expect(await spy.calls("groupOrder") == 0)
    }

    @Test func setShareThroughTheDecoratorUpdatesEntries() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let spy = SpyGroupOrderRepository(base: base.groupOrders)
        var spied = base
        spied.groupOrders = spy
        let repos = spied.cached()

        _ = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        _ = try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel)
        _ = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)

        #expect(try await repos.groupOrders.groupOrder(id: ID.potatoOrder).committedShares == 20)
        #expect(try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel).first?.committedShares == 20)
        #expect(await spy.calls("groupOrder") == 1)
        #expect(await spy.calls("groupOrdersOfGroup") == 1)
        _ = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(await spy.calls("shares") == 2)
    }

    @Test func pickupChangesThroughTheDecoratorUpdateEntries() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let spy = SpyGroupOrderRepository(base: base.groupOrders)
        var spied = base
        spied.groupOrders = spy
        let repos = spied.cached()

        let before = try await repos.groupOrders.groupOrder(id: ID.potatoOrder)
        _ = try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel)
        _ = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        let slot = try #require(before.pickupSlots.first)
        let later = PickupSlot(start: slot.end, end: slot.end.addingTimeInterval(3_600))

        try await repos.groupOrders.setPickupPoint(before.pickupPointId, slots: [slot, later], groupOrderId: ID.potatoOrder)
        #expect(try await repos.groupOrders.groupOrder(id: ID.potatoOrder).pickupSlots.count == 2)
        #expect(try await repos.groupOrders.groupOrders(ofGroup: ID.saintMichel).first?.pickupSlots.count == 2)
        #expect(await spy.calls("groupOrder") == 1)
        #expect(await spy.calls("groupOrdersOfGroup") == 1)
        _ = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(await spy.calls("shares") == 2)

        // Réserver un créneau fait relire les parts.
        try await repos.groupOrders.setShare(quantity: 1, householdId: ID.aminaHousehold, groupOrderId: ID.potatoOrder)
        try await repos.groupOrders.reservePickupSlot(start: later.start, householdId: ID.aminaHousehold,
                                                      groupOrderId: ID.potatoOrder)
        let shares = try await repos.groupOrders.shares(ofGroupOrder: ID.potatoOrder)
        #expect(shares.first { $0.householdId == ID.aminaHousehold }?.pickupSlotStart == later.start)
    }

    @Test func savingAnOfferInvalidatesOfferLists() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let repos = base.cached()
        var offer = try await repos.offers.offer(id: ID.riceOffer)
        #expect(try await repos.offers.activeOffers(inZone: nil).contains { $0.id == ID.riceOffer })
        _ = try await repos.offers.offers(ofVendor: ID.moulinsDuNord)

        offer.status = .cancelled
        try await repos.offers.saveOffer(offer)
        #expect(try await repos.offers.offer(id: ID.riceOffer).status == .cancelled)
        #expect(try await !repos.offers.activeOffers(inZone: nil).contains { $0.id == ID.riceOffer })
        #expect(try await repos.offers.offers(ofVendor: ID.moulinsDuNord).first?.status == .cancelled)
    }

    @Test func joiningThroughTheDecoratorInvalidatesMembership() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let repos = base.cached()
        let before = try await repos.groups.members(ofGroup: ID.hochelaga).count
        #expect(try await !repos.groups.groups(ofHousehold: ID.aminaHousehold).contains { $0.id == ID.hochelaga })

        try await repos.groups.join(groupId: ID.hochelaga, householdId: ID.aminaHousehold)
        #expect(try await repos.groups.members(ofGroup: ID.hochelaga).count == before + 1)
        #expect(try await repos.groups.groups(ofHousehold: ID.aminaHousehold).contains { $0.id == ID.hochelaga })
    }

    @Test func cachedKeepsTheOtherRepositories() async throws {
        let base = AppRepositories.fake(behavior: .instant)
        let repos = base.cached(ttl: 10)
        #expect(repos.users as AnyObject === base.users as AnyObject)
        #expect(repos.vendors as AnyObject === base.vendors as AnyObject)
        #expect(repos.pickupPoints as AnyObject === base.pickupPoints as AnyObject)
    }

    // MARK: Outils

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition jamais remplie")
    }
}

/// Horloge contrôlable pour les TTL.
private final class TestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(by seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

/// Compte les appels de lecture.
private actor CallCounter {
    private var counts: [String: Int] = [:]
    func hit(_ name: String) { counts[name, default: 0] += 1 }
    func calls(_ name: String) -> Int { counts[name, default: 0] }
}

private final class SpyOfferRepository: OfferRepository {
    let base: any OfferRepository
    private let counter = CallCounter()
    init(base: any OfferRepository) { self.base = base }
    func calls(_ name: String) async -> Int { await counter.calls(name) }

    func activeOffers(inZone zone: String?) async throws -> [Offer] {
        await counter.hit("activeOffers")
        return try await base.activeOffers(inZone: zone)
    }
    func offers(ofVendor vendorId: String) async throws -> [Offer] {
        await counter.hit("offersOfVendor")
        return try await base.offers(ofVendor: vendorId)
    }
    func offer(id: String) async throws -> Offer {
        await counter.hit("offer")
        return try await base.offer(id: id)
    }
    func saveOffer(_ offer: Offer) async throws { try await base.saveOffer(offer) }
}

private final class SpyGroupOrderRepository: GroupOrderRepository {
    let base: any GroupOrderRepository
    private let counter = CallCounter()
    init(base: any GroupOrderRepository) { self.base = base }
    func calls(_ name: String) async -> Int { await counter.calls(name) }

    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder] {
        await counter.hit("groupOrdersOfGroup")
        return try await base.groupOrders(ofGroup: groupId)
    }
    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder] {
        await counter.hit("groupOrdersOfOffer")
        return try await base.groupOrders(ofOffer: offerId)
    }
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder {
        try await base.openGroupOrder(groupId: groupId, offerId: offerId)
    }
    func groupOrder(id: String) async throws -> GroupOrder {
        await counter.hit("groupOrder")
        return try await base.groupOrder(id: id)
    }
    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share] {
        await counter.hit("shares")
        return try await base.shares(ofGroupOrder: groupOrderId)
    }
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder {
        try await base.setShare(quantity: quantity, householdId: householdId, groupOrderId: groupOrderId)
    }
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder {
        try await base.setPickupPoint(pickupPointId, slots: slots, groupOrderId: groupOrderId)
    }
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share {
        try await base.reservePickupSlot(start: start, householdId: householdId, groupOrderId: groupOrderId)
    }
    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error> {
        await base.observeGroupOrder(id: id)
    }
}
