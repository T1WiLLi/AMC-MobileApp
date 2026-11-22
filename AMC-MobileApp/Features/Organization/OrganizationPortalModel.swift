// OrganizationPortalModel.swift
// ViewModel partagé par les onglets du portail Organismes (T-116, RQ-081) : Tableau, Financer, Parrainages,
// Impact et Recherche. Un seul modèle pour que chaque financement ou parrainage se voie partout tout de suite.
// T-208 : les groupes sont ceux de la recherche de groupes du portail Famille (`GroupRepository.groups(inNeighborhood:
// nil)`, même tri par distance via `GroupsViewModel.items`) ; le fonds, le besoin et le parrainage s'y ajoutent.
// Les autres organismes (fiches publiques) alimentent la carte.
//
// Usage :
//   @State private var model = OrganizationPortalModel(repository: context.repositories.organizations,
//                                                      groups: context.repositories.groups,
//                                                      organizationId: context.organizationId)
//   .task { await model.loadIfNeeded() }  ·  .refreshable { await model.load() }

import Foundation
import Observation

@Observable @MainActor
final class OrganizationPortalModel {
    /// Tout ce que le portail affiche.
    nonisolated struct Snapshot: Sendable, Equatable {
        var organization: Organization
        var profiles: [GroupSolidarityProfile]
        var donations: [OrganizationDonation]
        var sponsorships: [Sponsorship]
        /// T-208 : fiches publiques des organismes (carte), l'organisme connecté compris.
        var directory: [OrganizationDirectoryEntry] = []
    }

