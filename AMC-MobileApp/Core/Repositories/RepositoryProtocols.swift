// RepositoryProtocols.swift
// Contrats d'accès aux données de Grenier (B-016, RQ-004).
// Les ViewModels dépendent de ces protocoles, jamais de Firebase. Deux implémentations :
// Fake* (mémoire, previews et tests) et Firestore* (B-017 à B-019).
// Toutes les erreurs levées sont des `AppError`.

import Foundation

/// Utilisateurs (`users`) et ménages (`households`).
nonisolated protocol UserRepository: Sendable {
    func user(id: String) async throws -> AppUser
    func saveUser(_ user: AppUser) async throws
    func household(id: String) async throws -> Household
    func saveHousehold(_ household: Household) async throws
}

/// Groupes de quartier (`groups`) et leurs membres.
nonisolated protocol GroupRepository: Sendable {
    /// Groupes publics d'un quartier ; `nil` = tous.
    func groups(inNeighborhood neighborhood: String?) async throws -> [NeighborhoodGroup]
    func group(id: String) async throws -> NeighborhoodGroup
    func members(ofGroup groupId: String) async throws -> [GroupMember]
    /// Ajoute le ménage au groupe ; sans effet s'il en fait déjà partie.
    func join(groupId: String, householdId: String) async throws
    func leave(groupId: String, householdId: String) async throws
    /// Écoute en temps réel : émet l'état courant, puis chaque changement.
    func observeGroup(id: String) async -> AsyncThrowingStream<NeighborhoodGroup, any Error>
}

/// Vendeurs (`vendors`) et leurs produits (`products`).
nonisolated protocol VendorRepository: Sendable {
    func vendors() async throws -> [Vendor]
    func vendor(id: String) async throws -> Vendor
    func products(ofVendor vendorId: String) async throws -> [Product]
    func product(id: String) async throws -> Product
    func saveProduct(_ product: Product) async throws
}

/// Lots (`offers`).
nonisolated protocol OfferRepository: Sendable {
    /// Fil des lots actifs qui desservent la zone ; `nil` = toutes les zones.
    func activeOffers(inZone zone: String?) async throws -> [Offer]
    func offers(ofVendor vendorId: String) async throws -> [Offer]
    func offer(id: String) async throws -> Offer
    func saveOffer(_ offer: Offer) async throws
}

/// Commandes groupées (`groupOrders`) et parts (`shares`).
nonisolated protocol GroupOrderRepository: Sendable {
    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder]
    func groupOrder(id: String) async throws -> GroupOrder
    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share]
    /// Ajoute ou change la part d'un ménage et recalcule quantité, ménages et palier en une fois.
    /// `quantity == 0` retire la part. Lève `.orderClosed` si la commande n'est plus ouverte.
    @discardableResult
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder
    /// Écoute en temps réel : émet l'état courant, puis chaque changement.
    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error>
}

/// Points de cueillette (`pickupPoints`).
nonisolated protocol PickupPointRepository: Sendable {
    func pickupPoints() async throws -> [PickupPoint]
    func pickupPoint(id: String) async throws -> PickupPoint
}

/// Tous les dépôts de l'app, à injecter dans les ViewModels.
nonisolated struct AppRepositories: Sendable {
    var users: any UserRepository
    var groups: any GroupRepository
    var vendors: any VendorRepository
    var offers: any OfferRepository
    var groupOrders: any GroupOrderRepository
    var pickupPoints: any PickupPointRepository

    /// Dépôts en mémoire remplis avec `FakeData`.
    static func fake(behavior: FakeBehavior = .realistic, data: FakeData = .montreal) -> AppRepositories {
        AppRepositories(
            users: FakeUserRepository(behavior: behavior, users: data.users, households: data.households),
            groups: FakeGroupRepository(behavior: behavior, groups: data.groups, members: data.members),
            vendors: FakeVendorRepository(behavior: behavior, vendors: data.vendors, products: data.products),
            offers: FakeOfferRepository(behavior: behavior, offers: data.offers),
            groupOrders: FakeGroupOrderRepository(
                behavior: behavior, groupOrders: data.groupOrders, shares: data.shares, offers: data.offers
            ),
            pickupPoints: FakePickupPointRepository(behavior: behavior, pickupPoints: data.pickupPoints)
        )
    }
}
