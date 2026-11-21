// HouseholdProfileViewModel.swift
// RQ-015 (ménage : nom, taille, quartier) et RQ-020 (statut subventionné par code d'organisme, privé).

import Foundation
import Observation

@Observable @MainActor
final class HouseholdProfileViewModel {
    /// Taille d'un ménage acceptée.
    static let sizeRange = 1...12

    private let repositories: AppRepositories
    private let privateStore: any HouseholdPrivateStore
    private let userId: String
    private let householdId: String
    /// Codes remis par les organismes ; vide = tout code bien formé est accepté (démo).
    private let issuedCodes: Set<String>

    private(set) var state: LoadState<Household> = .idle
    private var user: AppUser?

    // Champs éditables.
    var name = ""
    var size = 1
    var postalCode = "" {
        didSet {
            if let found = MontrealNeighborhood.lookup(postalCode: postalCode).neighborhood {
                neighborhood = found
            }
        }
    }
    /// Quartier choisi : trouvé par le code postal ou choisi dans la liste.
    var neighborhood: MontrealNeighborhood?

    private(set) var isSaving = false
    private(set) var saveError: AppError?
    /// Incrémenté à chaque enregistrement réussi (déclencheur d'haptique et de confirmation).
    private(set) var saveCount = 0

    // Statut subventionné (RQ-020).
    private(set) var privateProfile: HouseholdPrivate?
    var codeInput = "" { didSet { codeError = nil } }
    private(set) var codeError: String?
    private(set) var isRedeeming = false
    private(set) var redeemCount = 0

    init(repositories: AppRepositories, privateStore: any HouseholdPrivateStore,
         userId: String, householdId: String, issuedCodes: Set<String> = []) {
        self.repositories = repositories
        self.privateStore = privateStore
        self.userId = userId
        self.householdId = householdId
        self.issuedCodes = issuedCodes
    }

    convenience init(context: AppContext, privateStore: any HouseholdPrivateStore) {
        self.init(repositories: context.repositories, privateStore: privateStore,
                  userId: context.userId, householdId: context.householdId)
    }

    // MARK: Lecture

    func load() async {
        if state.value == nil { state = .loading }
        do {
            async let user = repositories.users.user(id: userId)
            async let household = repositories.users.household(id: householdId)
            async let privateProfile = privateStore.privateProfile(householdId: householdId)
            let (loadedUser, loadedHousehold, loadedPrivate) = try await (user, household, privateProfile)
            self.user = loadedUser
            self.privateProfile = loadedPrivate
            name = loadedHousehold.name
            size = loadedHousehold.size
            neighborhood = MontrealNeighborhood.named(loadedUser.neighborhood)
            state = .loaded(loadedHousehold)
        } catch {
            state = .failed(AppError(error))
        }
    }

    // MARK: Validation

    var postalLookup: MontrealNeighborhood.Lookup { MontrealNeighborhood.lookup(postalCode: postalCode) }

    /// Message sous le champ code postal, ou `nil`.
    var postalMessage: String? {
        switch postalLookup {
        case .empty, .incomplete: nil
        case .invalid: "Un code postal a la forme H2A 1B3."
        case .notServed: "Grenier n'est pas encore offert dans ce secteur. Choisis le quartier le plus proche."
        case .found(let found): "Quartier trouvé : \(found.name)."
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var nameError: String? {
        if trimmedName.isEmpty { return "Donne un nom à ton ménage (ex. « Famille Benali »)." }
        if trimmedName.count > 40 { return "40 caractères au plus." }
        return nil
    }

    var hasChanges: Bool {
        guard let household = state.value else { return false }
        return trimmedName != household.name
            || size != household.size
            || neighborhood?.name != user?.neighborhood
    }

    var canSave: Bool {
        state.value != nil && nameError == nil && neighborhood != nil
            && Self.sizeRange.contains(size) && hasChanges && !isSaving
    }

    // MARK: Enregistrement

    func save() async {
        guard canSave, var household = state.value, var user, let neighborhood else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        household.name = trimmedName
        household.size = size
        household.geohash = neighborhood.geohash
        user.neighborhood = neighborhood.name
        do {
            try await repositories.users.saveHousehold(household)
            try await repositories.users.saveUser(user)
            self.user = user
            name = household.name
            state = .loaded(household)
            saveCount += 1
        } catch {
            saveError = AppError(error)
        }
    }

    // MARK: Statut subventionné

    var isSubsidized: Bool { privateProfile?.isSubsidized == true }

    var canRedeem: Bool {
        !codeInput.trimmingCharacters(in: .whitespaces).isEmpty && !isRedeeming && state.value != nil
    }

    func redeemCode() async {
        guard canRedeem else { return }
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            let profile = try ReferralCode.subsidizedProfile(redeeming: codeInput, issuedCodes: issuedCodes)
            try await privateStore.savePrivateProfile(profile, householdId: householdId)
            privateProfile = profile
            codeInput = ""
            redeemCount += 1
        } catch let AppError.invalidInput(message) {
            codeError = message
        } catch {
            codeError = AppError(error).message
        }
    }

    /// Retire le statut (le ménage n'en a plus besoin).
    func withdrawSubsidy() async {
        isRedeeming = true
        defer { isRedeeming = false }
        let profile = HouseholdPrivate(isSubsidized: false, referralCode: nil)
        do {
            try await privateStore.savePrivateProfile(profile, householdId: householdId)
            privateProfile = profile
        } catch {
            codeError = AppError(error).message
        }
    }
}
