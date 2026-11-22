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

    // T-159 : plusieurs comptes dans un ménage.

    /// Ménage inscrit à l'adresse `lookupId` (`HouseholdAddress.lookupId`), `nil` s'il n'y en a pas.
    /// Lecture par id exact seulement : on ne liste jamais les adresses.
    func householdAddress(lookupId: String) async throws -> HouseholdAddressEntry?
    /// Inscrit le ménage à son adresse. Sans effet si un autre ménage y est déjà inscrit (le premier reste trouvable).
    func registerHouseholdAddress(_ entry: HouseholdAddressEntry) async throws
    /// Crée (ou remplace) la demande de `request.userId` pour rejoindre `request.householdId`.
    func requestToJoin(_ request: HouseholdJoinRequest) async throws
    /// Demande de `userId` pour `householdId`, `nil` si elle n'existe plus (refusée ou annulée).
    func joinRequest(householdId: String, userId: String) async throws -> HouseholdJoinRequest?
    /// Demandes en attente du ménage, les plus anciennes d'abord. Le propriétaire seulement (`.permissionDenied` sinon).
    func joinRequests(ofHousehold householdId: String, byUserId userId: String) async throws -> [HouseholdJoinRequest]
    /// Supprime la demande : annulée par la personne, ou refusée par le propriétaire.
    func deleteJoinRequest(householdId: String, userId: String) async throws
    /// Le propriétaire accepte : `userId` entre dans `userIds` et la demande passe à `.accepted`.
    func acceptJoinRequest(householdId: String, userId: String, byUserId ownerId: String) async throws -> Household
    /// Retire `userId` du ménage : le propriétaire retire un membre, ou un membre se retire lui-même.
    func removeMember(_ userId: String, fromHousehold householdId: String, byUserId callerId: String) async throws -> Household
}

/// Doublures de test d'avant T-159 : pas de ménage partagé.
extension UserRepository {
    func householdAddress(lookupId: String) async throws -> HouseholdAddressEntry? { nil }
    func registerHouseholdAddress(_ entry: HouseholdAddressEntry) async throws {}
    func requestToJoin(_ request: HouseholdJoinRequest) async throws { throw AppError.permissionDenied }
    func joinRequest(householdId: String, userId: String) async throws -> HouseholdJoinRequest? { nil }
    func joinRequests(ofHousehold householdId: String, byUserId userId: String) async throws -> [HouseholdJoinRequest] { [] }
    func deleteJoinRequest(householdId: String, userId: String) async throws {}
    func acceptJoinRequest(householdId: String, userId: String, byUserId ownerId: String) async throws -> Household {
        throw AppError.permissionDenied
    }
    func removeMember(_ userId: String, fromHousehold householdId: String, byUserId callerId: String) async throws -> Household {
        throw AppError.permissionDenied
    }
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
    /// T-122 : pose (ou retire, `url` nil) la photo ou la bannière du groupe. Seul un coordinateur
    /// (`coordinatorIds`) le peut : `.permissionDenied` sinon, `.notFound` si le groupe n'existe pas.
    /// L'image elle-même est dans `AppRepositories.images` ; `url` est son URL versionnée.
    func updateImage(_ kind: GroupImageKind, url: URL?, ofGroup groupId: String, byUserId userId: String) async throws
    /// B-036 : remplace la marque du groupe (`branding`). Seul un coordinateur le peut :
    /// `.permissionDenied` sinon, `.notFound` si le groupe n'existe pas. `GroupBranding()` = marque par défaut.
    func updateBranding(_ branding: GroupBranding, ofGroup groupId: String, byUserId userId: String) async throws

    // B-056 : visibilité et invitations à usage unique. Le créateur du groupe seulement
    // (`GroupRules.isCreator`) : `.permissionDenied` sinon, `.notFound` si le groupe n'existe pas.

    /// Rend le groupe public (listé) ou privé (sur invitation). Renvoie le groupe à jour.
    func setVisibility(isPublic: Bool, ofGroup groupId: String, byUserId userId: String) async throws -> NeighborhoodGroup
    /// Invitations du groupe, actives d'abord (`GroupRules.sortedForDisplay`).
    func invitations(ofGroup groupId: String, byUserId userId: String) async throws -> [GroupInvitation]
    /// Crée une invitation à usage unique.
    func createInvitation(forGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation
    /// Révoque une invitation pas encore utilisée.
    func revokeInvitation(code: String, ofGroup groupId: String, byUserId userId: String) async throws -> GroupInvitation
    /// Rejoint avec un code ou un lien : une invitation à usage unique (consommée dans la même transaction que
    /// l'adhésion) ou le code fixe d'un groupe public. Invitation utilisée ou révoquée : `.invalidInput` au message clair.
    /// Renvoie le groupe rejoint ; déjà membre : sans effet (l'invitation n'est pas consommée).
    func join(withCode code: String, householdId: String) async throws -> NeighborhoodGroup

    /// B-059 : crée un groupe (`GroupRules.makeGroup`) ; le ménage créateur en est le premier membre, coordonnateur.
    /// Groupe, adhésion et compteur dans une seule écriture. Refusé (`.invalidInput`) si le brouillon est invalide
    /// ou si le ménage fait déjà partie de 3 groupes (RQ-030).
    func createGroup(_ draft: GroupRules.Draft, byUserId userId: String, householdId: String) async throws -> NeighborhoodGroup
}

extension GroupRepository {
    /// Par défaut (dépôt qui ne l'implémente pas encore) : refus explicite plutôt qu'un succès silencieux.
    func updateBranding(_ branding: GroupBranding, ofGroup groupId: String, byUserId userId: String) async throws {
        throw AppError.unknown("updateBranding n'est pas encore branché sur ce dépôt.")
    }

