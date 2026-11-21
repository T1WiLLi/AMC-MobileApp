// VendorProfileViewModel.swift
// Profil vendeur (T-076, RQ-016) : raison sociale, type, description, photos de vitrine, zones desservies.
// Les règles Firestore ne laissent modifier que `description`, `photoURLs` et `servedZones` :
// le reste s'affiche en lecture seule.
//
// Usage dans une vue :
//   @State private var model = VendorProfileViewModel(repositories: .fake(), vendorId: FakeData.ID.fermeRive)
//   .task { await model.load() }
//   Button("Enregistrer") { Task { await model.save() } }.disabled(!model.canSave)

import Foundation
import Observation

/// Enregistre une photo choisie et renvoie son URL. Une version Firebase Storage
/// (`vendors/{vendorId}/…`, storage.rules) pourra remplacer la version locale.
nonisolated protocol VendorPhotoStoring: Sendable {
    func store(_ data: Data, vendorId: String) async throws -> URL
}

/// Écrit la photo dans le dossier Caches de l'app (démo et dépôts fake).
nonisolated struct LocalVendorPhotoStore: VendorPhotoStoring {
    func store(_ data: Data, vendorId: String) async throws -> URL {
        let folder = URL.cachesDirectory.appending(path: "vendor-photos/\(vendorId)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "\(UUID().uuidString).jpg")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw AppError.unknown(String(describing: error))
        }
    }
}

@Observable @MainActor
final class VendorProfileViewModel {
    /// Une zone proposée à l'ajout (tirée des groupes de quartier).
    nonisolated struct ZoneOption: Identifiable, Hashable, Sendable {
        /// Code enregistré dans `servedZones` (préfixe geohash, ex. « f25d »).
        var id: String
        /// Quartiers couverts (« Saint-Michel »).
        var label: String
    }

    // MARK: Limites (alignées sur firestore.rules)

    static let descriptionMinLength = 20
    static let descriptionMaxLength = 2_000
    static let maxPhotos = 10
    static let maxZones = 20
    /// Longueur des codes de zone proposés depuis les groupes.
    static let zonePrecision = 4

    // MARK: Champs modifiables

    var description: String = ""
    var servedZones: [String] = []
    private(set) var photoURLs: [URL] = []

    // MARK: État

    /// Profil chargé (valeurs enregistrées).
    private(set) var state: LoadState<Vendor> = .idle
    /// Dernière sauvegarde : `.loaded` si enregistrée, `.failed` si refusée.
    private(set) var saveState: LoadState<Vendor> = .idle
    /// Ajout de photo en cours.
    private(set) var isAddingPhoto = false
    /// Quartiers connus, par code de zone.
    private(set) var zoneLabels: [String: String] = [:]

    let vendorId: String
    private let repositories: AppRepositories
    private let photoStore: any VendorPhotoStoring

    init(
        repositories: AppRepositories,
        vendorId: String,
        photoStore: any VendorPhotoStoring = LocalVendorPhotoStore()
    ) {
        self.repositories = repositories
        self.vendorId = vendorId
        self.photoStore = photoStore
    }

    // MARK: Dérivés

    var vendor: Vendor? { state.value }
    var isSaving: Bool { saveState.isLoading }

    /// Vrai si un champ modifiable diffère de la version enregistrée.
    var hasChanges: Bool {
        guard let vendor else { return false }
        return vendor.description != trimmedDescription
            || vendor.servedZones != servedZones
            || vendor.photoURLs != photoURLs
    }

    /// Première règle non respectée, en français ; nil si le profil est enregistrable.
    var validationError: AppError? {
        do {
            _ = try validatedVendor()
            return nil
        } catch {
            return AppError(error)
        }
    }

    var canSave: Bool { hasChanges && validationError == nil && !isSaving }
    var canAddPhoto: Bool { photoURLs.count < Self.maxPhotos && !isAddingPhoto }

