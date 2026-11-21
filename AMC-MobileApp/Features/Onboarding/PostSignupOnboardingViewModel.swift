// PostSignupOnboardingViewModel.swift
// T-156 : onboarding juste après l'inscription. Goûts → quartier → ménage → fini, puis le tableau de bord Familles.
// Tout est enregistré d'un coup à la fin : `households/{id}` d'abord (la règle du profil vérifie l'appartenance),
// puis `users/{uid}` avec `onboardingCompleted = true` pour ne plus le remontrer.

import Foundation
import Observation

@MainActor
@Observable
final class PostSignupOnboardingViewModel {
    /// Étapes, dans l'ordre.
    enum Step: Int, CaseIterable, Comparable, Sendable {
        case tastes
        case neighborhood
        case household
        case done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Étapes à remplir (la dernière est un récapitulatif).
        static let formSteps: [Step] = [.tastes, .neighborhood, .household]

        var title: String {
            switch self {
            case .tastes: String(localized: "Qu'est-ce que tu aimes acheter ?")
            case .neighborhood: String(localized: "Où habites-tu ?")
            case .household: String(localized: "Ton ménage")
            case .done: String(localized: "Tout est prêt !")
            }
        }

        var subtitle: String {
            switch self {
            case .tastes: String(localized: "On mettra ces lots en premier. Tu pourras changer d'avis dans ton profil.")
            case .neighborhood: String(localized: "Ton code postal nous dit quels groupes sont près de chez toi. On ne garde jamais ton adresse.")
            case .household: String(localized: "Le nombre de personnes aide l'organisateur à prévoir les quantités.")
            case .done: String(localized: "Voici ce qu'on a retenu. Ton tableau de bord t'attend.")
            }
        }

        var systemImage: String {
            switch self {
            case .tastes: "basket.fill"
            case .neighborhood: "mappin.and.ellipse"
            case .household: "person.2.fill"
            case .done: "checkmark.seal.fill"
            }
        }
    }

    /// Récapitulatif en français (« Céréales et Œufs »), comme le reste des textes de l'app.
    nonisolated static let frenchLocale = Locale(identifier: "fr_CA")

    /// Taille de ménage acceptée (même plage que le profil du ménage).
    static let sizeRange = HouseholdProfileViewModel.sizeRange
    /// Longueur maximale du nom du ménage (même limite que le profil du ménage).
    nonisolated static let maxNameLength = 40

    private let repositories: AppRepositories
    private let userId: String
    private let householdId: String

    private(set) var loadState: LoadState<AppUser> = .idle
    private var household: Household?

    private(set) var step: Step = .tastes

    // Goûts.
    private(set) var favoriteCategories: Set<Product.Category> = []
    private(set) var dietaryPreferences: Set<DietaryTag> = []

    // Quartier.
    var postalCode = "" {
        didSet {
            if let found = MontrealNeighborhood.lookup(postalCode: postalCode).neighborhood {
                neighborhood = found
            }
        }
    }
    var neighborhood: MontrealNeighborhood?

    // Ménage.
    var householdName = ""
    var householdSize = 1

    private(set) var isSaving = false
    private(set) var saveError: AppError?

    init(repositories: AppRepositories, userId: String, householdId: String) {
        self.repositories = repositories
        self.userId = userId
        self.householdId = householdId
    }

    convenience init(context: AppContext) {
        self.init(repositories: context.repositories, userId: context.userId, householdId: context.householdId)
    }

    // MARK: Lecture

    /// Lit le profil (et le ménage créé à l'inscription) pour pré-remplir les étapes.
    func load() async {
        if loadState.value == nil { loadState = .loading }
        do {
            let user = try await repositories.users.user(id: userId)
            var household: Household?
            let id = user.householdId ?? householdId
            if !id.isEmpty {
                household = try? await repositories.users.household(id: id)
            }
            apply(user: user, household: household)
            loadState = .loaded(user)
        } catch {
            loadState = .failed(AppError(error))
        }
    }

