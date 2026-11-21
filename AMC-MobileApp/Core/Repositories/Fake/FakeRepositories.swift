// FakeRepositories.swift
// Implémentations en mémoire des dépôts, pour les previews et les tests.

import Foundation

actor FakeUserRepository: UserRepository {
    private let behavior: FakeBehavior
    private var users: [String: AppUser]
    private var households: [String: Household]

    init(behavior: FakeBehavior = .instant, users: [AppUser] = [], households: [Household] = []) {
        self.behavior = behavior
        self.users = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        self.households = Dictionary(uniqueKeysWithValues: households.map { ($0.id, $0) })
    }

    func user(id: String) async throws -> AppUser {
        try await behavior.simulate()
        guard let user = users[id] else { throw AppError.notFound }
        return user
    }

    func saveUser(_ user: AppUser) async throws {
        try await behavior.simulate()
        users[user.id] = user
    }

    func household(id: String) async throws -> Household {
        try await behavior.simulate()
        guard let household = households[id] else { throw AppError.notFound }
        return household
    }

    func saveHousehold(_ household: Household) async throws {
        try await behavior.simulate()
        households[household.id] = household
    }

    /// Suppression du compte (`FakeAuthService.deleteAccount()`) : retire l'uid du ménage, puis efface l'utilisateur.
    /// Le ménage reste (les règles interdisent de le supprimer).
    func removeUserAndLeaveHousehold(id: String) {
        if let householdId = users[id]?.householdId, var household = households[householdId] {
            household.userIds.removeAll { $0 == id }
            households[householdId] = household
        }
        users[id] = nil
    }
}

