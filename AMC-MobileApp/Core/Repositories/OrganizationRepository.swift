// OrganizationRepository.swift
// Contrat du portail Organismes (T-116, RQ-081) : organisme, besoins des groupes, financements et parrainages.
// Deux implémentations : `FakeOrganizationRepository` (mémoire) et `FirestoreOrganizationRepository`.
// Toutes les erreurs levées sont des `AppError`. Paiements simulés : aucun argent réel.

import Foundation

nonisolated protocol OrganizationRepository: Sendable {
    /// Lève `.notFound` si l'organisme n'existe pas.
    func organization(id: String) async throws -> Organization
    /// Groupes publics avec leur fonds de solidarité et leur besoin anonyme, par nom.
    func solidarityProfiles() async throws -> [GroupSolidarityProfile]
    /// T-208 : fonds et besoin de ces groupes (ceux de la recherche de groupes du portail Famille), dans le même
    /// ordre. Un groupe sans fonds a un profil vide (aucun ménage subventionné, prix de panier par défaut).
    func solidarityProfiles(of groups: [NeighborhoodGroup]) async throws -> [GroupSolidarityProfile]
    /// Lève `.notFound` si le groupe n'existe pas.
    func solidarityProfile(groupId: String) async throws -> GroupSolidarityProfile
    /// T-208 : fiches publiques de tous les organismes (carte du portail), par nom.
    func directory() async throws -> [OrganizationDirectoryEntry]
    /// Financements de l'organisme, du plus récent au plus ancien.
    func donations(ofOrganization organizationId: String) async throws -> [OrganizationDonation]
    /// Parrainages de l'organisme, du plus ancien au plus récent.
    func sponsorships(ofOrganization organizationId: String) async throws -> [Sponsorship]
    /// Finance le fonds de solidarité du groupe (don ou paniers suspendus), en une transaction :
    /// contribution ajoutée au fonds + trace du don. Lève `.invalidInput` (montant), `.notFound` (groupe, organisme).
    @discardableResult
    func donate(_ request: DonationRequest, toGroup groupId: String, organizationId: String) async throws -> OrganizationDonation
    /// Parraine le groupe (ou change l'objectif d'un parrainage existant). Lève `.invalidInput` si l'objectif ≤ 0.
    @discardableResult
    func sponsor(groupId: String, organizationId: String, monthlyBasketGoal: Int) async throws -> Sponsorship
    /// Met fin au parrainage ; sans effet s'il n'existe pas.
    func endSponsorship(groupId: String, organizationId: String) async throws
}
