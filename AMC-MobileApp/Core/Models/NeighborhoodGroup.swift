// NeighborhoodGroup.swift
// Collection `groups` et sa sous-collection `groups/{id}/members`.
// Nommé NeighborhoodGroup pour éviter le conflit avec SwiftUI.Group.

import Foundation

nonisolated struct NeighborhoodGroup: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var name: String
    var neighborhood: String
    var centerGeohash: String
    var radiusMeters: Int
    var coordinatorIds: [String]
    var householdCount: Int
    var isPublic: Bool
    var inviteCode: String
}

/// Document `groups/{groupId}/members/{householdId}`.
nonisolated struct GroupMember: Identifiable, Codable, Sendable, Hashable {
    enum Role: String, Codable, Sendable, CaseIterable {
        case member
        case coordinator
    }

    var householdId: String
    var role: Role
    var joinedAt: Date

    var id: String { householdId }
}
