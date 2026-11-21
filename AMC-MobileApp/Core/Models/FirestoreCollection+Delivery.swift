// FirestoreCollection+Delivery.swift
// Collections de la livraison à domicile par un voisin bénévole (RQ-069, T-117).
//
//   groupOrders/{orderId}/deliveries/{requestId}                  → VolunteerDelivery.Request (sans adresse)
//   groupOrders/{orderId}/deliveries/{requestId}/private/address  → VolunteerDelivery.PrivateAddress
//
// L'adresse vit dans une sous-collection à part : firestore.rules ne la laisse lire qu'au ménage et au
// bénévole qui a pris la livraison, alors que la demande est lisible par tout le groupe.

import Foundation

nonisolated extension FirestoreCollection {
    static let deliveries = "deliveries"

    static func deliveries(ofGroupOrder groupOrderId: String) -> String { "groupOrders/\(groupOrderId)/deliveries" }

    static func deliveryPrivate(groupOrderId: String, requestId: String) -> String {
        "groupOrders/\(groupOrderId)/deliveries/\(requestId)/private"
    }

    /// Id du seul document de `deliveries/{id}/private`.
    static let deliveryAddressDocumentId = "address"
}