    /// Une ligne du fil « Notre impact ».
    nonisolated struct TimelineEvent: Identifiable, Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case baskets
            case fund
            case sponsorship
        }

        var id: String
        var date: Date
        var kind: Kind
        var title: String
        var detail: String

        var systemImage: String {
            switch kind {
            case .baskets: "basket.fill"
            case .fund: "heart.circle.fill"
            case .sponsorship: "hands.and.sparkles.fill"
            }
        }
    }

    private(set) var state: LoadState<Snapshot> = .idle
    /// Texte de l'onglet Recherche.
    var searchText = ""
    private(set) var isSubmitting = false
    /// Dernier financement réussi (écran de remerciement de la feuille).
    private(set) var lastDonation: OrganizationDonation?
    /// Compteur de financements réussis : déclencheur de l'haptique de succès.
    private(set) var completedActions = 0
    /// Erreur de la dernière action (financer, parrainer), affichée dans la feuille.
    private(set) var actionError: AppError?

    private let repository: any OrganizationRepository
    /// T-208 : source des groupes, la même que la recherche de groupes du portail Famille. nil (aperçus, tests du
    /// registre seul) : les groupes du dépôt d'organismes.
    private let groups: (any GroupRepository)?
    let organizationId: String

    init(repository: any OrganizationRepository, groups: (any GroupRepository)? = nil, organizationId: String) {
        self.repository = repository
        self.groups = groups
        self.organizationId = organizationId
    }

    var snapshot: Snapshot? { state.value }

    // MARK: Chargement

    func loadIfNeeded() async {
        switch state {
        case .idle: await load()
        case .failed(let error) where error.isCancellation: await load()
        default: break
        }
    }

    func load() async {
        if snapshot == nil { state = .loading }
        do {
            async let organization = repository.organization(id: organizationId)
            async let profiles = loadProfiles()
            async let donations = repository.donations(ofOrganization: organizationId)
            async let sponsorships = repository.sponsorships(ofOrganization: organizationId)
            // La carte des organismes est un plus : sans elle (règles pas encore déployées), le portail reste utilisable.
            async let directory = try? repository.directory()
            state = .loaded(Snapshot(
                organization: try await organization,
                profiles: try await profiles,
                donations: try await donations,
                sponsorships: try await sponsorships,
                directory: await directory ?? []
            ))
        } catch {
            // Un rafraîchissement raté garde l'écran déjà chargé.
            if snapshot == nil { state = .failed(AppError(error)) }
        }
    }

    /// Les groupes publics de la recherche du portail Famille, avec leur fonds.
    private func loadProfiles() async throws -> [GroupSolidarityProfile] {
        guard let groups else { return try await repository.solidarityProfiles() }
        return try await repository.solidarityProfiles(of: groups.groups(inNeighborhood: nil))
    }

    // MARK: Lectures dérivées

    /// T-208 : tous les groupes, dans l'ordre de la recherche de groupes du portail Famille (`GroupsViewModel.items`) :
    /// du plus proche au plus loin du siège de l'organisme, par nom si la distance est inconnue.
    var groupsByDistance: [GroupSolidarityProfile] {
        guard let snapshot else { return [] }
        let byId = Dictionary(snapshot.profiles.map { ($0.groupId, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = GroupsViewModel.items(
            publicGroups: snapshot.profiles.compactMap(\.group), householdGroups: [], neighborhood: nil,
            origin: Geohash.center(of: snapshot.organization.geohash)
        ).compactMap { byId[$0.id] }
        // Profils sans groupe (anciennes données fake) : à la suite, par nom.
        let rest = snapshot.profiles.filter { $0.group == nil }
            .sorted { $0.groupName.localizedStandardCompare($1.groupName) == .orderedAscending }
        return ordered + rest
    }

    /// Groupe affiché par la recherche de groupes (photo, bannière), nil s'il est inconnu.
    func group(id: String) -> NeighborhoodGroup? {
        profile(id: id)?.group
    }

    /// T-208 : les autres organismes (carte), sans l'organisme connecté.
    var otherOrganizations: [OrganizationDirectoryEntry] {
        (snapshot?.directory ?? []).filter { $0.id != organizationId }
    }

    /// T-208 : lieux de la carte du portail : les groupes de la liste, les autres organismes et le sien.
    var mapPlaces: [OrganizationMapPlace] {
        guard let snapshot else { return [] }
        return Self.mapPlaces(groups: groupsByDistance, directory: snapshot.directory,
                              organization: snapshot.organization)
    }

    /// Lieux localisables (geohash valide). L'organisme connecté y est même s'il manque à l'annuaire
    /// (règles pas encore déployées) : sa propre position vient de son document.
    nonisolated static func mapPlaces(
        groups: [GroupSolidarityProfile], directory: [OrganizationDirectoryEntry], organization: Organization
    ) -> [OrganizationMapPlace] {
        var organizations = directory.filter { $0.id != organization.id }
        organizations.insert(OrganizationDirectoryEntry(organization), at: 0)
        let groupPlaces = groups.compactMap { profile -> OrganizationMapPlace? in
            guard let coordinate = Geohash.center(of: profile.centerGeohash) else { return nil }
            return OrganizationMapPlace(detail: .group(profile), coordinate: coordinate)
        }
        let organizationPlaces = organizations.compactMap { entry -> OrganizationMapPlace? in
            guard let coordinate = Geohash.center(of: entry.geohash) else { return nil }
            return OrganizationMapPlace(detail: .organization(entry, isMine: entry.id == organization.id),
                                        coordinate: coordinate)
        }
        return groupPlaces + organizationPlaces
    }

    var impact: OrganizationLedger.ImpactSummary {
        guard let snapshot else { return .empty }
        return OrganizationLedger.summarize(donations: snapshot.donations, sponsorships: snapshot.sponsorships)
    }

    /// Groupes par besoin décroissant, les plus proches de l'organisme d'abord à besoin égal.
    var prioritizedGroups: [GroupSolidarityProfile] {
        guard let snapshot else { return [] }
        return OrganizationLedger.prioritized(snapshot.profiles, from: snapshot.organization.geohash)
    }

    /// Groupes qui ont besoin d'aide (urgent ou modéré).
    var groupsInNeed: [GroupSolidarityProfile] {
        prioritizedGroups.filter { $0.needLevel != .covered }
    }

    var sponsoredGroups: [GroupSolidarityProfile] {
        prioritizedGroups.filter { $0.isSponsored(by: organizationId) }
    }

    /// Groupes à parrainer : tous les autres, dans l'ordre de la recherche de groupes (T-208).
    var sponsorableGroups: [GroupSolidarityProfile] {
        groupsByDistance.filter { !$0.isSponsored(by: organizationId) }
    }

    func profile(id: String) -> GroupSolidarityProfile? {
        snapshot?.profiles.first { $0.groupId == id }
    }

    func sponsorship(ofGroup groupId: String) -> Sponsorship? {
        snapshot?.sponsorships.first { $0.groupId == groupId }
    }

    /// Paniers financés pour ce groupe pendant le mois en cours (progrès d'un parrainage).
    func basketsThisMonth(groupId: String, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return (snapshot?.donations ?? [])
            .filter { $0.groupId == groupId && month.contains($0.date) }
            .reduce(0) { $0 + $1.basketCount }
    }

    /// Recherche par nom de groupe ou quartier, sans tenir compte des accents ni de la casse.
    var searchResults: [GroupSolidarityProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groupsByDistance }
        return groupsByDistance.filter {
            $0.groupName.localizedStandardContains(query) || $0.neighborhood.localizedStandardContains(query)
        }
    }

    /// Quartiers proposés sous le champ de recherche : ceux qui contiennent le texte tapé, sauf celui déjà choisi.
    /// T-202 : sans ce filtre, la liste complète restait affichée par-dessus les résultats (et l'état vide).
    var neighborhoodSuggestions: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = Array(Set(snapshot?.profiles.map(\.neighborhood) ?? [])).sorted()
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.localizedStandardContains(query) && $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
    }

    /// « 1,2 km » depuis le siège de l'organisme ; nil sans géolocalisation.
    func distanceText(for profile: GroupSolidarityProfile) -> String? {
        distanceText(toGeohash: profile.centerGeohash)
    }

    /// « 850 m », « 3,4 km » entre le siège de l'organisme et un geohash ; nil si l'un est inconnu.
    func distanceText(toGeohash geohash: String) -> String? {
        guard let origin = snapshot?.organization.geohash,
              let meters = Geohash.distanceMeters(from: origin, to: geohash) else { return nil }
        if meters < 1_000 { return "\(Int((meters / 50).rounded()) * 50) m" }
        return Measurement(value: meters / 1_000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
                .locale(AppLanguage.formattingLocale))
    }

    /// Aperçu d'un financement (montant, paniers, familles), ou l'erreur de saisie.
    func plan(_ request: DonationRequest, for profile: GroupSolidarityProfile) -> Result<OrganizationLedger.Plan, AppError> {
        do {
            return .success(try OrganizationLedger.plan(request, for: profile))
        } catch {
            return .failure(AppError(error))
        }
    }

    /// Derniers dons, du plus récent au plus ancien (historique du Tableau, T-207).
    func recentDonations(limit: Int = 5) -> [OrganizationDonation] {
        Array((snapshot?.donations ?? []).sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }

    /// Reçu d'un don de l'historique ; nil pour un événement qui n'est pas un don (parrainage).
    func receipt(forDonationId id: String) -> OrganizationPaymentReceipt? {
        snapshot?.donations.first { $0.id == id }.map { OrganizationPaymentReceipt.make(donation: $0) }
    }

    /// Fil d'impact : financements et débuts de parrainage, du plus récent au plus ancien.
    var timeline: [TimelineEvent] {
        guard let snapshot else { return [] }
        let donations = snapshot.donations.map { donation in
            TimelineEvent(
                id: donation.id, date: donation.date,
                kind: donation.kind == .suspendedBaskets ? .baskets : .fund,
                title: donation.kind == .suspendedBaskets
                    ? String(localized: "\(FrenchPlural.count(donation.basketCount, "panier suspendu", plural: "paniers suspendus")) à \(donation.groupName)")
                    : String(localized: "Don de \(Money.formatRounded(donation.amountCents)) au fonds de \(donation.groupName)"),
                detail: donation.householdsReached > 0
                    ? String(localized: "\(FrenchPlural.count(donation.householdsReached, "famille aidée", plural: "familles aidées")) · \(Money.formatRounded(donation.amountCents))")
                    : String(localized: "\(Money.formatRounded(donation.amountCents)) en réserve dans le fonds")
            )
        }
        let sponsorships = snapshot.sponsorships.map { sponsorship in
            TimelineEvent(
                id: "sponsorship-\(sponsorship.id)", date: sponsorship.startedAt, kind: .sponsorship,
                title: String(localized: "Parrainage de \(sponsorship.groupName)"),
                detail: String(localized: "Objectif : \(FrenchPlural.count(sponsorship.monthlyBasketGoal, "panier")) par mois · \(MontrealNeighborhood.displayName(for: sponsorship.neighborhood))")
            )
        }
        return (donations + sponsorships).sorted { $0.date > $1.date }
    }

    /// Phrase du récit d'impact, à partager.
    var impactStory: String {
        let impact = impact
        guard let snapshot, impact.basketsFunded > 0 else {
            return String(localized: "Ton premier panier suspendu financé apparaîtra ici.")
        }
        let quartiers = FrenchPlural.count(impact.groupsReached, "groupe de quartier", plural: "groupes de quartier")
        return String(localized: "\(snapshot.organization.name) a financé \(FrenchPlural.count(impact.basketsFunded, "panier")) pour \(FrenchPlural.count(impact.familiesHelped, "famille")) dans \(quartiers) avec LeGrenier.")
    }

    // MARK: Actions

    /// Finance un groupe (simulation). Vrai si c'est fait ; sinon `actionError` explique pourquoi.
    @discardableResult
    func donate(_ request: DonationRequest, toGroup groupId: String) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }
        do {
            let donation = try await repository.donate(request, toGroup: groupId, organizationId: organizationId)
            let profile = try? await repository.solidarityProfile(groupId: groupId)
            if var snapshot {
                snapshot.donations.insert(donation, at: 0)
                if var profile, let index = snapshot.profiles.firstIndex(where: { $0.groupId == groupId }) {
                    // Le groupe affiché (médias résolus) reste celui de la liste.
                    profile.group = snapshot.profiles[index].group ?? profile.group
                    snapshot.profiles[index] = profile
                }
                state = .loaded(snapshot)
            }
            lastDonation = donation
            completedActions += 1
            return true
        } catch {
            actionError = AppError(error)
            return false
        }
    }

    /// Parraine un groupe, ou change l'objectif du parrainage existant.
    @discardableResult
    func sponsor(groupId: String, monthlyBasketGoal: Int) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }
        do {
            let sponsorship = try await repository.sponsor(
                groupId: groupId, organizationId: organizationId, monthlyBasketGoal: monthlyBasketGoal
            )
            if var snapshot {
                if let index = snapshot.sponsorships.firstIndex(where: { $0.groupId == groupId }) {
                    snapshot.sponsorships[index] = sponsorship
                } else {
                    snapshot.sponsorships.append(sponsorship)
                }
                if let index = snapshot.profiles.firstIndex(where: { $0.groupId == groupId }),
                   !snapshot.profiles[index].sponsorOrganizationIds.contains(organizationId) {
                    snapshot.profiles[index].sponsorOrganizationIds.append(organizationId)
                }
                state = .loaded(snapshot)
            }
            completedActions += 1
            return true
        } catch {
            actionError = AppError(error)
            return false
        }
    }

    @discardableResult
    func endSponsorship(groupId: String) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }
        do {
            try await repository.endSponsorship(groupId: groupId, organizationId: organizationId)
            if var snapshot {
                snapshot.sponsorships.removeAll { $0.groupId == groupId }
                if let index = snapshot.profiles.firstIndex(where: { $0.groupId == groupId }) {
                    snapshot.profiles[index].sponsorOrganizationIds.removeAll { $0 == organizationId }
                }
                state = .loaded(snapshot)
            }
            return true
        } catch {
            actionError = AppError(error)
            return false
        }
    }

    /// Efface l'erreur et le remerciement avant d'ouvrir une nouvelle feuille.
    func resetAction() {
        actionError = nil
        lastDonation = nil
    }
}