    /// Zones à proposer : celles des groupes, pas encore desservies.
    var zoneSuggestions: [ZoneOption] {
        zoneLabels
            .filter { !servedZones.contains($0.key) }
            .map { ZoneOption(id: $0.key, label: $0.value) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// Nom lisible d'une zone (« Saint-Michel »), ou son code si aucun groupe ne la couvre.
    func label(forZone zone: String) -> String {
        zoneLabels[zone] ?? zone
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Actions

    /// Charge le profil et les quartiers des groupes (pour nommer et proposer les zones).
    func load() async {
        if state.value == nil { state = .loading }
        do {
            async let loadedVendor = repositories.vendors.vendor(id: vendorId)
            async let loadedGroups = try? repositories.groups.groups(inNeighborhood: nil)
            let vendor = try await loadedVendor
            zoneLabels = Self.zoneLabels(from: await loadedGroups ?? [])
            apply(vendor)
            state = .loaded(vendor)
        } catch {
            state = .failed(AppError(error))
        }
    }

    /// Ajoute une zone (code saisi ou proposé). Renvoie l'erreur à afficher, nil si ajoutée.
    @discardableResult
    func addZone(_ rawZone: String) -> AppError? {
        let zone = rawZone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !zone.isEmpty else { return .invalidInput("Saisis un code de zone.") }
        guard zone.count <= 40 else { return .invalidInput("Ce code de zone est trop long (40 caractères au plus).") }
        guard !servedZones.contains(zone) else { return .invalidInput("Tu dessers déjà cette zone.") }
        guard servedZones.count < Self.maxZones else {
            return .invalidInput("Tu peux desservir \(Self.maxZones) zones au plus.")
        }
        servedZones.append(zone)
        return nil
    }

    func removeZone(_ zone: String) {
        servedZones.removeAll { $0 == zone }
    }

    /// Enregistre l'image choisie (PhotosPicker) et l'ajoute aux photos. Renvoie l'erreur, nil si ajoutée.
    @discardableResult
    func addPhoto(data: Data) async -> AppError? {
        guard photoURLs.count < Self.maxPhotos else {
            return .invalidInput("Tu peux ajouter \(Self.maxPhotos) photos au plus.")
        }
        guard !data.isEmpty else { return .invalidInput("Cette image est vide.") }
        isAddingPhoto = true
        defer { isAddingPhoto = false }
        do {
            let url = try await photoStore.store(data, vendorId: vendorId)
            photoURLs.append(url)
            return nil
        } catch {
            return AppError(error)
        }
    }

    func removePhoto(_ url: URL) {
        photoURLs.removeAll { $0 == url }
    }

    /// Met une photo en tête : c'est elle qui sert de couverture.
    func makeCover(_ url: URL) {
        guard let index = photoURLs.firstIndex(of: url), index > 0 else { return }
        photoURLs.insert(photoURLs.remove(at: index), at: 0)
    }

    /// Annule les modifications non enregistrées.
    func discardChanges() {
        if let vendor { apply(vendor) }
        saveState = .idle
    }

    /// Valide puis enregistre via `vendors.saveVendor`. Renvoie le profil enregistré, nil en cas d'échec.
    @discardableResult
    func save() async -> Vendor? {
        let updated: Vendor
        do {
            updated = try validatedVendor()
        } catch {
            saveState = .failed(AppError(error))
            return nil
        }
        saveState = .loading
        do {
            try await repositories.vendors.saveVendor(updated)
            state = .loaded(updated)
            apply(updated)
            saveState = .loaded(updated)
            return updated
        } catch {
            saveState = .failed(AppError(error))
            return nil
        }
    }

    // MARK: Privé

    private func apply(_ vendor: Vendor) {
        description = vendor.description
        servedZones = vendor.servedZones
        photoURLs = vendor.photoURLs
    }

    /// Profil enregistré + champs modifiables ; lève `.invalidInput` avec la règle à corriger.
    private func validatedVendor() throws(AppError) -> Vendor {
        guard var vendor else { throw .notFound }
        let text = trimmedDescription
        guard text.count >= Self.descriptionMinLength else {
            throw .invalidInput("Décris ton entreprise en \(Self.descriptionMinLength) caractères au moins.")
        }
        guard text.count <= Self.descriptionMaxLength else {
            throw .invalidInput("La description dépasse \(Self.descriptionMaxLength) caractères.")
        }
        guard !servedZones.isEmpty else {
            throw .invalidInput("Choisis au moins une zone desservie : c'est là que tes lots apparaîtront.")
        }
        guard servedZones.count <= Self.maxZones else {
            throw .invalidInput("Tu peux desservir \(Self.maxZones) zones au plus.")
        }
        guard photoURLs.count <= Self.maxPhotos else {
            throw .invalidInput("Tu peux ajouter \(Self.maxPhotos) photos au plus.")
        }
        vendor.description = text
        vendor.servedZones = servedZones
        vendor.photoURLs = photoURLs
        return vendor
    }

    /// Code de zone (préfixe geohash) → quartiers des groupes qui s'y trouvent (« Hochelaga, Saint-Michel »).
    static func zoneLabels(from groups: [NeighborhoodGroup]) -> [String: String] {
        var neighborhoods: [String: Set<String>] = [:]
        for group in groups where group.centerGeohash.count >= zonePrecision {
            let zone = String(group.centerGeohash.prefix(zonePrecision)).lowercased()
            neighborhoods[zone, default: []].insert(group.neighborhood)
        }
        return neighborhoods.mapValues { $0.sorted().formatted(.list(type: .and)) }
    }
}

extension Vendor.Kind {
    /// Nom affiché du type de vendeur.
    var title: String {
        switch self {
        case .farm: "Ferme"
        case .wholesaler: "Grossiste"
        case .cooperative: "Coopérative"
        case .bakery: "Boulangerie"
        case .other: "Autre commerce"
        }
    }

    var systemImage: String {
        switch self {
        case .farm: "leaf.fill"
        case .wholesaler: "shippingbox.fill"
        case .cooperative: "person.3.fill"
        case .bakery: "birthday.cake.fill"
        case .other: "storefront.fill"
        }
    }
}
