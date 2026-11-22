// CachedRepositories.swift
// Décorateurs de cache (T-112) : se conforment aux protocoles de RepositoryProtocols.swift sans les changer.
// Lecture : cache si présent et pas expiré, sinon dépôt sous-jacent puis mise en cache.
// Écriture : délègue, puis met à jour ou invalide les entrées touchées.
// Temps réel : chaque snapshot remplace l'entrée (et les listes qui la contiennent) avant d'être ré-émis.

import Foundation

/// Commandes groupées et parts, avec cache.
nonisolated struct CachedGroupOrderRepository: GroupOrderRepository {
    let base: any GroupOrderRepository
    let cache: RepositoryCache

    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder] {
        let base = base
        return try await cache.cached(.groupOrdersOfGroup(groupId)) { try await base.groupOrders(ofGroup: groupId) }
    }

    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder] {
        let base = base
        return try await cache.cached(.groupOrdersOfOffer(offerId)) { try await base.groupOrders(ofOffer: offerId) }
    }

    @discardableResult
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder {
        let order = try await base.openGroupOrder(groupId: groupId, offerId: offerId)
        await cache.store(order, for: .groupOrder(order.id))
        // Une commande a pu être créée : les listes du groupe et du lot sont relues.
        await cache.invalidate(.groupOrdersOfGroup(order.groupId))
        await cache.invalidate(.groupOrdersOfOffer(order.offerId))
        return order
    }

    func groupOrder(id: String) async throws -> GroupOrder {
        let base = base
        return try await cache.cached(.groupOrder(id)) { try await base.groupOrder(id: id) }
    }

    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share] {
        let base = base
        return try await cache.cached(.shares(ofGroupOrder: groupOrderId)) {
            try await base.shares(ofGroupOrder: groupOrderId)
        }
    }

    /// T-174 : lecture directe (un ancien membre ne peut lire que sa propre part, pas toute la liste en cache).
    func share(ofHousehold householdId: String, inGroupOrder groupOrderId: String) async throws -> Share? {
        try await base.share(ofHousehold: householdId, inGroupOrder: groupOrderId)
    }

    @discardableResult
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder {
        let order = try await base.setShare(quantity: quantity, householdId: householdId, groupOrderId: groupOrderId)
        await Self.apply(order, to: cache)
        return order
    }

    @discardableResult
    func setSuspendedBasket(_ amountCents: Cents, householdId: String, groupOrderId: String) async throws -> Share {
        let share = try await base.setSuspendedBasket(amountCents, householdId: householdId, groupOrderId: groupOrderId)
        await cache.invalidate(.shares(ofGroupOrder: groupOrderId))
        return share
    }

    @discardableResult
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder {
        let order = try await base.setPickupPoint(pickupPointId, slots: slots, groupOrderId: groupOrderId)
        // Les réservations sur un créneau retiré sont effacées : `apply` fait aussi relire les parts.
        await Self.apply(order, to: cache)
        return order
    }

    @discardableResult
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share {
        let share = try await base.reservePickupSlot(start: start, householdId: householdId, groupOrderId: groupOrderId)
        await cache.invalidate(.shares(ofGroupOrder: groupOrderId))
        return share
    }

    @discardableResult
    func confirmPickup(code: String, groupOrderId: String, at date: Date) async throws -> PickupDesk.ScanResult {
        let result = try await base.confirmPickup(code: code, groupOrderId: groupOrderId, at: date)
        await cache.invalidate(.shares(ofGroupOrder: groupOrderId))
        return result
    }

    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error> {
        let cache = cache
        return relayingSnapshots(
            of: await base.observeGroupOrder(id: id),
            apply: { order in await Self.apply(order, to: cache) },
            onFailure: { await cache.invalidate(.groupOrder(id)) }
        )
    }

    /// Nouvel état d'une commande : remplace l'entrée et les listes, et fait relire les parts.
    private static func apply(_ order: GroupOrder, to cache: RepositoryCache) async {
        await cache.store(order, for: .groupOrder(order.id))
        await cache.replaceInLists(order) { key in
            key == .groupOrdersOfGroup(order.groupId) || key == .groupOrdersOfOffer(order.offerId)
        }
        await cache.invalidate(.shares(ofGroupOrder: order.id))
    }
}

