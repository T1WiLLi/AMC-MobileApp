// NearbyGroupsViewModel.swift
// Groupes à proximité (T-063, RQ-023) et groupe suggéré (RQ-031) : groupes publics autour du ménage,
// du plus proche au plus loin, avec rejoindre.
//
// Usage dans une vue :
//   @State private var model = NearbyGroupsViewModel(repositories: repos, householdId: id)
//   .task { await model.load() }
//   Picker lié à `$model.radius` (1 km / 2 km) : `state` se recalcule seul.
//   switch model.state { case .loaded(let items): GroupCard + `item.distanceText` (« à 650 m ») }
//   if let suggestion = model.suggestedGroup { carte « Groupe suggéré » + bouton `join(groupId:)` }
//
// La distance est mesurée entre le geohash du ménage (ou une position donnée) et le centre du groupe.

import Foundation
import Observation

@Observable
@MainActor
final class NearbyGroupsViewModel {
    /// D'où mesurer les distances.
    nonisolated enum Origin: Sendable, Hashable {
        /// Geohash approximatif du ménage (`Household.geohash`), lu au chargement.
        case household
        case geohash(String)
        case coordinate(Geohash.Coordinate)
    }

    /// Rayon de recherche (RQ-023).
    nonisolated enum Radius: Int, CaseIterable, Identifiable, Sendable {
        case oneKilometer = 1_000
        case twoKilometers = 2_000

        var id: Int { rawValue }
        var meters: Double { Double(rawValue) }
        var title: String {
            switch self {
            case .oneKilometer: String(localized: "1 km")
            case .twoKilometers: String(localized: "2 km")
            }
        }
    }

    /// Une ligne de la liste.
    nonisolated struct Item: Identifiable, Sendable, Hashable {
        var group: NeighborhoodGroup
        /// Distance du ménage au centre du groupe, en mètres.
        var distanceMeters: Double
        /// Le ménage fait partie du groupe.
        var isMember: Bool

        var id: String { group.id }
        /// Ménages membres.
        var memberCount: Int { group.householdCount }
        /// « à 650 m », « à 1,4 km ».
        var distanceText: String { NearbyGroupsViewModel.distanceText(meters: distanceMeters) }
        /// « 12 ménages ».
        var memberCountText: String { memberCount <= 1 ? String(localized: "\(memberCount) ménage") : String(localized: "\(memberCount) ménages") }
    }

    // MARK: Filtre (le résultat se recalcule à chaque changement)

    var radius: Radius = .twoKilometers

    // MARK: État

    /// Tous les groupes publics localisables, du plus proche au plus loin (avant le filtre de rayon).
    private(set) var allGroups: LoadState<[Item]> = .idle
    /// Groupes dont l'adhésion est en cours de changement.
    private(set) var pendingGroupIds: Set<String> = []
    /// Dernière erreur d'une action (rejoindre), à montrer en alerte ; remise à nil par la vue.
    var actionError: AppError?

    let householdId: String
    let origin: Origin
    private let repositories: AppRepositories

    init(repositories: AppRepositories, householdId: String, origin: Origin = .household,
         radius: Radius = .twoKilometers) {
        self.repositories = repositories
        self.householdId = householdId
        self.origin = origin
        self.radius = radius
    }

    /// Groupes dans le rayon, du plus proche au plus loin ; `.empty` s'il n'y en a aucun.
    var state: LoadState<[Item]> {
        switch allGroups {
        case .idle: .idle
        case .loading: .loading
        case .empty: .empty
        case .failed(let error): .failed(error)
        case .loaded(let items): .from(items.filter { $0.distanceMeters <= radius.meters })
        }
    }

    var items: [Item] { state.value ?? [] }

    /// Groupe le plus proche dans le rayon dont le ménage n'est pas membre (RQ-031) ; nil sinon.
    var suggestedGroup: Item? { items.first { !$0.isMember } }

    // MARK: Actions

    /// Charge (ou recharge) les groupes. Garde la liste affichée pendant un rechargement.
    func load() async {
        if allGroups.value == nil { allGroups = .loading }
        let repositories = repositories, householdId = householdId, origin = origin
        let result = await LoadState<[Item]>.run {
            let originCoordinate = try await Self.coordinate(of: origin, householdId: householdId,
                                                             repositories: repositories)
            let memberOf = Set(try await repositories.groups.groups(ofHousehold: householdId).map(\.id))
            let groups = try await repositories.groups.groups(inNeighborhood: nil)
            return Self.items(groups, from: originCoordinate, memberOf: memberOf)
        }
        if let items = result.value { allGroups = .from(items) } else { allGroups = result }
    }

    /// Rejoint le groupe puis met la ligne à jour (membre, nombre de ménages). En cas d'erreur : `actionError`.
    func join(groupId: String) async {
        guard !pendingGroupIds.contains(groupId) else { return }
        pendingGroupIds.insert(groupId)
        defer { pendingGroupIds.remove(groupId) }
        do {
            try await repositories.groups.join(groupId: groupId, householdId: householdId)
            let group = try await repositories.groups.group(id: groupId)
            if var items = allGroups.value, let index = items.firstIndex(where: { $0.id == groupId }) {
                items[index].group = group
                items[index].isMember = true
                allGroups = .loaded(items)
            }
        } catch {
            actionError = AppError(error)
        }
    }

    // MARK: Calculs (purs, testables)

    /// Lignes triées par distance puis par nom ; les groupes au geohash invalide sont ignorés.
    nonisolated static func items(
        _ groups: [NeighborhoodGroup], from origin: Geohash.Coordinate, memberOf: Set<String>
    ) -> [Item] {
        groups
            .compactMap { group -> Item? in
                guard let distance = Geohash.distanceMeters(from: origin, to: group.centerGeohash) else { return nil }
                return Item(group: group, distanceMeters: distance, isMember: memberOf.contains(group.id))
            }
            .sorted { ($0.distanceMeters, $0.group.name) < ($1.distanceMeters, $1.group.name) }
    }

    /// « à 650 m » sous 1 km (arrondi à 10 m), « à 1,4 km » jusqu'à 10 km, puis « à 12 km ».
    nonisolated static func distanceText(meters: Double) -> String {
        let meters = max(0, meters)
        let roundedMeters = Int((meters / 10).rounded()) * 10
        if roundedMeters < 1_000 { return "à \(max(10, roundedMeters)) m" }
        let tenths = Int((meters / 100).rounded())
        if tenths < 100 { return String(localized: "à \(tenths / 10),\(tenths % 10) km") }
        return String(localized: "à \(Int((meters / 1_000).rounded())) km")
    }

    nonisolated private static func coordinate(
        of origin: Origin, householdId: String, repositories: AppRepositories
    ) async throws -> Geohash.Coordinate {
        let geohash: String
        switch origin {
        case .coordinate(let coordinate): return coordinate
        case .geohash(let value): geohash = value
        case .household: geohash = try await repositories.users.household(id: householdId).geohash
        }
        guard let center = Geohash.center(of: geohash) else {
            throw AppError.invalidInput(String(localized: "La position du ménage est inconnue."))
        }
        return center
    }
}