    /// Par défaut (dépôt qui ne l'implémente pas encore) : refus explicite plutôt qu'un succès silencieux.
    func updateImage(_ kind: GroupImageKind, url: URL?, ofGroup groupId: String, byUserId userId: String) async throws {
        throw AppError.unknown("updateImage n'est pas encore branché sur ce dépôt.")
    }
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
    /// Enregistre le profil du vendeur. Seuls `description`, `photoURLs`, `servedZones` et `featuredProductIds` peuvent changer
    /// (firestore.rules) ; tout autre changement lève `.permissionDenied`, un id inconnu `.notFound`.
    func saveVendor(_ vendor: Vendor) async throws
    /// Onboarding producteur (T-158) : crée le vendeur d'un compte (`Vendor.ownedId`), non vérifié et sans note.
    /// Relancer avec le même propriétaire réutilise le vendeur déjà créé ; `.permissionDenied` s'il est à un autre.
    func createVendor(_ vendor: Vendor) async throws -> Vendor
}

extension VendorRepository {
    /// Dépôts sans création (stubs de tests) : refusé.
    func createVendor(_ vendor: Vendor) async throws -> Vendor {
        throw AppError.permissionDenied
    }

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

/// Envies des familles (`groups/{groupId}/wishes`) — S-07.
/// Les écrans des familles n'affichent que `demand(ofGroup:)` (anonyme) et les envies de leur propre ménage.
nonisolated protocol GroupWishRepository: Sendable {
    /// Toutes les envies du groupe (membres du groupe et vendeurs seulement, voir firestore.rules).
    func wishes(ofGroup groupId: String) async throws -> [GroupWish]
    /// Envies d'un ménage dans un groupe, les plus anciennes d'abord.
    func wishes(ofHousehold householdId: String, inGroup groupId: String) async throws -> [GroupWish]
    /// Envies de tous les groupes, pour le `Matcher` côté vendeur.
    func allWishes() async throws -> [GroupWish]
    /// Crée l'envie (id attribué s'il est vide, dates posées) et la renvoie telle qu'enregistrée.
    @discardableResult
    func addWish(_ wish: GroupWish) async throws -> GroupWish
    /// Change quantité, unité, rythme, produit ou période. Groupe et ménage ne changent pas
    /// (`.permissionDenied`), un id inconnu lève `.notFound`.
    @discardableResult
    func updateWish(_ wish: GroupWish) async throws -> GroupWish
    func removeWish(id: String, groupId: String) async throws
    /// Écoute en temps réel : émet les envies du groupe, puis à chaque changement.
    func observeWishes(ofGroup groupId: String) async -> AsyncThrowingStream<[GroupWish], any Error>
}

extension GroupWishRepository {
    /// « Ce que le groupe veut » : total par catégorie et nombre de ménages, sans dire qui.
    nonisolated func demand(ofGroup groupId: String) async throws -> [GroupDemand] {
        GroupDemand.aggregate(try await wishes(ofGroup: groupId))
    }

