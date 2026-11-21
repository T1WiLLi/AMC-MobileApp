// AccountViewModel.swift
// « Mon compte » (T-103, RQ-021) : modifier le nom affiché et la photo (`users.saveUser`),
// supprimer le compte (`AuthService.deleteAccount()`).
//
// Usage dans une vue :
//   @State private var model = AccountViewModel(repositories: context.repositories, userId: context.userId, auth: auth)
//   .task { await model.load() }
//   Button("Enregistrer") { Task { await model.save() } }.disabled(!model.canSave)

import Foundation
import Observation

/// Enregistre la photo de profil choisie et renvoie son URL. Une version Firebase Storage
/// (`users/{uid}/…`, storage.rules) pourra remplacer la version locale.
nonisolated protocol ProfilePhotoStoring: Sendable {
    func store(_ data: Data, userId: String) async throws -> URL
}

/// Écrit la photo dans le dossier Caches de l'app (démo et dépôts fake).
nonisolated struct LocalProfilePhotoStore: ProfilePhotoStoring {
    func store(_ data: Data, userId: String) async throws -> URL {
        let folder = URL.cachesDirectory.appending(path: "profile-photos/\(userId)", directoryHint: .isDirectory)
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
final class AccountViewModel {
    /// Étapes de la suppression, dans l'ordre de l'écran.
    enum DeletionState: Equatable {
        case idle
        /// Première confirmation passée : la seconde est à l'écran.
        case confirming
        case deleting
        /// Compte supprimé : la session repasse à l'écran de connexion.
        case deleted
        /// Firebase exige une connexion récente : se reconnecter, puis réessayer.
        case needsReauthentication
        case failed(String)
    }

    // MARK: Limites (alignées sur firestore.rules, isValidUser)

    static let displayNameMaxLength = 80

    // MARK: État

    private(set) var loadState: LoadState<AppUser> = .idle
    /// Nom affiché en cours de saisie.
    var displayName = ""
    private(set) var photoURL: URL?
    private(set) var isSaving = false
    private(set) var isAddingPhoto = false
    /// Incrémenté à chaque enregistrement réussi (haptique et sceau).
    private(set) var saveCount = 0
    private(set) var saveError: AppError?
    private(set) var deletionState: DeletionState = .idle

    private let repositories: AppRepositories
    private let userId: String
    private let auth: any AuthService
    private let photoStore: any ProfilePhotoStoring

    init(
        repositories: AppRepositories,
        userId: String,
        auth: any AuthService,
        photoStore: any ProfilePhotoStoring = LocalProfilePhotoStore()
    ) {
        self.repositories = repositories
        self.userId = userId
        self.auth = auth
        self.photoStore = photoStore
    }

    // MARK: Lecture

    var user: AppUser? { loadState.value }

    var trimmedDisplayName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Message sous le champ du nom, nil si valide.
    var displayNameError: String? {
        if trimmedDisplayName.isEmpty { return String(localized: "Ton nom ne peut pas être vide.") }
        if trimmedDisplayName.count > Self.displayNameMaxLength {
            return String(localized: "\(Self.displayNameMaxLength) caractères au plus.")
        }
        return nil
    }

    var hasChanges: Bool {
        guard let user else { return false }
        return user.displayName != trimmedDisplayName || user.photoURL != photoURL
    }

    var canSave: Bool { hasChanges && displayNameError == nil && !isSaving && !isDeleting }

    var isDeleting: Bool { deletionState == .deleting }

    /// Initiales pour l'avatar sans photo.
    var initials: String {
        let parts = trimmedDisplayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    func load() async {
        loadState = .loading
        do {
            let user = try await repositories.users.user(id: userId)
            displayName = user.displayName
            photoURL = user.photoURL
            loadState = .loaded(user)
        } catch {
            loadState = .failed(AppError(error))
        }
    }

    // MARK: Modifier

    func save() async {
        guard canSave, var user else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        user.displayName = trimmedDisplayName
        user.photoURL = photoURL
        do {
            try await repositories.users.saveUser(user)
            displayName = user.displayName
            loadState = .loaded(user)
            saveCount += 1
        } catch {
            saveError = AppError(error)
        }
    }

    /// Enregistre l'image choisie (PhotosPicker) ; elle part avec le prochain « Enregistrer ».
    func setPhoto(data: Data) async {
        isAddingPhoto = true
        saveError = nil
        defer { isAddingPhoto = false }
        do {
            photoURL = try await photoStore.store(data, userId: userId)
        } catch {
            saveError = AppError(error)
        }
    }

    func removePhoto() {
        photoURL = nil
    }

    /// Revenir aux valeurs enregistrées.
    func discardChanges() {
        guard let user else { return }
        displayName = user.displayName
        photoURL = user.photoURL
        saveError = nil
    }

    // MARK: Supprimer (confirmation en deux temps)

    /// Premier temps : « Supprimer mon compte » touché, la seconde confirmation s'affiche.
    func requestDeletion() {
        guard !isDeleting else { return }
        deletionState = .confirming
    }

    func cancelDeletion() {
        guard !isDeleting else { return }
        deletionState = .idle
    }

    /// Second temps : suppression définitive.
    func confirmDeletion() async {
        guard deletionState == .confirming else { return }
        deletionState = .deleting
        do {
            try await auth.deleteAccount()
            deletionState = .deleted
        } catch AuthError.requiresRecentLogin {
            deletionState = .needsReauthentication
        } catch let error as AuthError {
            deletionState = .failed(error.errorDescription ?? AppError.unknown("").message)
        } catch {
            deletionState = .failed(AppError(error).message)
        }
    }

    /// Ferme le message d'erreur ou de reconnexion.
    func dismissDeletionMessage() {
        if case .deleted = deletionState { return }
        deletionState = .idle
    }
}