/// Lots, avec cache.
nonisolated struct CachedOfferRepository: OfferRepository {
    let base: any OfferRepository
    let cache: RepositoryCache

    func activeOffers(inZone zone: String?) async throws -> [Offer] {
        let base = base
        return try await cache.cached(.activeOffers(zone: zone)) { try await base.activeOffers(inZone: zone) }
    }

    func offers(ofVendor vendorId: String) async throws -> [Offer] {
        let base = base
        return try await cache.cached(.offersOfVendor(vendorId)) { try await base.offers(ofVendor: vendorId) }
    }

    func offer(id: String) async throws -> Offer {
        let base = base
        return try await cache.cached(.offer(id)) { try await base.offer(id: id) }
    }

    func saveOffer(_ offer: Offer) async throws {
        try await base.saveOffer(offer)
        await cache.store(offer, for: .offer(offer.id))
        // Statut, zones ou date limite ont pu changer : les fils sont relus.
        await cache.invalidate(.offersOfVendor(offer.vendorId))
        await cache.invalidate { key in
            if case .activeOffers = key { return true }
            return false
        }
    }
}

/// Groupes de quartier et membres, avec cache.
nonisolated struct CachedGroupRepository: GroupRepository {
    let base: any GroupRepository
    let cache: RepositoryCache

    func groups(inNeighborhood neighborhood: String?) async throws -> [NeighborhoodGroup] {
        let base = base
        return try await cache.cached(.groupsInNeighborhood(neighborhood)) {
            try await base.groups(inNeighborhood: neighborhood)
        }
    }

    func group(id: String) async throws -> NeighborhoodGroup {
        let base = base
        return try await cache.cached(.group(id)) { try await base.group(id: id) }
    }

    func groups(ofHousehold householdId: String) async throws -> [NeighborhoodGroup] {
        let base = base
        return try await cache.cached(.groupsOfHousehold(householdId)) {
            try await base.groups(ofHousehold: householdId)
        }
    }

    func members(ofGroup groupId: String) async throws -> [GroupMember] {
        let base = base
        return try await cache.cached(.members(ofGroup: groupId)) { try await base.members(ofGroup: groupId) }
    }

    func join(groupId: String, householdId: String) async throws {
        try await base.join(groupId: groupId, householdId: householdId)
        await Self.invalidateMembership(groupId: groupId, householdId: householdId, in: cache)
    }

    func leave(groupId: String, householdId: String) async throws {
        try await base.leave(groupId: groupId, householdId: householdId)
        await Self.invalidateMembership(groupId: groupId, householdId: householdId, in: cache)
    }

    /// T-122 : la fiche et les listes qui contiennent le groupe sont relues avec la nouvelle image.
    func updateImage(_ kind: GroupImageKind, url: URL?, ofGroup groupId: String, byUserId userId: String) async throws {
        try await base.updateImage(kind, url: url, ofGroup: groupId, byUserId: userId)
        await cache.invalidate(.group(groupId))
        await cache.invalidate { key in
            switch key {
            case .groupsInNeighborhood, .groupsOfHousehold: true
            default: false
            }
        }
    }

    /// B-036 : la fiche et les listes qui contiennent le groupe sont relues avec la nouvelle marque.
    func updateBranding(_ branding: GroupBranding, ofGroup groupId: String, byUserId userId: String) async throws {
        try await base.updateBranding(branding, ofGroup: groupId, byUserId: userId)
        await cache.invalidate(.group(groupId))
        await cache.invalidate { key in
            switch key {
            case .groupsInNeighborhood, .groupsOfHousehold: true
            default: false
            }
        }
    }

    func observeGroup(id: String) async -> AsyncThrowingStream<NeighborhoodGroup, any Error> {
        let cache = cache
        return relayingSnapshots(
            of: await base.observeGroup(id: id),
            apply: { group in
                await cache.store(group, for: .group(group.id))
                await cache.replaceInLists(group) { key in
                    switch key {
                    case .groupsInNeighborhood, .groupsOfHousehold: true
                    default: false
                    }
                }
            },
            onFailure: { await cache.invalidate(.group(id)) }
        )
    }

    /// FB-22 : chaque changement d'adhésion (vu en direct) fait relire les listes de groupes du ménage
    /// et les membres des groupes concernés.
    func observeGroupIds(ofHousehold householdId: String) async -> AsyncThrowingStream<Set<String>, any Error> {
        let cache = cache
        let known = GroupIdsBox()
        return relayingSnapshots(
            of: await base.observeGroupIds(ofHousehold: householdId),
            apply: { ids in
                guard let changed = await known.swap(ids) else { return }
                for groupId in changed {
                    await Self.invalidateMembership(groupId: groupId, householdId: householdId, in: cache)
                }
            },
            onFailure: { await cache.invalidate(.groupsOfHousehold(householdId)) }
        )
    }

    /// Le nombre de ménages du groupe et la liste des groupes du ménage ont changé.
    // MARK: B-056 (invitations jamais mises en cache : le créateur doit voir leur état réel)

    func setVisibility(isPublic: Bool, ofGroup groupId: String, byUserId userId: String) async throws -> NeighborhoodGroup {
        let group = try await base.setVisibility(isPublic: isPublic, ofGroup: groupId, byUserId: userId)
        await cache.invalidate(.group(groupId))
        await cache.invalidate { key in
            switch key {
            case .groupsInNeighborhood, .groupsOfHousehold: true
            default: false
            }
        }
        return group
    }

    func invitations(ofGroup groupId: String, byUserId userId: String) async throws -> [GroupInvitation] {
        try await base.invitations(ofGroup: groupId, byUserId: userId)
    }

    func createInvitation(forGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation {
        try await base.createInvitation(forGroup: groupId, byUserId: userId)
    }

    func revokeInvitation(code: String, ofGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation {
        try await base.revokeInvitation(code: code, ofGroup: groupId, byUserId: userId)
    }

    func join(withCode code: String, householdId: String) async throws -> NeighborhoodGroup {
        let group = try await base.join(withCode: code, householdId: householdId)
        await Self.invalidateMembership(groupId: group.id, householdId: householdId, in: cache)
        return group
    }

    func createGroup(_ draft: GroupRules.Draft, byUserId userId: String, householdId: String) async throws -> NeighborhoodGroup {
        let group = try await base.createGroup(draft, byUserId: userId, householdId: householdId)
        await Self.invalidateMembership(groupId: group.id, householdId: householdId, in: cache)
        return group
    }

    /// T-174 : avis lus sans cache (rares, et toujours frais après une note).
    func ratings(ofGroup groupId: String) async throws -> [GroupRating] {
        try await base.ratings(ofGroup: groupId)
    }

    /// T-174 : la note moyenne change sur la fiche et sur les cartes des listes.
    func saveRating(_ rating: GroupRating) async throws -> NeighborhoodGroup {
        let group = try await base.saveRating(rating)
        await cache.store(group, for: .group(group.id))
        await cache.replaceInLists(group) { key in
            switch key {
            case .groupsInNeighborhood, .groupsOfHousehold: true
            default: false
            }
        }
        return group
    }

    private static func invalidateMembership(groupId: String, householdId: String, in cache: RepositoryCache) async {
        await cache.invalidate(.group(groupId))
        await cache.invalidate(.members(ofGroup: groupId))
        await cache.invalidate(.groupsOfHousehold(householdId))
        await cache.invalidate { key in
            if case .groupsInNeighborhood = key { return true }
            return false
        }
    }
}

/// Derniers ids reçus par `observeGroupIds` : le premier état ne vide pas le cache, les suivants
/// rendent les groupes ajoutés ou retirés.
private actor GroupIdsBox {
    private var ids: Set<String>?

    func swap(_ new: Set<String>) -> Set<String>? {
        defer { ids = new }
        guard let ids else { return nil }
        return ids.symmetricDifference(new)
    }
}
