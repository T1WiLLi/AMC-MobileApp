// HostSetupViewModel.swift
// RQ-062 (T-077) : devenir hôte d'un point de cueillette — nom, adresse, photo, capacité, accessibilité.
// Reprend le point existant de l'utilisateur s'il en a déjà un (modification).

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class HostSetupViewModel {
    /// Point existant de l'hôte, nil s'il devient hôte pour la première fois.
    private(set) var existingPoint: PickupPoint?
    private(set) var loadState: LoadState<Bool> = .idle

    var name = ""
    var address = ""
    var capacity = 20
    var accessibility: Set<PickupPoint.Accessibility> = []
    /// Photo choisie dans la photothèque, pas encore envoyée.
    var photoData: Data?
    /// Photo déjà enregistrée.
    private(set) var photoURL: URL?

    private(set) var isSaving = false
    private(set) var saveError: AppError?
    /// Point enregistré au dernier `save()` réussi (déclenche l'haptique et la confirmation).
    private(set) var savedPoint: PickupPoint?

    static let capacityRange = 1...PickupSlotBook.maxPointCapacity

    /// T-185 : l'adresse doit être trouvée par Apple Maps avant d'enregistrer (sauf celle déjà enregistrée).
    let addressCheck: AddressFieldModel

    private let repositories: AppRepositories
    private let photoStore: any HostPhotoStore
    private let userId: String
    private let makeId: @Sendable () -> String

    init(
        repositories: AppRepositories,
        userId: String,
        photoStore: (any HostPhotoStore)? = nil,
        addressValidator: any AddressValidating = MapKitAddressValidator.shared,
        makeId: @escaping @Sendable () -> String = { "pickup-\(UUID().uuidString.lowercased())" }
    ) {
        self.addressCheck = AddressFieldModel(validator: addressValidator)
        self.repositories = repositories
        self.userId = userId
        self.photoStore = photoStore ?? ImageStoreHostPhotoStore(images: repositories.images)
        self.makeId = makeId
    }

    var isEditing: Bool { existingPoint != nil }

    /// Erreur de saisie à montrer sous le formulaire, nil si tout est bon.
    var validationError: AppError? {
        if addressCheck.status(for: address) == .notFound {
            return .invalidInput(String(localized: "Adresse introuvable. Vérifie le numéro et la rue."))
        }
        do {
            _ = try PickupSlotBook.validatedPoint(draft(id: existingPoint?.id ?? "draft", photoURL: photoURL))
            return nil
        } catch let error as AppError {
            return error
        } catch {
            return AppError(error)
        }
    }

    var canSave: Bool { validationError == nil && !isSaving && !addressCheck.blocksSaving(address) }

    func load() async {
        if loadState.value == nil { loadState = .loading }
        let repositories = repositories, userId = userId
        do {
            let points = try await repositories.pickupPoints.pickupPoints()
            if let mine = points.first(where: { $0.hostUserId == userId }) { fill(with: mine) }
            loadState = .loaded(true)
        } catch {
            loadState = .failed(AppError(error))
        }
    }

    func toggle(_ option: PickupPoint.Accessibility) {
        if accessibility.contains(option) { accessibility.remove(option) } else { accessibility.insert(option) }
    }

    func removePhoto() {
        photoData = nil
        photoURL = nil
    }

    @discardableResult
    func save() async -> PickupPoint? {
        guard !isSaving else { return nil }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let id = existingPoint?.id ?? makeId()
        // T-185 : adresse modifiée et pas encore vérifiée (ex. enregistrée sans choisir de suggestion) : on la vérifie.
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let checked = await addressCheck.ensureValid(address) else {
                saveError = .invalidInput(String(localized: "Adresse introuvable. Vérifie le numéro et la rue."))
                return nil
            }
            address = checked
        }
        let isNew = existingPoint == nil
        let point: PickupPoint
        do {
            // Le point d'abord : firestore.rules n'accepte la photo que de l'hôte d'un point existant.
            point = try PickupSlotBook.validatedPoint(draft(id: id, photoURL: photoURL))
            if isNew || photoData == nil { try await repositories.pickupPoints.savePickupPoint(point) }
        } catch {
            saveError = AppError(error)
            return nil
        }
        guard let photoData else { return finishSave(point) }
        do {
            var withPhoto = point
            withPhoto.photoURL = try await photoStore.upload(photoData, pointId: id)
            try await repositories.pickupPoints.savePickupPoint(withPhoto)
            return finishSave(withPhoto)
        } catch {
            // Point créé sans sa photo : l'écran passe en modification et garde la photo choisie pour réessayer.
            let pending = photoData
            if isNew { fill(with: point) }
            self.photoData = pending
            saveError = AppError(error)
            return nil
        }
    }

    private func finishSave(_ point: PickupPoint) -> PickupPoint {
        fill(with: point)
        savedPoint = point
        return point
    }

    private func draft(id: String, photoURL: URL?) -> PickupPoint {
        PickupPoint(
            id: id, hostUserId: userId, name: name, address: address, photoURL: photoURL, capacity: capacity,
            accessibility: PickupPoint.Accessibility.allCases.filter(accessibility.contains),
            slots: existingPoint?.slots ?? [],
            // Position de l'adresse vérifiée ; sinon (adresse inchangée) celle déjà connue.
            geohash: addressCheck.validatedAddress(for: address)?.geohash() ?? existingPoint?.geohash,
            // Zone de livraison d'un groupe : le rattachement ne change pas (immuable dans firestore.rules).
            groupId: existingPoint?.groupId
        )
    }

    private func fill(with point: PickupPoint) {
        existingPoint = point
        name = point.name
        address = point.address
        addressCheck.accept(saved: point.address)
        capacity = point.capacity
        accessibility = Set(point.accessibility)
        photoURL = point.photoURL
        photoData = nil
    }
}

/// Envoi de la photo d'un point de cueillette.
nonisolated protocol HostPhotoStore: Sendable {
    func upload(_ data: Data, pointId: String) async throws -> URL
}

/// Par défaut : recadre en 4:3, compresse sous 300 Kio et range dans `pickupPoints/{id}/media/photo`
/// (Firestore en live, mémoire en fake). Renvoie l'URL `grenier-media` versionnée (à afficher avec `MediaImage`).
nonisolated struct ImageStoreHostPhotoStore: HostPhotoStore {
    let images: any ImageStore

    func upload(_ data: Data, pointId: String) async throws -> URL {
        let path = MediaPath.pickupPhoto(pointId: pointId)
        let image = try await Task.detached(priority: .userInitiated) {
            try ImageProcessing.prepare(data, spec: path.spec)
        }.value
        let url = try await images.save(image, at: path)
        if let decoded = UIImage(data: image.jpeg) {
            await MediaImageLoader.shared.prime(decoded, for: url)
        }
        return url
    }
}