    /// Agrégat en temps réel ; le listener sous-jacent s'arrête quand le flux se termine.
    nonisolated func observeDemand(ofGroup groupId: String) async -> AsyncThrowingStream<[GroupDemand], any Error> {
        let wishes = await observeWishes(ofGroup: groupId)
        let (stream, continuation) = AsyncThrowingStream<[GroupDemand], any Error>.makeStream()
        let task = Task {
            do {
                for try await groupWishes in wishes {
                    continuation.yield(GroupDemand.aggregate(groupWishes))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

/// Disponibilités des vendeurs (`vendors/{vendorId}/supplies`) — S-08.
nonisolated protocol VendorSupplyRepository: Sendable {
    /// Disponibilités du vendeur, par date de début.
    func supplies(ofVendor vendorId: String) async throws -> [VendorSupply]
    /// Disponibilités de tous les vendeurs, pour le `Matcher`.
    func allSupplies() async throws -> [VendorSupply]
    /// Crée la disponibilité (id attribué s'il est vide, dates posées) et la renvoie telle qu'enregistrée.
    @discardableResult
    func addSupply(_ supply: VendorSupply) async throws -> VendorSupply
    /// Le vendeur ne change pas (`.permissionDenied`), un id inconnu lève `.notFound`.
    @discardableResult
    func updateSupply(_ supply: VendorSupply) async throws -> VendorSupply
    func removeSupply(id: String, vendorId: String) async throws
    /// Écoute en temps réel : émet les disponibilités du vendeur, puis à chaque changement.
    func observeSupplies(ofVendor vendorId: String) async -> AsyncThrowingStream<[VendorSupply], any Error>
}

/// Agrégats des arrondissements (`boroughStats`) — RQ-093, lecture seule.
nonisolated protocol BoroughStatsRepository: Sendable {
    /// Tous les arrondissements qui ont des agrégats, dans un ordre quelconque (le classement trie).
    func boroughStats() async throws -> [BoroughStats]
}

/// Tous les dépôts de l'app, à injecter dans les ViewModels.
nonisolated struct AppRepositories: Sendable {
    var users: any UserRepository
    var groups: any GroupRepository
    var vendors: any VendorRepository
    var offers: any OfferRepository
    var groupOrders: any GroupOrderRepository
    var pickupPoints: any PickupPointRepository
    /// S-07, S-08. Valeur par défaut (fakes vides) pour que les appels existants de l'init compilent tels quels.
    var wishes: any GroupWishRepository = FakeGroupWishRepository()
    var supplies: any VendorSupplyRepository = FakeVendorSupplyRepository()
    /// T-122 : photos de profil, de groupe et bannières (base64 dans Firestore en live, mémoire sinon).
    var images: any ImageStore = FakeImageStore()
    /// RQ-093 (T-114). Fake vide par défaut.
    var boroughStats: any BoroughStatsRepository = FakeBoroughStatsRepository()
    /// RQ-069 (T-117) : livraison à domicile par un voisin bénévole.
    var deliveries: any VolunteerDeliveryRepository = FakeVolunteerDeliveryRepository()
    /// T-116 : portail Organismes (fonds de solidarité, financements, parrainages).
    var organizations: any OrganizationRepository = FakeOrganizationRepository(
        organizations: [], profiles: [], donations: [], sponsorships: []
    )
    /// T-157 : avis des familles sur les producteurs et ventes livrées (page producteur). Fake vide par défaut.
    var reviews: any VendorReviewRepository = FakeVendorReviewRepository()

    /// Dépôts en mémoire VIDES (aucune persona de `FakeData`) : repli quand Firebase n'est pas configuré
    /// et contexte non résolu (`AppContext.unresolved`). Un écran qui les lit n'affiche rien plutôt que du faux.
    static func empty() -> AppRepositories {
        AppRepositories(
            users: FakeUserRepository(),
            groups: FakeGroupRepository(),
            vendors: FakeVendorRepository(),
            offers: FakeOfferRepository(),
            groupOrders: FakeGroupOrderRepository(),
            pickupPoints: FakePickupPointRepository(),
            wishes: FakeGroupWishRepository(),
            supplies: FakeVendorSupplyRepository()
        )
    }

    /// Dépôts en mémoire remplis avec `FakeData` : previews, tests et mode `.fake` (`-useFakeData`) seulement.
    static func fake(behavior: FakeBehavior = .realistic, data: FakeData = .montreal) -> AppRepositories {
        AppRepositories(
            users: FakeUserRepository(behavior: behavior, users: data.users, households: data.households,
                                      joinRequests: data.joinRequests),
            groups: FakeGroupRepository(behavior: behavior, groups: data.groups, members: data.members,
                                        invitations: data.invitations),
            vendors: FakeVendorRepository(behavior: behavior, vendors: data.vendors, products: data.products),
            offers: FakeOfferRepository(behavior: behavior, offers: data.offers),
            groupOrders: FakeGroupOrderRepository(
                behavior: behavior, groupOrders: data.groupOrders, shares: data.shares, offers: data.offers
            ),
            pickupPoints: FakePickupPointRepository(behavior: behavior, pickupPoints: data.pickupPoints),
            wishes: FakeGroupWishRepository(behavior: behavior, wishes: FakeData.demoWishes),
            supplies: FakeVendorSupplyRepository(behavior: behavior, supplies: FakeData.demoSupplies),
            images: FakeImageStore(behavior: behavior),
            boroughStats: FakeBoroughStatsRepository(behavior: behavior, stats: FakeData.montrealBoroughs),
            deliveries: FakeVolunteerDeliveryRepository.demo(behavior: behavior),
            organizations: FakeOrganizationRepository(behavior: behavior),
            reviews: FakeVendorReviewRepository(behavior: behavior, reviews: FakeData.demoVendorReviews,
                                                sales: FakeData.demoVendorSales)
        )
    }
}
