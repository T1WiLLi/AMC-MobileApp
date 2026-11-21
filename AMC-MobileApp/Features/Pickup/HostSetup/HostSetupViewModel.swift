// HostSetupViewModel.swift
// RQ-062 (T-077) : devenir hôte d'un point de cueillette — nom, adresse, photo, capacité, accessibilité.
// Reprend le point existant de l'utilisateur s'il en a déjà un (modification).

import Foundation
import Observation

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

    private let repositories: AppRepositories
    private let photoStore: any HostPhotoStore
    private let userId: String
    private let makeId: @Sendable () -> String

    init(
        repositories: AppRepositories,
        userId: String,
        photoStore: any HostPhotoStore = LocalHostPhotoStore(),
        makeId: @escaping @Sendable () -> String = { "pickup-\(UUID().uuidString.lowercased())" }
    ) {
        self.repositories = repositories
        self.userId = userId
        self.photoStore = photoStore
        self.makeId = makeId
    }

    var isEditing: Bool { existingPoint != nil }

    /// Erreur de saisie à montrer sous le formulaire, nil si tout est bon.
    var validationError: AppError? {
        do {
            _ = try PickupSlotBook.validatedPoint(draft(id: existingPoint?.id ?? "draft", photoURL: photoURL))
            return nil
        } catch let error as AppError {
            return error
        } catch {
            return AppError(error)
        }
    }

    var canSave: Bool { validationError == nil && !isSaving }

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
        do {
            var url = photoURL
            if let photoData { url = try await photoStore.upload(photoData, pointId: id) }
            let point = try PickupSlotBook.validatedPoint(draft(id: id, photoURL: url))
            try await repositories.pickupPoints.savePickupPoint(point)
            fill(with: point)
            savedPoint = point
            return point
        } catch {
            saveError = AppError(error)
            return nil
        }
    }

    private func draft(id: String, photoURL: URL?) -> PickupPoint {
        PickupPoint(
            id: id, hostUserId: userId, name: name, address: address, photoURL: photoURL, capacity: capacity,
            accessibility: PickupPoint.Accessibility.allCases.filter(accessibility.contains),
            slots: existingPoint?.slots ?? []
        )
    }

    private func fill(with point: PickupPoint) {
        existingPoint = point
        name = point.name
        address = point.address
        capacity = point.capacity
        accessibility = Set(point.accessibility)
        photoURL = point.photoURL
        photoData = nil
    }
}

/// Envoi de la photo d'un point de cueillette. L'app range la photo sur l'appareil en attendant
/// le dépôt Firebase Storage.
nonisolated protocol HostPhotoStore: Sendable {
    func upload(_ data: Data, pointId: String) async throws -> URL
}

/// Range la photo dans les caches de l'app (fake, previews, démo).
nonisolated struct LocalHostPhotoStore: HostPhotoStore {
    func upload(_ data: Data, pointId: String) async throws -> URL {
        let folder = URL.cachesDirectory.appending(path: "pickup-photos", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "\(pointId).jpg")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw AppError.unknown("Photo non enregistrée : \(error.localizedDescription)")
        }
    }
}
