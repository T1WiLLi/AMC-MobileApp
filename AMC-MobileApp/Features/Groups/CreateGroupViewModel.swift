// CreateGroupViewModel.swift
// B-059 : créer un groupe depuis l'app. Nom, quartier, centre sur la carte, rayon de 1 à 2 km, public ou privé.
// Le brouillon passe par `GroupRules.validate` / `makeGroup` (dans le dépôt) ; au plus 3 groupes par ménage (RQ-030).
// Retour samuel : un groupe a toujours sa zone de livraison (point de cueillette : nom + adresse vérifiée par
// Apple). Le vendeur y livre et les familles du groupe y cueillent ; le point est créé avec le groupe
// (hôte = créateur, `groupId` = le groupe) et sert de lieu par défaut à ses commandes.

import Foundation
import Observation

@Observable
@MainActor
final class CreateGroupViewModel {
    var name = ""
    var neighborhood = ""
    /// Centre du groupe, posé en touchant la carte ; au départ, la position approximative du ménage.
    var center: Geohash.Coordinate
    var radiusMeters = 1_500
    var isPublic = true
    /// Zone de livraison : nom du lieu (« Centre communautaire Côte-des-Neiges ») et adresse.
    var pickupName = ""
    var pickupAddress = ""
    /// T-185 : l'adresse du point est vérifiée par Apple ; « vérification impossible » (hors ligne) est acceptée.
    let addressCheck: AddressFieldModel
    /// Position approximative du ménage (bouton « Chez moi » de la carte) ; nil si inconnue.
    private(set) var homeCenter: Geohash.Coordinate?

    private(set) var isSaving = false
    /// Erreur renvoyée par le dépôt (réseau, règles, limite de groupes) ; remise à nil dès qu'on modifie le formulaire.
    private(set) var submitError: String?
    /// Groupe créé : la feuille se ferme et ouvre sa fiche.
    private(set) var createdGroup: NeighborhoodGroup?
    /// Nombre de groupes du ménage ; nil tant qu'il n'est pas chargé.
    private(set) var householdGroupCount: Int?
    /// Groupe déjà créé dont le point n'a pas pu être enregistré : « Créer le groupe » réessaie seulement le point.
    private var pendingGroup: NeighborhoodGroup?

    /// Centre de Montréal, si la position du ménage est inconnue.
    nonisolated static let fallbackCenter = Geohash.Coordinate(latitude: 45.5017, longitude: -73.5673)
    nonisolated static let radiusStep = 100

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String

    init(repositories: AppRepositories, userId: String, householdId: String,
         addressValidator: any AddressValidating = MapKitAddressValidator.shared) {
        self.addressCheck = AddressFieldModel(validator: addressValidator)
        self.repositories = repositories
        self.userId = userId
        self.householdId = householdId
        self.center = Self.fallbackCenter
    }

    /// Préremplit le quartier et le centre, et compte les groupes du ménage.
    func load() async {
        let repositories = repositories, userId = userId, householdId = householdId
        async let user = try? repositories.users.user(id: userId)
        async let household = try? repositories.users.household(id: householdId)
        async let groups = try? repositories.groups.groups(ofHousehold: householdId)
        let (loadedUser, loadedHousehold, loadedGroups) = await (user, household, groups)
        if neighborhood.isEmpty, let value = loadedUser?.neighborhood { neighborhood = value }
        if let geohash = loadedHousehold?.geohash, let origin = Geohash.center(of: geohash) {
            center = origin
            homeCenter = origin
        }
        householdGroupCount = loadedGroups?.count
    }

    var draft: GroupRules.Draft {
        GroupRules.Draft(name: name, neighborhood: neighborhood,
                         centerGeohash: Geohash.encode(center, precision: 7),
                         radiusMeters: radiusMeters, isPublic: isPublic)
    }