/// T-208 : un lieu de la carte du portail Organismes : un groupe (avec son besoin) ou un organisme.
nonisolated struct OrganizationMapPlace: Identifiable, Sendable, Equatable {
    enum Detail: Sendable, Equatable {
        case group(GroupSolidarityProfile)
        case organization(OrganizationDirectoryEntry, isMine: Bool)
    }

    enum Kind: String, Sendable, CaseIterable, Identifiable {
        case group
        case organization

        var id: String { rawValue }
    }

    var detail: Detail
    var coordinate: Geohash.Coordinate

    var kind: Kind {
        if case .group = detail { .group } else { .organization }
    }

    /// « group:group-hochelaga », « organization:org-… » : unique entre les sortes.
    var id: String {
        switch detail {
        case .group(let profile): "group:\(profile.groupId)"
        case .organization(let entry, _): "organization:\(entry.id)"
        }
    }

    var name: String {
        switch detail {
        case .group(let profile): profile.groupName
        case .organization(let entry, _): entry.name
        }
    }

    var photoURL: URL? {
        switch detail {
        case .group(let profile): profile.group?.photoURL
        case .organization(let entry, _): entry.photoURL
        }
    }

    var isMine: Bool {
        if case .organization(_, true) = detail { true } else { false }
    }
}