actor FakeGroupRepository: GroupRepository {
    private let behavior: FakeBehavior
    private var groups: [String: NeighborhoodGroup]
    private var members: [String: [GroupMember]]
    /// B-056 : invitations à usage unique, par code.
    private var invitations: [String: GroupInvitation]
    private var broadcaster = FakeBroadcaster<NeighborhoodGroup>()

    init(behavior: FakeBehavior = .instant, groups: [NeighborhoodGroup] = [], members: [String: [GroupMember]] = [:],
         invitations: [GroupInvitation] = []) {
        self.behavior = behavior
        self.groups = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        self.members = members
        self.invitations = Dictionary(invitations.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func groups(inNeighborhood neighborhood: String?) async throws -> [NeighborhoodGroup] {
        try await behavior.simulate()
        return groups.values
            .filter { $0.isPublic && (neighborhood == nil || $0.neighborhood == neighborhood) }
            .sorted { $0.name < $1.name }
    }

    func group(id: String) async throws -> NeighborhoodGroup {
        try await behavior.simulate()
        guard let group = groups[id] else { throw AppError.notFound }
        return group
    }

    func groups(ofHousehold householdId: String) async throws -> [NeighborhoodGroup] {
        try await behavior.simulate()
        return members
            .filter { _, groupMembers in groupMembers.contains { $0.householdId == householdId } }
            .compactMap { groupId, _ in groups[groupId] }
            .sorted { $0.name < $1.name }
    }

    func members(ofGroup groupId: String) async throws -> [GroupMember] {
        try await behavior.simulate()
        guard groups[groupId] != nil else { throw AppError.notFound }
        return members[groupId, default: []]
    }

    func join(groupId: String, householdId: String) async throws {
        try await behavior.simulate()
        guard let group = groups[groupId] else { throw AppError.notFound }
        guard !isMember(householdId, of: groupId) else { return }
        // Même règle que firestore.rules (B-056) : un groupe privé s'ouvre seulement avec une invitation.
        guard group.isPublic else { throw AppError.permissionDenied }
        addMember(householdId, to: group)
    }

    // MARK: B-056 Visibilité et invitations

    func setVisibility(isPublic: Bool, ofGroup groupId: String, byUserId userId: String) async throws -> NeighborhoodGroup {
        try await behavior.simulate()
        guard var group = groups[groupId] else { throw AppError.notFound }
        try GroupRules.requireCreator(userId, of: group)
        group.isPublic = isPublic
        update(group)
        return group
    }

    func invitations(ofGroup groupId: String, byUserId userId: String) async throws -> [GroupInvitation] {
        try await behavior.simulate()
        guard let group = groups[groupId] else { throw AppError.notFound }
        try GroupRules.requireCreator(userId, of: group)
        return GroupRules.sortedForDisplay(invitations.values.filter { $0.groupId == groupId })
    }

    func createInvitation(forGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation {
        try await behavior.simulate()
        guard let group = groups[groupId] else { throw AppError.notFound }
        let taken = Set(invitations.keys).union(groups.values.map(\.inviteCode))
        let invitation = try GroupRules.makeInvitation(for: group, byUserId: userId, existingCodes: taken)
        invitations[invitation.code] = invitation
        return invitation
    }

    func revokeInvitation(code: String, ofGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation {
        try await behavior.simulate()
        guard let group = groups[groupId] else { throw AppError.notFound }
        let code = GroupRules.normalizedInviteCode(code)
        guard let invitation = invitations[code] else { throw AppError.notFound }
        let revoked = try GroupRules.revoking(invitation, in: group, byUserId: userId)
        invitations[code] = revoked
        return revoked
    }

    func join(withCode input: String, householdId: String) async throws -> NeighborhoodGroup {
        try await behavior.simulate()
        let code = try GroupRules.validatedInviteCode(GroupRules.inviteCode(fromUserInput: input) ?? input)
        if let invitation = invitations[code] {
            guard let group = groups[invitation.groupId] else { throw AppError.notFound }
            if isMember(householdId, of: group.id) { return group }
            // Consommation et adhésion ensemble (la transaction Firestore fait de même).
            invitations[code] = try GroupRules.consuming(invitation, byHousehold: householdId)
            return addMember(householdId, to: group)
        }
        guard let group = groups.values.first(where: { GroupRules.acceptsFixedCode($0, code: code) }) else {
            throw GroupRules.unknownInviteCodeError
        }
        if isMember(householdId, of: group.id) { return group }
        return addMember(householdId, to: group)
    }

    // MARK: B-059 Création

    func createGroup(_ draft: GroupRules.Draft, byUserId userId: String, householdId: String) async throws -> NeighborhoodGroup {
        try await behavior.simulate()
        let householdGroupIds = members.filter { _, list in list.contains { $0.householdId == householdId } }.map(\.key)
        try GroupRules.requireRoomToCreate(householdGroupIds: householdGroupIds)
        let taken = Set(invitations.keys).union(groups.values.map(\.inviteCode))
        let creation = try GroupRules.makeGroup(
            from: draft, creatorUserId: userId, creatorHouseholdId: householdId,
            makeInviteCode: { var rng = SystemRandomNumberGenerator(); return GroupRules.generateInviteCode(avoiding: taken, using: &rng) }
        )
        members[creation.group.id] = [creation.creatorMember]
        update(creation.group)
        return creation.group
    }

    private func isMember(_ householdId: String, of groupId: String) -> Bool {
        members[groupId, default: []].contains { $0.householdId == householdId }
    }

    @discardableResult
    private func addMember(_ householdId: String, to group: NeighborhoodGroup) -> NeighborhoodGroup {
        var group = group
        members[group.id, default: []].append(GroupMember(householdId: householdId, role: .member, joinedAt: .now))
        group.householdCount += 1
        update(group)
        return group
    }

    func leave(groupId: String, householdId: String) async throws {
        try await behavior.simulate()
        guard var group = groups[groupId] else { throw AppError.notFound }
        let before = members[groupId, default: []].count
        members[groupId]?.removeAll { $0.householdId == householdId }
        guard members[groupId, default: []].count < before else { return }
        group.householdCount = max(0, group.householdCount - 1)
        update(group)
    }

    func observeGroup(id: String) async -> AsyncThrowingStream<NeighborhoodGroup, any Error> {
        let (stream, continuation) = AsyncThrowingStream<NeighborhoodGroup, any Error>.makeStream()
        guard let group = groups[id] else {
            continuation.finish(throwing: AppError.notFound)
            return stream
        }
        let token = broadcaster.add(continuation, for: id)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopObserving(token: token, id: id) }
        }
        continuation.yield(group)
        return stream
    }

    func updateImage(_ kind: GroupImageKind, url: URL?, ofGroup groupId: String, byUserId userId: String) async throws {
        try await behavior.simulate()
        guard var group = groups[groupId] else { throw AppError.notFound }
        // Même règle que firestore.rules : seul un coordinateur change les images du groupe.
        guard group.coordinatorIds.contains(userId) else { throw AppError.permissionDenied }
        switch kind {
        case .photo: group.photoURL = url
        case .banner: group.bannerURL = url
        }
        update(group)
    }

    func updateBranding(_ branding: GroupBranding, ofGroup groupId: String, byUserId userId: String) async throws {
        try await behavior.simulate()
        guard var group = groups[groupId] else { throw AppError.notFound }
        // Même règle que firestore.rules (B-036) : seul un coordinateur change la marque.
        guard group.coordinatorIds.contains(userId) else { throw AppError.permissionDenied }
        group.branding = branding == GroupBranding() ? nil : branding
        update(group)
    }

    private func update(_ group: NeighborhoodGroup) {
        groups[group.id] = group
        broadcaster.send(group, for: group.id)
    }

    private func stopObserving(token: UUID, id: String) {
        broadcaster.remove(token: token, for: id)
    }
}

actor FakeVendorRepository: VendorRepository {
    private let behavior: FakeBehavior
    private var vendors: [String: Vendor]
    private var products: [String: Product]

    init(behavior: FakeBehavior = .instant, vendors: [Vendor] = [], products: [Product] = []) {
        self.behavior = behavior
        self.vendors = Dictionary(uniqueKeysWithValues: vendors.map { ($0.id, $0) })
        self.products = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    func vendors() async throws -> [Vendor] {
        try await behavior.simulate()
        return vendors.values.sorted { $0.legalName < $1.legalName }
    }

    func vendor(id: String) async throws -> Vendor {
        try await behavior.simulate()
        guard let vendor = vendors[id] else { throw AppError.notFound }
        return vendor
    }

    func products(ofVendor vendorId: String) async throws -> [Product] {
        try await behavior.simulate()
        return products.values.filter { $0.vendorId == vendorId }.sorted { $0.name < $1.name }
    }

    func product(id: String) async throws -> Product {
        try await behavior.simulate()
        guard let product = products[id] else { throw AppError.notFound }
        return product
    }

    func saveProduct(_ product: Product) async throws {
        try await behavior.simulate()
        guard vendors[product.vendorId] != nil else { throw AppError.notFound }
        products[product.id] = product
    }

    func deleteProduct(id: String) async throws {
        try await behavior.simulate()
        guard products.removeValue(forKey: id) != nil else { throw AppError.notFound }
    }

    func saveVendor(_ vendor: Vendor) async throws {
        try await behavior.simulate()
        guard let current = vendors[vendor.id] else { throw AppError.notFound }
        // Comme firestore.rules : raison sociale, type, note et vérification restent en lecture seule.
        guard current.legalName == vendor.legalName, current.kind == vendor.kind,
              current.averageRating == vendor.averageRating, current.isVerified == vendor.isVerified,
              current.city == vendor.city, current.memberSince == vendor.memberSince,
              current.storefrontGeohash == vendor.storefrontGeohash
        else { throw AppError.permissionDenied }
        vendors[vendor.id] = vendor
    }
}

actor FakeOfferRepository: OfferRepository {
    private let behavior: FakeBehavior
    private var offers: [String: Offer]

    init(behavior: FakeBehavior = .instant, offers: [Offer] = []) {
        self.behavior = behavior
        self.offers = Dictionary(uniqueKeysWithValues: offers.map { ($0.id, $0) })
    }

    func activeOffers(inZone zone: String?) async throws -> [Offer] {
        try await behavior.simulate()
        return offers.values
            .filter { offer in
                // Préfixes geohash : la zone du lot contient la zone demandée, ou l'inverse.
                offer.status == .active
                    && (zone.map { zone in offer.zones.contains { zone.hasPrefix($0) || $0.hasPrefix(zone) } } ?? true)
            }
            .sorted { $0.deadline < $1.deadline }
    }

    func offers(ofVendor vendorId: String) async throws -> [Offer] {
        try await behavior.simulate()
        return offers.values.filter { $0.vendorId == vendorId }.sorted { $0.deadline < $1.deadline }
    }

    func offer(id: String) async throws -> Offer {
        try await behavior.simulate()
        guard let offer = offers[id] else { throw AppError.notFound }
        return offer
    }

    func saveOffer(_ offer: Offer) async throws {
        try await behavior.simulate()
        guard !offer.tiers.isEmpty else { throw AppError.invalidInput("Ajoute au moins un palier de prix.") }
        offers[offer.id] = offer
    }
}

actor FakeGroupOrderRepository: GroupOrderRepository {
    private let behavior: FakeBehavior
    private var groupOrders: [String: GroupOrder]
    private var shares: [String: [Share]]
    private let offers: [String: Offer]
    private let now: @Sendable () -> Date
    private var broadcaster = FakeBroadcaster<GroupOrder>()

    init(
        behavior: FakeBehavior = .instant,
        groupOrders: [GroupOrder] = [],
        shares: [String: [Share]] = [:],
        offers: [Offer] = [],
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.behavior = behavior
        self.now = now
        self.groupOrders = Dictionary(uniqueKeysWithValues: groupOrders.map { ($0.id, $0) })
        self.shares = shares
        self.offers = Dictionary(uniqueKeysWithValues: offers.map { ($0.id, $0) })
    }

    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder] {
        try await behavior.simulate()
        return groupOrders.values.filter { $0.groupId == groupId }.sorted { $0.id < $1.id }
    }

    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder] {
        try await behavior.simulate()
        return groupOrders.values.filter { $0.offerId == offerId }.sorted { $0.id < $1.id }
    }

    @discardableResult
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder {
        try await behavior.simulate()
        guard let offer = offers[offerId] else { throw AppError.notFound }
        if let existing = groupOrders.values.first(where: {
            $0.groupId == groupId && $0.offerId == offerId && ($0.status == .open || $0.status == .reached)
        }) {
            return existing
        }
        guard offer.status == .active, offer.deadline > now() else { throw AppError.orderClosed }
        var id = "order-\(groupId)-\(offerId)"
        var suffix = 2
        while groupOrders[id] != nil {
            id = "order-\(groupId)-\(offerId)-\(suffix)"
            suffix += 1
        }
        let order = GroupOrder(
            id: id, groupId: groupId, offerId: offerId, status: .open, currentTierIndex: nil,
            committedShares: 0, committedHouseholds: 0, pickupPointId: nil, pickupSlots: []
        )
        groupOrders[id] = order
        shares[id] = []
        return order
    }

    func groupOrder(id: String) async throws -> GroupOrder {
        try await behavior.simulate()
        guard let order = groupOrders[id] else { throw AppError.notFound }
        return order
    }

    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share] {
        try await behavior.simulate()
        guard groupOrders[groupOrderId] != nil else { throw AppError.notFound }
        return shares[groupOrderId, default: []]
    }

    @discardableResult
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder {
        try await behavior.simulate()
        guard let order = groupOrders[groupOrderId], let offer = offers[order.offerId] else { throw AppError.notFound }
        guard TierEngine.isOpen(order) else { throw AppError.orderClosed }
        guard quantity >= 0 else { throw AppError.invalidInput("La quantité ne peut pas être négative.") }

        var orderShares = shares[groupOrderId, default: []]
        let othersTotal = orderShares.filter { $0.householdId != householdId }.reduce(0) { $0 + $1.quantity }
        guard othersTotal + quantity <= offer.totalShares else {
            throw AppError.invalidInput("Il ne reste que \(offer.totalShares - othersTotal) parts dans ce lot.")
        }

        if let index = orderShares.firstIndex(where: { $0.householdId == householdId }) {
            if quantity == 0 {
                orderShares.remove(at: index)
            } else {
                orderShares[index].quantity = quantity
                orderShares[index].updatedAt = now()
            }
        } else if quantity > 0 {
            orderShares.append(Share(
                householdId: householdId, quantity: quantity, finalPriceCents: nil, isPaid: false,
                suspendedAmountCents: 0, subsidyCents: 0, qrCode: nil, isPickedUp: false, updatedAt: now()
            ))
        }
        // Même recalcul que la transaction Firestore (RQ-051).
        let updated = try TierEngine.recalculated(order, offer: offer, shares: orderShares)
        shares[groupOrderId] = orderShares
        groupOrders[groupOrderId] = updated
        broadcaster.send(updated, for: groupOrderId)
        return updated
    }

    @discardableResult
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder {
        try await behavior.simulate()
        guard var order = groupOrders[groupOrderId] else { throw AppError.notFound }
        guard order.status != .cancelled, order.status != .delivered else { throw AppError.orderClosed }
        let slots = pickupPointId == nil ? [] : try PickupSlotBook.validatedSlots(slots)
        order.pickupPointId = pickupPointId
        order.pickupSlots = slots
        shares[groupOrderId] = PickupSlotBook.clearingRemovedSlots(shares[groupOrderId, default: []], keeping: slots)
        groupOrders[groupOrderId] = order
        broadcaster.send(order, for: groupOrderId)
        return order
    }

    @discardableResult
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share {
        try await behavior.simulate()
        guard let order = groupOrders[groupOrderId] else { throw AppError.notFound }
        guard order.status != .cancelled, order.status != .delivered else { throw AppError.orderClosed }
        var orderShares = shares[groupOrderId, default: []]
        let share = try PickupSlotBook.reserving(
            start, householdId: householdId, slots: order.pickupSlots, shares: orderShares, now: now()
        )
        if let index = orderShares.firstIndex(where: { $0.householdId == householdId }) {
            orderShares[index] = share
        }
        shares[groupOrderId] = orderShares
        return share
    }

    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error> {
        let (stream, continuation) = AsyncThrowingStream<GroupOrder, any Error>.makeStream()
        guard let order = groupOrders[id] else {
            continuation.finish(throwing: AppError.notFound)
            return stream
        }
        let token = broadcaster.add(continuation, for: id)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopObserving(token: token, id: id) }
        }
        continuation.yield(order)
        return stream
    }

    private func stopObserving(token: UUID, id: String) {
        broadcaster.remove(token: token, for: id)
    }
}

actor FakePickupPointRepository: PickupPointRepository {
    private let behavior: FakeBehavior
    private var pickupPoints: [String: PickupPoint]

    init(behavior: FakeBehavior = .instant, pickupPoints: [PickupPoint] = []) {
        self.behavior = behavior
        self.pickupPoints = Dictionary(uniqueKeysWithValues: pickupPoints.map { ($0.id, $0) })
    }

    func pickupPoints() async throws -> [PickupPoint] {
        try await behavior.simulate()
        return pickupPoints.values.sorted { $0.name < $1.name }
    }

    func pickupPoint(id: String) async throws -> PickupPoint {
        try await behavior.simulate()
        guard let point = pickupPoints[id] else { throw AppError.notFound }
        return point
    }

    func savePickupPoint(_ point: PickupPoint) async throws {
        try await behavior.simulate()
        if let existing = pickupPoints[point.id], existing.hostUserId != point.hostUserId {
            throw AppError.permissionDenied
        }
        pickupPoints[point.id] = try PickupSlotBook.validatedPoint(point)
    }
}