    /// Point de cueillette tel qu'il sera créé (id et groupe définitifs posés à la création).
    func pickupPointDraft(groupId: String) -> PickupPoint {
        PickupPoint.deliveryZone(
            forGroup: groupId, hostUserId: userId, name: pickupName, address: pickupAddress,
            // Position approximative (6 caractères ≈ 1 km), jamais l'adresse exacte ; nil si non vérifiée.
            geohash: addressCheck.validatedAddress(for: pickupAddress)?.geohash(precision: 6)
        )
    }

    /// Ce qui manque au formulaire, en français ; nil s'il est prêt.
    var validationMessage: String? {
        do {
            try GroupRules.validate(draft)
            return pickupValidationMessage
        } catch {
            return AppError(error).message
        }
    }

    /// Ce qui manque à la zone de livraison ; nil si elle est prête.
    var pickupValidationMessage: String? {
        if addressCheck.status(for: pickupAddress) == .notFound {
            return String(localized: "Adresse introuvable. Vérifie le numéro et la rue.")
        }
        do {
            _ = try PickupSlotBook.validatedPoint(pickupPointDraft(groupId: "draft"))
            return nil
        } catch {
            return AppError(error).message
        }
    }

    /// Nom du point sans les espaces autour, pour le compteur de caractères.
    var trimmedPickupNameCount: Int { pickupName.trimmingCharacters(in: .whitespacesAndNewlines).count }

    /// Faux si le ménage fait déjà partie de 3 groupes (RQ-030).
    var hasRoomForAnotherGroup: Bool {
        householdGroupCount.map { $0 < GroupRules.maxGroupsPerHousehold } ?? true
    }

    var canCreate: Bool {
        validationMessage == nil && hasRoomForAnotherGroup && !isSaving && !addressCheck.blocksSaving(pickupAddress)
    }

    /// « 1,5 km », « 2 km ».
    var radiusText: String { Self.radiusText(meters: radiusMeters) }

    nonisolated static func radiusText(meters: Int) -> String {
        let tenths = Int((Double(meters) / 100).rounded())
        return tenths % 10 == 0
            ? String(localized: "\(tenths / 10) km")
            : String(localized: "\(tenths / 10),\(tenths % 10) km")
    }

    /// Nom sans les espaces autour, pour le compteur de caractères.
    var trimmedNameCount: Int { name.trimmingCharacters(in: .whitespacesAndNewlines).count }

    /// Vrai si le centre est encore sur le ménage (le bouton « Chez moi » n'a alors rien à faire).
    var isCenteredAtHome: Bool {
        guard let homeCenter else { return true }
        return Geohash.distanceMeters(from: homeCenter, to: center) < 20
    }

    func formChanged() { submitError = nil }

    func create() async {
        guard canCreate else { return }
        isSaving = true
        defer { isSaving = false }
        // Adresse tapée sans choisir de suggestion : on la vérifie maintenant (texte normalisé réécrit).
        guard let address = await addressCheck.ensureValid(pickupAddress) else {
            submitError = String(localized: "Adresse introuvable. Vérifie le numéro et la rue.")
            return
        }
        pickupAddress = address
        do {
            let group: NeighborhoodGroup
            if let pendingGroup {
                group = pendingGroup
            } else {
                group = try await repositories.groups.createGroup(draft, byUserId: userId, householdId: householdId)
                pendingGroup = group
            }
            // Après le groupe : le point porte son id. firestore.rules accepte un point dont on est l'hôte.
            let point = try PickupSlotBook.validatedPoint(pickupPointDraft(groupId: group.id))
            try await repositories.pickupPoints.savePickupPoint(point)
            pendingGroup = nil
            createdGroup = group
            submitError = nil
        } catch {
            submitError = pendingGroup == nil
                ? AppError(error).message
                : String(localized: "Groupe créé, mais son point de cueillette n'a pas été enregistré. Touche « Créer le groupe » pour réessayer.")
        }
    }
}
