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
    /// Groupes dont le ménage est membre, publics ou privés, triés par nom.
    func groups(ofHousehold householdId: String) async throws -> [NeighborhoodGroup]
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
    /// Retire un produit du catalogue (T-089). Lève `.notFound` si l'id est inconnu ;
    /// firestore.rules n'autorise que le vendeur propriétaire.
    func deleteProduct(id: String) async throws
    /// Enregistre le profil du vendeur. Seuls `description`, `photoURLs` et `servedZones` peuvent changer
    /// (firestore.rules) ; tout autre changement lève `.permissionDenied`, un id inconnu `.notFound`.
    func saveVendor(_ vendor: Vendor) async throws
}

extension VendorRepository {
    /// Par défaut (dépôt qui ne l'implémente pas encore) : refus explicite plutôt qu'un succès silencieux.
    func deleteProduct(id: String) async throws {
        throw AppError.unknown("deleteProduct n'est pas encore branché sur ce dépôt.")
    }
}

/// Lots (`offers`).
nonisolated protocol OfferRepository: Sendable {
    /// Fil des lots actifs qui desservent la zone ; `nil` = toutes les zones.
    /// `zone` et `Offer.zones` sont des geohash de longueurs différentes (lot : préfixe court comme « f25d » ;
    /// groupe : « f25dv… »). Un lot est visible dans la zone si une de ses zones est un préfixe de `zone`,
    /// ou si `zone` est un préfixe d'une de ses zones (zone demandée plus large). Pas d'égalité exacte.
    func activeOffers(inZone zone: String?) async throws -> [Offer]
    func offers(ofVendor vendorId: String) async throws -> [Offer]
    func offer(id: String) async throws -> Offer
    func saveOffer(_ offer: Offer) async throws
}

/// Commandes groupées (`groupOrders`) et parts (`shares`).
nonisolated protocol GroupOrderRepository: Sendable {
    func groupOrders(ofGroup groupId: String) async throws -> [GroupOrder]
    /// Commandes groupées d'un lot, tous groupes confondus (publics et privés).
    func groupOrders(ofOffer offerId: String) async throws -> [GroupOrder]
    /// Commande ouverte du groupe sur ce lot : la renvoie si elle existe (ouverte ou palier atteint),
    /// sinon la crée vide. Lève `.notFound` si le lot n'existe pas, `.orderClosed` si le lot
    /// n'est plus actif ou que sa date limite est passée.
    @discardableResult
    func openGroupOrder(groupId: String, offerId: String) async throws -> GroupOrder
    func groupOrder(id: String) async throws -> GroupOrder
    func shares(ofGroupOrder groupOrderId: String) async throws -> [Share]
    /// Ajoute ou change la part d'un ménage et recalcule quantité, ménages et palier en une fois.
    /// `quantity == 0` retire la part. Lève `.orderClosed` si la commande n'est plus ouverte.
    @discardableResult
    func setShare(quantity: Int, householdId: String, groupOrderId: String) async throws -> GroupOrder
    /// Écoute en temps réel : émet l'état courant, puis chaque changement.
    func observeGroupOrder(id: String) async -> AsyncThrowingStream<GroupOrder, any Error>
    /// RQ-063 : le coordonnateur choisit le point de cueillette et ses créneaux ; `nil` retire le point.
    /// Les réservations des ménages sur un créneau retiré sont effacées. Lève `.orderClosed` si la commande
    /// est annulée ou livrée.
    @discardableResult
    func setPickupPoint(_ pickupPointId: String?, slots: [PickupSlot], groupOrderId: String) async throws -> GroupOrder
    /// RQ-064 : le ménage réserve un créneau (`start` d'un des `pickupSlots`) ; `nil` annule la réservation.
    /// Lève `.notFound` sans part, `.invalidInput` si le créneau est inconnu ou complet.
    @discardableResult
    func reservePickupSlot(start: Date?, householdId: String, groupOrderId: String) async throws -> Share
}

/// Points de cueillette (`pickupPoints`).
nonisolated protocol PickupPointRepository: Sendable {
    func pickupPoints() async throws -> [PickupPoint]
    func pickupPoint(id: String) async throws -> PickupPoint
    /// RQ-062 : crée ou modifie le point d'un hôte (même id = mise à jour).
    func savePickupPoint(_ point: PickupPoint) async throws
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
