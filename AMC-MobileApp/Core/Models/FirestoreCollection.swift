// FirestoreCollection.swift
// Noms des collections Firestore de Grenier (onglet Requis, « Modèle de données »).

import Foundation

/// Chemins des collections. Les sous-collections prennent l'id du document parent.
nonisolated enum FirestoreCollection {
    static let users = "users"
    static let households = "households"
    static let groups = "groups"
    static let vendors = "vendors"
    static let products = "products"
    static let offers = "offers"
    static let groupOrders = "groupOrders"
    static let pickupPoints = "pickupPoints"
    /// B-056 : invitations à usage unique des groupes privés (`groupInvitations/{code}`).
    static let groupInvitations = "groupInvitations"
    /// T-157 : avis des familles sur les producteurs (`vendorReviews/{vendorId}_{householdId}`).
    static let vendorReviews = "vendorReviews"

    /// T-159 : index d'adresse des ménages (`householdAddresses/{lookupId}`), lu par id exact seulement.
    static let householdAddresses = "householdAddresses"

    /// T-159 : demandes pour rejoindre un ménage (`households/{id}/joinRequests/{uid}`).
    static func joinRequests(ofHousehold householdId: String) -> String { "households/\(householdId)/joinRequests" }
    static func householdPrivate(_ householdId: String) -> String { "households/\(householdId)/private" }
    static func members(ofGroup groupId: String) -> String { "groups/\(groupId)/members" }
    static func shares(ofGroupOrder groupOrderId: String) -> String { "groupOrders/\(groupOrderId)/shares" }

    /// Id du seul document de `households/{id}/private`.
    static let householdPrivateDocumentId = "profile"
}
