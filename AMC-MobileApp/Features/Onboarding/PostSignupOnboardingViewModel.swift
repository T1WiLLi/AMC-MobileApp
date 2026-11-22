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
        /// T-159 : un ménage est déjà inscrit à cette adresse — le rejoindre ou en créer un nouveau.
        case joinChoice
        /// T-159 : demande envoyée, en attente du propriétaire.
        case waiting
        case done

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Étapes à remplir (la dernière est un récapitulatif).
        static let formSteps: [Step] = [.tastes, .neighborhood, .household]

        var title: String {
            switch self {
            case .tastes: String(localized: "Qu'est-ce que tu aimes acheter ?")
            case .neighborhood: String(localized: "Où habites-tu ?")
            case .household: String(localized: "Ton ménage")
            case .joinChoice: String(localized: "Ta famille est déjà inscrite ?")
            case .waiting: String(localized: "Demande envoyée")
            case .done: String(localized: "Tout est prêt !")
            }
        }

        var subtitle: String {
            switch self {
            case .tastes: String(localized: "On mettra ces lots en premier. Tu pourras changer d'avis dans ton profil.")
            case .neighborhood: String(localized: "Ton code postal nous dit quels groupes sont près de chez toi.")
            case .household: String(localized: "Ton adresse sert seulement à retrouver ta famille si elle utilise déjà LeGrenier. Personne d'autre ne la voit.")
            case .joinChoice: String(localized: "Un ménage existe déjà à cette adresse. Rejoins-le pour partager vos groupes, vos commandes et vos cueillettes.")
            case .waiting: String(localized: "Le propriétaire du ménage doit accepter ta demande. Tu peux fermer l'app : tu entreras dans le ménage dès qu'il aura accepté.")
            case .done: String(localized: "Voici ce qu'on a retenu. Ton tableau de bord t'attend.")
            }
        }

        var systemImage: String {
            switch self {
            case .tastes: "basket.fill"
            case .neighborhood: "mappin.and.ellipse"
            case .household: "person.2.fill"
            case .joinChoice: "house.and.flag.fill"
            case .waiting: "hourglass"
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

    // Adresse (T-159) : numéro et rue ici, code postal partagé avec l'étape quartier.
    var streetNumber = ""
    var street = ""
    /// Ménage trouvé à l'adresse saisie (son nom seulement), `nil` s'il n'y en a pas.
    private(set) var match: HouseholdAddressEntry?
    /// Demande envoyée, tant qu'elle attend le propriétaire.
    private(set) var joinRequest: HouseholdJoinRequest?
    /// La demande a disparu sans être acceptée : le propriétaire l'a refusée.
    private(set) var joinDeclined = false
    private(set) var isCheckingJoin = false

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
            // Relancé pendant l'attente (app fermée) : on revient sur l'écran d'attente.
            if let pendingId = user.pendingHouseholdId, !pendingId.isEmpty {
                joinRequest = try? await repositories.users.joinRequest(householdId: pendingId, userId: userId)
                step = .waiting
                await checkJoin()
            }
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

    // MARK: Adresse (T-159)

    var address: HouseholdAddress {
        HouseholdAddress(streetNumber: streetNumber, street: street, postalCode: postalCode)
    }

    /// Adresse laissée vide : facultative (pas de recherche de ménage, rien d'enregistré).
    var isAddressEmpty: Bool {
        streetNumber.trimmingCharacters(in: .whitespaces).isEmpty && street.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Message sous les champs d'adresse commencée mais incomplète, ou `nil` (complète ou laissée vide).
    var addressError: String? {
        if isAddressEmpty { return nil }
        if address.normalizedNumber.isEmpty { return String(localized: "Entre ton numéro civique (ex. 1234).") }
        if address.normalizedStreet.isEmpty { return String(localized: "Entre le nom de ta rue (ex. rue Jarry Est).") }
        if address.normalizedPostalCode.isEmpty { return String(localized: "Entre ton code postal (ex. H2R 1A1).") }
        return nil
    }

    /// Nom du ménage trouvé ou demandé (« Famille Benali »).
    var matchName: String { match?.name ?? joinRequest?.householdName ?? String(localized: "ce ménage") }

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
        case .household: return nameError == nil && addressError == nil && Self.sizeRange.contains(householdSize)
        case .joinChoice: return match != nil
        case .waiting: return !isCheckingJoin
        case .done: return true
        }
    }

    var canGoBack: Bool { step != .tastes && step != .done && step != .waiting && !isSaving }

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
            // Un ménage existe déjà à cette adresse (et ce n'est pas le nôtre) : on propose de le rejoindre.
            if let found = await lookUpAddress() {
                match = found
                step = .joinChoice
            } else if await save() {
                step = .done
            }
        case .joinChoice:
            if await requestJoin() { step = .waiting }
        case .waiting:
            if joinDeclined {
                if await save() { step = .done }
            } else {
                await checkJoin()
            }
        case .done: break
        }
    }

    func back() {
        guard canGoBack else { return }
        let previous: Step? = step == .joinChoice ? .household : Step(rawValue: step.rawValue - 1)
        guard let previous else { return }
        step = previous
        saveError = nil
    }

    // MARK: Rejoindre un ménage (T-159)

    /// Ménage inscrit à l'adresse saisie, sauf le nôtre. `nil` sans adresse, sans ménage, ou si la lecture échoue
    /// (on crée alors un ménage, comme avant T-159).
    private func lookUpAddress() async -> HouseholdAddressEntry? {
        guard let lookupId = address.lookupId,
              let found = try? await repositories.users.householdAddress(lookupId: lookupId) else { return nil }
        let own = household?.id ?? householdId
        guard found.householdId != own, found.ownerId != userId else { return nil }
        return found
    }

    /// « Rejoindre » : envoie la demande et garde les préférences. L'onboarding reste ouvert (écran d'attente)
    /// jusqu'à l'acceptation, même si l'app est relancée (`pendingHouseholdId`).
    @discardableResult
    func requestJoin() async -> Bool {
        guard var user = loadState.value, let match, let neighborhood else { return false }
        isSaving = true
        saveError = nil
        joinDeclined = false
        defer { isSaving = false }
        let request = HouseholdJoinRequest(householdId: match.householdId, userId: userId, displayName: user.displayName,
                                           householdName: match.name, createdAt: .now, status: .pending)
        applyPreferences(to: &user, neighborhood: neighborhood)
        user.pendingHouseholdId = match.householdId
        do {
            try await repositories.users.requestToJoin(request)
            try await repositories.users.saveUser(user)
            joinRequest = request
            loadState = .loaded(user)
            return true
        } catch {
            saveError = AppError(error)
            return false
        }
    }

    /// Regarde si le propriétaire a répondu. Acceptée : le profil pointe vers le ménage, onboarding fini.
    /// Disparue : refusée (on propose de créer un ménage). Sinon : on attend encore.
    func checkJoin() async {
        guard var user = loadState.value, let pendingId = user.pendingHouseholdId, !pendingId.isEmpty else { return }
        isCheckingJoin = true
        defer { isCheckingJoin = false }
        do {
            let current = try await repositories.users.joinRequest(householdId: pendingId, userId: userId)
            guard let current else {
                joinDeclined = true
                return
            }
            joinRequest = current
            guard current.status == .accepted else { return }
            user = try await AppContextResolver(repositories: repositories).finishJoinIfAccepted(user)
            user.onboardingCompleted = true
            try await repositories.users.saveUser(user)
            loadState = .loaded(user)
            savedHouseholdId = pendingId
            joinedHouseholdName = current.householdName ?? match?.name
            joinDeclined = false
            step = .done
        } catch {
            saveError = AppError(error)
        }
    }

    /// Annule la demande et revient au choix (ou au ménage, si on ne connaît plus l'adresse trouvée).
    func cancelJoin() async {
        guard var user = loadState.value else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            if let pendingId = user.pendingHouseholdId, !pendingId.isEmpty {
                try await repositories.users.deleteJoinRequest(householdId: pendingId, userId: userId)
            }
            user.pendingHouseholdId = nil
            try await repositories.users.saveUser(user)
            loadState = .loaded(user)
            joinRequest = nil
            joinDeclined = false
            step = match == nil ? .household : .joinChoice
        } catch {
            saveError = AppError(error)
        }
    }

    /// « Créer un nouveau ménage » (au choix, ou à la place d'une demande en attente ou refusée).
    @discardableResult
    func createOwnHousehold() async -> Bool {
        if loadState.value?.pendingHouseholdId != nil {
            await cancelJoin()
            guard saveError == nil else { return false }
        }
        guard await save() else { return false }
        step = .done
        return true
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
        // T-159 : propriétaire (le créateur), clé d'adresse, nom affiché du membre.
        if household.ownerId == nil { household.ownerId = HouseholdMembership.ownerId(of: household) ?? userId }
        if let key = address.key { household.addressKey = key }
        household.memberNames = (household.memberNames ?? [:]).merging([userId: user.displayName]) { _, new in new }

        user.householdId = household.id
        user.pendingHouseholdId = nil
        applyPreferences(to: &user, neighborhood: neighborhood)
        user.onboardingCompleted = true

        do {
            try await repositories.users.saveHousehold(household)
            // Inscription à l'adresse : un détail (adresse déjà prise par un autre ménage, hors ligne…).
            if let lookupId = address.lookupId, HouseholdMembership.isOwner(userId, of: household) {
                try? await repositories.users.registerHouseholdAddress(
                    HouseholdAddressEntry(id: lookupId, householdId: household.id, name: household.name, ownerId: userId)
                )
            }
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

    private func applyPreferences(to user: inout AppUser, neighborhood: MontrealNeighborhood) {
        user.neighborhood = neighborhood.name
        // Ordre stable (celui des enums) pour ne pas réécrire le document pour rien.
        user.dietaryPreferences = DietaryTag.allCases.filter(dietaryPreferences.contains)
        user.favoriteCategories = Product.Category.allCases.filter(favoriteCategories.contains)
        if !user.roles.contains(.family) { user.roles.append(.family) }
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

    /// « Famille Benali · 4 personnes », ou « Famille Benali · tu en fais partie » après avoir rejoint un ménage.
    var householdSummary: String {
        if let joinedHouseholdName { return String(localized: "\(joinedHouseholdName) · tu en fais partie") }
        return "\(trimmedName) · \(FrenchPlural.count(householdSize, "personne"))"
    }

    /// Nom du ménage rejoint (T-159), `nil` si la personne a créé le sien.
    private(set) var joinedHouseholdName: String?

    #if DEBUG
    /// Previews : montre directement le choix « Rejoindre ou créer ».
    func previewJoinChoice(_ match: HouseholdAddressEntry) {
        self.match = match
        step = .joinChoice
    }
    #endif

    // MARK: Portail

    /// Fin de l'onboarding : ouvre le portail Familles, sauf si la personne n'a choisi que d'autres portails.
    static func openFamilyPortalIfChosen(in defaults: UserDefaults = .standard) {
        let choice = PortalChoice.stored(in: defaults)
        guard choice == nil || choice?.portals.contains(.family) == true else { return }
        defaults.set(Portal.family.rawValue, forKey: Portal.storageKey)
    }
}
