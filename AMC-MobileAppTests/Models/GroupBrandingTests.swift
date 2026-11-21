import Foundation
import Testing
@testable import AMC_MobileApp

/// Marque d'un groupe sur `groups/{id}.branding` (B-033).
struct GroupBrandingTests {
    private static let base = #""id":"g1","name":"Voisins de Jarry","neighborhood":"Villeray","centerGeohash":"f25dv","radiusMeters":800,"coordinatorIds":[],"householdCount":3,"isPublic":true,"inviteCode":"VJ-1""#

    private static func group(branding: String? = nil) throws -> NeighborhoodGroup {
        let json = "{" + base + (branding.map { #","branding":"# + $0 } ?? "") + "}"
        return try JSONDecoder().decode(NeighborhoodGroup.self, from: Data(json.utf8))
    }

    @Test func missingBrandingGivesTheDefaultBrand() throws {
        let group = try Self.group()
        #expect(group.branding == nil)
        let resolved = group.resolvedBranding
        #expect(resolved.displayName == "Voisins de Jarry")
        #expect(resolved.emblem == GroupBranding.defaultEmblem)
        #expect(resolved.welcomeMessage == "Bienvenue chez Voisins de Jarry")
        #expect(resolved.accent == nil)
        #expect(!resolved.hasCustomAccent)
    }

    @Test func decodesACompleteBranding() throws {
        let group = try Self.group(branding: ##"{"displayName":"Jarry ensemble","emblem":"leaf.fill","accentLight":"1e6b52","accentDark":"#5FC9A0","welcomeMessage":"Salut voisin !"}"##)
        #expect(group.branding == GroupBranding(displayName: "Jarry ensemble", emblem: "leaf.fill",
                                                accentLight: "#1E6B52", accentDark: "#5FC9A0",
                                                welcomeMessage: "Salut voisin !"))
        let resolved = group.resolvedBranding
        #expect(resolved.displayName == "Jarry ensemble")
        #expect(resolved.welcomeMessage == "Salut voisin !")
        #expect(resolved.hasCustomAccent)
        #expect(resolved.accent != nil)
    }

    @Test func badFieldsFallBackOneByOne() throws {
        let group = try Self.group(branding: ##"{"displayName":"  ","emblem":42,"accentLight":"vert","welcomeMessage":"Allo"}"##)
        let resolved = group.resolvedBranding
        #expect(resolved.displayName == "Voisins de Jarry")
        #expect(resolved.emblem == GroupBranding.defaultEmblem)
        #expect(resolved.branding.accentLight == nil)
        #expect(resolved.welcomeMessage == "Allo")
    }

    @Test(arguments: [#""rouge""#, "[1, 2]", "12", "null"])
    func brandingOfTheWrongTypeNeverBreaksTheGroup(_ branding: String) throws {
        let group = try Self.group(branding: branding)
        #expect(group.name == "Voisins de Jarry")
        #expect(group.resolvedBranding.emblem == GroupBranding.defaultEmblem)
    }

    @Test func roundTripsThroughJSON() throws {
        var group = try Self.group()
        group.branding = GroupBranding(emblem: "sun.max.fill", accentLight: "#9A5B00")
        let decoded = try JSONDecoder().decode(NeighborhoodGroup.self, from: JSONEncoder().encode(group))
        #expect(decoded == group)
    }

    @Test func fakeDataHasAtLeastTwoBrandedGroups() async throws {
        let groups = try await AppRepositories.fake(behavior: .instant).groups.groups(inNeighborhood: nil)
        #expect(groups.filter { $0.branding?.accentLight != nil }.count >= 2)
        let saintMichel = try #require(groups.first { $0.id == FakeData.ID.saintMichel })
        #expect(saintMichel.resolvedBranding.displayName == "Saint-Michel en commun")
    }
}