    private func apply(user: AppUser, household: Household?) {
        self.household = household
        favoriteCategories = Set(user.favoriteCategories ?? [])
        dietaryPreferences = Set(user.dietaryPreferences)
        neighborhood = MontrealNeighborhood.named(user.neighborhood)
        householdName = household?.name ?? Self.defaultHouseholdName(for: user.displayName)
        householdSize = min(max(household?.size ?? 1, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
    }

    /// « Famille Benali » à partir de « Amina Benali » ; « Ménage d'Amina » s'il n'y a qu'un prénom.
    nonisolated static func defaultHouseholdName(for displayName: String) -> String {
        let parts = displayName.split(separator: " ").map(String.init)
        if parts.count >= 2, let last = parts.last {
            return String(String(localized: "Famille \(last)").prefix(maxNameLength))
        }
        guard let first = parts.first else { return String(localized: "Mon ménage") }
        return String(String(localized: "Ménage de \(first)").prefix(maxNameLength))
    }

    // MARK: Goûts

    func isSelected(_ category: Product.Category) -> Bool { favoriteCategories.contains(category) }
    func isSelected(_ tag: DietaryTag) -> Bool { dietaryPreferences.contains(tag) }

    func toggle(_ category: Product.Category) {
        if favoriteCategories.contains(category) { favoriteCategories.remove(category) } else { favoriteCategories.insert(category) }
    }

    func toggle(_ tag: DietaryTag) {
        if dietaryPreferences.contains(tag) { dietaryPreferences.remove(tag) } else { dietaryPreferences.insert(tag) }
    }

    // MARK: Quartier

    var postalLookup: MontrealNeighborhood.Lookup { MontrealNeighborhood.lookup(postalCode: postalCode) }

    /// Message sous le champ code postal, ou `nil`.
    var postalMessage: String? {
        switch postalLookup {
        case .empty, .incomplete: nil
        case .invalid: String(localized: "Un code postal a la forme H2A 1B3.")
        case .notServed: String(localized: "LeGrenier n'est pas encore offert dans ce secteur. Choisis le quartier le plus proche.")
        case .found(let found): String(localized: "Quartier trouvé : \(found.name).")
        }
    }

    // MARK: Ménage

    var trimmedName: String { householdName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var nameError: String? {
        if trimmedName.isEmpty { return String(localized: "Donne un nom à ton ménage (ex. « Famille Benali »).") }
        if trimmedName.count > Self.maxNameLength { return String(localized: "40 caractères au plus.") }
        return nil
    }

    // MARK: Navigation

    /// Peut-on passer à l'étape suivante ? Les goûts sont facultatifs ; quartier et nom du ménage, non.
    var canContinue: Bool {
        guard loadState.value != nil, !isSaving else { return false }
        switch step {
        case .tastes: return true
        case .neighborhood: return neighborhood != nil
        case .household: return nameError == nil && Self.sizeRange.contains(householdSize)
        case .done: return true
        }
    }

    var canGoBack: Bool { step != .tastes && step != .done && !isSaving }

    /// Rang de l'étape à remplir (1 à 3), pour « Étape 2 sur 3 ».
    var stepNumber: Int { (Step.formSteps.firstIndex(of: step) ?? Step.formSteps.count - 1) + 1 }
    var stepCount: Int { Step.formSteps.count }
    /// Avancement de 0 à 1 pour la barre du haut (1/3 à la première étape, plein à la fin).
    var progress: Double { step == .done ? 1 : Double(stepNumber) / Double(stepCount) }

    /// Étape suivante. Après le ménage, enregistre tout ; on n'arrive à « Tout est prêt » que si ça a marché.
    func next() async {
        guard canContinue else { return }
        switch step {
        case .tastes: step = .neighborhood
        case .neighborhood: step = .household
        case .household:
            if await save() { step = .done }
        case .done: break
        }
    }

    func back() {
        guard canGoBack, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        saveError = nil
    }

    // MARK: Enregistrement

    /// Id du ménage enregistré (celui de l'inscription, ou un nouveau si le compte n'en avait pas).
    private(set) var savedHouseholdId: String?

    /// Enregistre ménage puis profil. Renvoie vrai si tout est passé.
    @discardableResult
    func save() async -> Bool {
        guard var user = loadState.value, let neighborhood, nameError == nil else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        var household = household ?? Household(
            id: "household-\(UUID().uuidString.lowercased())",
            name: trimmedName,
            size: householdSize,
            geohash: "",
            userIds: [userId]
        )
        household.name = trimmedName
        household.size = householdSize
        household.geohash = neighborhood.geohash
        if !household.userIds.contains(userId) { household.userIds.append(userId) }

        user.householdId = household.id
        user.neighborhood = neighborhood.name
        // Ordre stable (celui des enums) pour ne pas réécrire le document pour rien.
        user.dietaryPreferences = DietaryTag.allCases.filter(dietaryPreferences.contains)
        user.favoriteCategories = Product.Category.allCases.filter(favoriteCategories.contains)
        if !user.roles.contains(.family) { user.roles.append(.family) }
        user.onboardingCompleted = true

        do {
            try await repositories.users.saveHousehold(household)
            try await repositories.users.saveUser(user)
            self.household = household
            loadState = .loaded(user)
            savedHouseholdId = household.id
            return true
        } catch {
            saveError = AppError(error)
            return false
        }
    }

    /// « Plus tard » : on ne remontre pas l'onboarding, sans rien changer d'autre au profil.
    @discardableResult
    func skip() async -> Bool {
        guard var user = loadState.value else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        user.onboardingCompleted = true
        do {
            try await repositories.users.saveUser(user)
            loadState = .loaded(user)
            savedHouseholdId = user.householdId ?? householdId
            return true
        } catch {
            saveError = AppError(error)
            return false
        }
    }

    // MARK: Récapitulatif

    /// « Céréales, Œufs » ou « Tout m'intéresse ».
    var tastesSummary: String {
        let titles = Product.Category.allCases.filter(favoriteCategories.contains).map(\.title)
        return titles.isEmpty ? String(localized: "Tout m'intéresse") : titles.formatted(.list(type: .and).locale(Self.frenchLocale))
    }

    /// « Halal, Sans gluten » ou « Aucune ».
    var dietarySummary: String {
        let titles = DietaryTag.allCases.filter(dietaryPreferences.contains).map(PreferencesViewModel.title(of:))
        return titles.isEmpty ? String(localized: "Aucune") : titles.formatted(.list(type: .and).locale(Self.frenchLocale))
    }

    /// « Famille Benali · 4 personnes ».
    var householdSummary: String {
        "\(trimmedName) · \(FrenchPlural.count(householdSize, "personne"))"
    }

    // MARK: Portail

    /// Fin de l'onboarding : ouvre le portail Familles, sauf si la personne n'a choisi que d'autres portails.
    static func openFamilyPortalIfChosen(in defaults: UserDefaults = .standard) {
        let choice = PortalChoice.stored(in: defaults)
        guard choice == nil || choice?.portals.contains(.family) == true else { return }
        defaults.set(Portal.family.rawValue, forKey: Portal.storageKey)
    }
}
