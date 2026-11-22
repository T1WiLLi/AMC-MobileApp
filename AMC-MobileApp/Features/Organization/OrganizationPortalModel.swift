// OrganizationPortalModel.swift
// ViewModel partagé par les onglets du portail Organismes (T-116, RQ-081) : Tableau, Financer, Parrainages,
// Impact et Recherche. Un seul modèle pour que chaque financement ou parrainage se voie partout tout de suite.
//
// Usage :
//   @State private var model = OrganizationPortalModel(repository: context.repositories.organizations,
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
    let organizationId: String

    init(repository: any OrganizationRepository, organizationId: String) {
        self.repository = repository
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
            async let profiles = repository.solidarityProfiles()
            async let donations = repository.donations(ofOrganization: organizationId)
            async let sponsorships = repository.sponsorships(ofOrganization: organizationId)
            state = .loaded(Snapshot(
                organization: try await organization,
                profiles: try await profiles,
                donations: try await donations,
                sponsorships: try await sponsorships
            ))
        } catch {
            // Un rafraîchissement raté garde l'écran déjà chargé.
            if snapshot == nil { state = .failed(AppError(error)) }
        }
    }

    // MARK: Lectures dérivées

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

    var sponsorableGroups: [GroupSolidarityProfile] {
        prioritizedGroups.filter { !$0.isSponsored(by: organizationId) }
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
        guard !query.isEmpty else { return prioritizedGroups }
        return prioritizedGroups.filter {
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
        guard let origin = snapshot?.organization.geohash,
              let meters = OrganizationLedger.distanceMeters(from: origin, to: profile) else { return nil }
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
                if let profile, let index = snapshot.profiles.firstIndex(where: { $0.groupId == groupId }) {
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
