// CreateGroupViewModel.swift
// B-059 : créer un groupe depuis l'app. Nom, quartier, centre sur la carte, rayon de 1 à 2 km, public ou privé.
// Le brouillon passe par `GroupRules.validate` / `makeGroup` (dans le dépôt) ; au plus 3 groupes par ménage (RQ-030).

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

    private(set) var isSaving = false
    /// Erreur renvoyée par le dépôt (réseau, règles, limite de groupes) ; remise à nil dès qu'on modifie le formulaire.
    private(set) var submitError: String?
    /// Groupe créé : la feuille se ferme et ouvre sa fiche.
    private(set) var createdGroup: NeighborhoodGroup?
    /// Nombre de groupes du ménage ; nil tant qu'il n'est pas chargé.
    private(set) var householdGroupCount: Int?

    /// Centre de Montréal, si la position du ménage est inconnue.
    nonisolated static let fallbackCenter = Geohash.Coordinate(latitude: 45.5017, longitude: -73.5673)
    nonisolated static let radiusStep = 100

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String

    init(repositories: AppRepositories, userId: String, householdId: String) {
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
        if let geohash = loadedHousehold?.geohash, let origin = Geohash.center(of: geohash) { center = origin }
        householdGroupCount = loadedGroups?.count
    }

    var draft: GroupRules.Draft {
        GroupRules.Draft(name: name, neighborhood: neighborhood,
                         centerGeohash: Geohash.encode(center, precision: 7),
                         radiusMeters: radiusMeters, isPublic: isPublic)
    }

    /// Ce qui manque au formulaire, en français ; nil s'il est prêt.
    var validationMessage: String? {
        do {
            try GroupRules.validate(draft)
            return nil
        } catch {
            return AppError(error).message
        }
    }

    /// Faux si le ménage fait déjà partie de 3 groupes (RQ-030).
    var hasRoomForAnotherGroup: Bool {
        householdGroupCount.map { $0 < GroupRules.maxGroupsPerHousehold } ?? true
    }

    var canCreate: Bool { validationMessage == nil && hasRoomForAnotherGroup && !isSaving }

    /// « 1,5 km », « 2 km ».
    var radiusText: String { Self.radiusText(meters: radiusMeters) }

    nonisolated static func radiusText(meters: Int) -> String {
        let tenths = Int((Double(meters) / 100).rounded())
        return tenths % 10 == 0
            ? String(localized: "\(tenths / 10) km")
            : String(localized: "\(tenths / 10),\(tenths % 10) km")
    }

    func formChanged() { submitError = nil }

    func create() async {
        guard canCreate else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            createdGroup = try await repositories.groups.createGroup(draft, byUserId: userId, householdId: householdId)
            submitError = nil
        } catch {
            submitError = AppError(error).message
        }
    }
}
