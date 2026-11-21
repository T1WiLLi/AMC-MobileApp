// FirestoreCollection+Matching.swift
// Chemins des sous-collections des envies (S-07) et des disponibilités (S-08).

import Foundation

nonisolated extension FirestoreCollection {
    /// Nom des sous-collections, pour les requêtes `collectionGroup` (tous groupes, tous vendeurs).
    static let wishes = "wishes"
    static let supplies = "supplies"

    static func wishes(ofGroup groupId: String) -> String { "groups/\(groupId)/wishes" }
    static func supplies(ofVendor vendorId: String) -> String { "vendors/\(vendorId)/supplies" }
}
