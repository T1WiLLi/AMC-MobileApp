// PreferencesViewModel.swift
// RQ-017 (préférences alimentaires et allergies), RQ-018 (langue), RQ-019 (mode aîné).
// Chaque changement s'enregistre tout de suite (comme Réglages) ; en cas d'échec, on revient en arrière.

import Foundation
import Observation

@Observable @MainActor
final class PreferencesViewModel {
    /// Groupes d'étiquettes affichés à l'écran, dans l'ordre.
    enum TagGroup: CaseIterable, Identifiable {
        case diet, allergies, sourcing

        var id: Self { self }

        var title: String {
            switch self {
            case .diet: String(localized: "Régime")
            case .allergies: String(localized: "Allergies et intolérances")
            case .sourcing: String(localized: "Provenance")
            }
        }

        var systemImage: String {
            switch self {
            case .diet: "fork.knife"
            case .allergies: "allergens"
            case .sourcing: "leaf.fill"
            }
        }

        var tags: [DietaryTag] {
            switch self {
            case .diet: [.halal, .kosher, .vegetarian, .vegan]
            case .allergies: [.glutenFree]
            case .sourcing: [.organic, .local]
            }
        }
    }

    private let repositories: AppRepositories
    private let userId: String

    private(set) var state: LoadState<AppUser> = .idle
    private(set) var saveError: AppError?
    private(set) var isSaving = false
    /// Incrémenté à chaque enregistrement réussi.
    private(set) var saveCount = 0

    init(repositories: AppRepositories, userId: String) {
        self.repositories = repositories
        self.userId = userId
    }

    convenience init(context: AppContext) {
        self.init(repositories: context.repositories, userId: context.userId)
    }

    var user: AppUser? { state.value }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await repositories.users.user(id: userId))
        } catch {
            state = .failed(AppError(error))
        }
    }

    // MARK: Préférences alimentaires

    func isSelected(_ tag: DietaryTag) -> Bool { user?.dietaryPreferences.contains(tag) == true }

    func toggle(_ tag: DietaryTag) async {
        await update { user in
            var tags = Set(user.dietaryPreferences)
            if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
            // Ordre stable (celui de DietaryTag) pour ne pas réécrire le document pour rien.
            user.dietaryPreferences = DietaryTag.allCases.filter(tags.contains)
        }
    }

    /// « Halal, Sans gluten » ou « Aucune ».
    var dietarySummary: String {
        let tags = user?.dietaryPreferences ?? []
        guard !tags.isEmpty else { return String(localized: "Aucune") }
        return tags.map(Self.title(of:)).formatted(.list(type: .and).locale(AppLanguage.formattingLocale))
    }

    nonisolated static func title(of tag: DietaryTag) -> String { OfferFeedViewModel.title(of: tag) }

    nonisolated static func systemImage(of tag: DietaryTag) -> String {
        switch tag {
        case .organic: "leaf"
        case .halal: "moon.stars"
        case .kosher: "star.circle"
        case .vegetarian: "carrot"
        case .vegan: "leaf.circle"
        case .glutenFree: "laurel.leading"
        case .local: "mappin.and.ellipse"
        }
    }

    // MARK: Langue et mode aîné

    func setLanguage(_ language: AppUser.Language) async {
        await update { $0.language = language }
    }

    func setSeniorMode(_ isOn: Bool) async {
        await update { $0.seniorMode = isOn }
    }

    /// T-171 : libellé d'un choix de langue de l'interface. « Langue de l'appareil » montre la langue résolue.
    nonisolated static func title(of language: AppLanguage) -> String {
        switch language {
        case .system:
            let resolved = AppUser.Language(rawValue: AppLanguage.system.resolvedCode) ?? .french
            return String(localized: "Langue de l'appareil (\(title(of: resolved)))")
        case .french: return title(of: AppUser.Language.french)
        case .english: return title(of: AppUser.Language.english)
        }
    }

    nonisolated static func title(of language: AppUser.Language) -> String {
        switch language {
        case .french: "Français"
        case .english: "English"
        }
    }

    // MARK: Enregistrement optimiste

    private func update(_ change: (inout AppUser) -> Void) async {
        guard let previous = state.value else { return }
        var updated = previous
        change(&updated)
        guard updated != previous else { return }
        state = .loaded(updated)
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await repositories.users.saveUser(updated)
            saveCount += 1
        } catch {
            // Un autre changement a pu arriver entretemps : on ne revient en arrière que si rien n'a bougé.
            if state.value == updated { state = .loaded(previous) }
            saveError = AppError(error)
        }
    }
}
