// VolunteerDeliveryRepository.swift
// Contrat des livraisons à domicile par un voisin bénévole (RQ-069, T-117).
// Les règles métier sont dans `VolunteerDelivery` (Core/Domain) ; le dépôt les applique sur la donnée
// fraîche, en transaction quand deux voisins peuvent se disputer la même livraison.
// Deux implémentations : `FakeVolunteerDeliveryRepository` et `FirestoreVolunteerDeliveryRepository`.

import Foundation

nonisolated protocol VolunteerDeliveryRepository: Sendable {
    /// Toutes les demandes du groupe (membres du groupe seulement), sans aucune adresse.
    func deliveries(ofGroup groupId: String) async throws -> [VolunteerDelivery.Request]

    /// Enregistre une demande déjà validée par `VolunteerDelivery.request(_:existing:now:)` et son adresse privée.
    /// Lève `.invalidInput` si le ménage a déjà une demande en cours pour cette commande.
    @discardableResult
    func createDelivery(
        _ request: VolunteerDelivery.Request, address: VolunteerDelivery.PrivateAddress
    ) async throws -> VolunteerDelivery.Request

    /// Un voisin prend la livraison. En transaction : si un autre voisin l'a prise entre-temps,
    /// lève `.invalidInput("Un autre voisin a déjà pris cette livraison.")`.
    @discardableResult
    func claimDelivery(
        id: String, groupOrderId: String, volunteerHouseholdId: String, volunteerName: String,
        volunteerGroupIds: Set<String>
    ) async throws -> VolunteerDelivery.Request

    /// Le bénévole se désiste : la demande redevient ouverte.
    @discardableResult
    func releaseDelivery(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request

    /// Le bénévole a récupéré la part chez l'hôte : la demande passe « en route » et la part est marquée cueillie.
    @discardableResult
    func startRoute(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request

    /// Le bénévole a remis la part.
    @discardableResult
    func markDelivered(id: String, groupOrderId: String, volunteerHouseholdId: String) async throws
        -> VolunteerDelivery.Request

    /// Le ménage confirme la réception.
    @discardableResult
    func confirmReceipt(id: String, groupOrderId: String, householdId: String) async throws
        -> VolunteerDelivery.Request

    /// Le ménage annule (tant que la part n'a pas quitté l'hôte).
    @discardableResult
    func cancelDelivery(id: String, groupOrderId: String, householdId: String) async throws
        -> VolunteerDelivery.Request

    /// Adresse exacte si `viewerHouseholdId` a le droit de la voir (`VolunteerDelivery.canSeeAddress`), sinon nil.
    func address(ofDelivery id: String, groupOrderId: String, viewerHouseholdId: String) async throws
        -> VolunteerDelivery.PrivateAddress?
}
