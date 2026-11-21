// GroupImageEditorViewModel.swift
// T-122 : le coordinateur change la photo ou la bannière de son groupe.
// Choix (PhotosPicker) → recadrage et compression hors du fil principal → aperçu → envoi
// (`repositories.images` puis `groups.updateImage`) → succès (haptique) ou erreur avec « Réessayer ».
//
// Usage :
//   @State private var editor = GroupImageEditorViewModel(repositories: context.repositories, groupId: id, userId: context.userId)
//   await editor.pick(data, kind: .banner)          // ouvre l'aperçu
//   if let group = await editor.confirm() { detail.replaceGroup(group) }

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class GroupImageEditorViewModel {
    enum Status: Equatable {
        case idle
        /// Recadrage et compression de la photo choisie.
        case preparing
        /// Aperçu prêt, en attente de « Utiliser cette photo ».
        case ready
        case uploading
        case succeeded
        case failed(AppError)
    }

    /// Image recadrée en attente d'envoi.
    struct Pending: Equatable {
        var kind: GroupImageKind
        var image: PreparedImage
    }

    private(set) var status: Status = .idle
    private(set) var pending: Pending?
    /// Type d'image en cours de traitement (aussi pendant la préparation, avant `pending`).
    private(set) var activeKind: GroupImageKind?
    /// Avancement affiché : préparation 0,25, envoi 0,6, enregistré 1.
    private(set) var progress: Double = 0
    /// Incrémenté à chaque image enregistrée ou retirée (haptique et rebond).
    private(set) var successCount = 0

    private let repositories: AppRepositories
    private let groupId: String
    private let userId: String

    init(repositories: AppRepositories, groupId: String, userId: String) {
        self.repositories = repositories
        self.groupId = groupId
        self.userId = userId
    }

    /// La feuille d'aperçu est ouverte.
    var isPresentingPreview: Bool { activeKind != nil }

    var isBusy: Bool { status == .preparing || status == .uploading }

    var error: AppError? {
        if case .failed(let error) = status { error } else { nil }
    }

    /// Image de l'aperçu.
    var previewImage: UIImage? { pending.flatMap { UIImage(data: $0.image.jpeg) } }

    // MARK: Choisir

    /// Recadre et compresse la photo choisie, puis montre l'aperçu.
    func pick(_ data: Data, kind: GroupImageKind) async {
        guard !isBusy else { return }
        activeKind = kind
        pending = nil
        status = .preparing
        progress = 0.25
        do {
            let spec = kind.mediaPath(groupId: groupId).spec
            let image = try await Task.detached(priority: .userInitiated) {
                try ImageProcessing.prepare(data, spec: spec)
            }.value
            pending = Pending(kind: kind, image: image)
            status = .ready
        } catch {
            status = .failed(AppError(error))
            progress = 0
        }
    }

    // MARK: Envoyer

    /// Envoie l'image de l'aperçu et la pose sur le groupe ; renvoie le groupe à jour (nil en cas d'échec).
    @discardableResult
    func confirm() async -> NeighborhoodGroup? {
        guard let pending, status != .uploading else { return nil }
        status = .uploading
        progress = 0.6
        do {
            let path = pending.kind.mediaPath(groupId: groupId)
            let url = try await repositories.images.save(pending.image, at: path)
            try await repositories.groups.updateImage(pending.kind, url: url, ofGroup: groupId, byUserId: userId)
            // L'image vient d'ici : elle s'affiche tout de suite, sans relire Firestore.
            if let image = UIImage(data: pending.image.jpeg) {
                MediaImageLoader.shared.prime(image, for: url)
            }
            let group = try await repositories.groups.group(id: groupId)
            progress = 1
            status = .succeeded
            successCount += 1
            return group
        } catch {
            status = .failed(AppError(error))
            progress = 0
            return nil
        }
    }

    /// Après une erreur : renvoie l'aperçu s'il existe, sinon ferme.
    func retry() async -> NeighborhoodGroup? {
        guard pending != nil else {
            dismiss()
            return nil
        }
        return await confirm()
    }

    /// Ferme l'aperçu (annuler, ou après le succès).
    func dismiss() {
        guard status != .uploading else { return }
        pending = nil
        activeKind = nil
        status = .idle
        progress = 0
    }

    /// Ferme le message d'erreur d'un retrait (hors de la feuille d'aperçu).
    func clearError() {
        guard activeKind == nil, case .failed = status else { return }
        status = .idle
    }

    // MARK: Retirer

    /// Retire la photo ou la bannière : le groupe repasse aux initiales ou au dégradé.
    @discardableResult
    func remove(_ kind: GroupImageKind) async -> NeighborhoodGroup? {
        guard !isBusy else { return nil }
        status = .uploading
        do {
            try await repositories.groups.updateImage(kind, url: nil, ofGroup: groupId, byUserId: userId)
            // Le document `media` n'est plus référencé : on le supprime, sans bloquer si ça échoue.
            try? await repositories.images.delete(at: kind.mediaPath(groupId: groupId))
            let group = try await repositories.groups.group(id: groupId)
            status = .idle
            successCount += 1
            return group
        } catch {
            status = .failed(AppError(error))
            return nil
        }
    }
}
