import Foundation
import Testing
@testable import AMC_MobileApp

/// Fixtures des groupes, points de cueillette et personas (B-027, B-029, T-048) :
/// elles doivent se décoder avec les modèles Swift et rester cohérentes entre elles.
struct SeedGroupsFixtureTests {
    private static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Seed/
        .deletingLastPathComponent()  // AMC-MobileAppTests/
        .deletingLastPathComponent()  // racine du repo
        .appending(path: "scripts/seed/fixtures")

    private static let groupIds: Set<String> = [
        "group-parc-extension", "group-rosemont", "group-hochelaga", "group-saint-michel",
        "group-verdun", "group-cote-des-neiges", "group-montreal-nord", "group-villeray",
    ]

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appending(path: "\(name).json"))
    }

    private func raw(_ name: String) throws -> [[String: Any]] {
        try #require(try JSONSerialization.jsonObject(with: data(name)) as? [[String: Any]])
    }

    private func groups() throws -> [NeighborhoodGroup] {
        try JSONDecoder().decode([NeighborhoodGroup].self, from: data("groups"))
    }

    private func users() throws -> [AppUser] { try JSONDecoder().decode([AppUser].self, from: data("users")) }
    private func vendors() throws -> [Vendor] { try JSONDecoder().decode([Vendor].self, from: data("vendors")) }

    /// `slotTemplates` est converti en `slots` par le script ; on fait pareil ici.
    private func pickupPoints() throws -> [PickupPoint] {
        let midnight = Calendar.current.startOfDay(for: .now)
        func date(_ days: Int, _ time: String) throws -> Double {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            try #require(parts.count == 2, "heure invalide : \(time)")
            let seconds = Double(days * 86_400 + parts[0] * 3_600 + parts[1] * 60)
            return midnight.timeIntervalSinceReferenceDate + seconds
        }
        let converted: [[String: Any]] = try raw("pickupPoints").map { point in
            var point = point
            let templates = try #require(point.removeValue(forKey: "slotTemplates") as? [[String: Any]])
            point["slots"] = try templates.map { template in
                let days = try #require(template["inDays"] as? Int)
                let start = try #require(template["start"] as? String)
                let end = try #require(template["end"] as? String)
                return ["start": try date(days, start), "end": try date(days, end)]
            }
            return point
        }
        return try JSONDecoder().decode([PickupPoint].self, from: JSONSerialization.data(withJSONObject: converted))
    }

    @Test func eightPublicGroupsWithFixedIds() throws {
        let groups = try groups()
        #expect(groups.count == 8)
        #expect(Set(groups.map(\.id)) == Self.groupIds)
        #expect(groups.allSatisfy { $0.isPublic })
        #expect(groups.allSatisfy { $0.id == "group-\($0.neighborhood)" })
        #expect(groups.allSatisfy { $0.centerGeohash.count == 6 && $0.centerGeohash.hasPrefix("f25") })
    }

    @Test func idsAreUnique() throws {
        let points = try pickupPoints()
        let users = try users()
        #expect(Set(points.map(\.id)).count == points.count)
        #expect(Set(users.map(\.id)).count == users.count)
        #expect(Set(try groups().map(\.inviteCode)).count == 8)
    }

    @Test func householdCountsMatchB028() throws {
        let counts = Dictionary(uniqueKeysWithValues: try groups().map { ($0.id, $0.householdCount) })
        #expect(counts.values.reduce(0, +) == 60)
        #expect(counts["group-parc-extension"] == 10)
        #expect(counts["group-rosemont"] == 8)
        #expect(counts.filter { $0.value == 7 }.count == 6)
    }

    @Test func everyGroupHasAnExistingPickupPoint() throws {
        let points = Dictionary(uniqueKeysWithValues: try pickupPoints().map { ($0.id, $0) })
        for group in try raw("groups") {
            let id = try #require(group["id"] as? String)
            let pointIds = try #require(group["pickupPointIds"] as? [String], "\(id)")
            #expect(!pointIds.isEmpty, "\(id)")
            #expect(pointIds.allSatisfy { points[$0] != nil }, "\(id)")
        }
        for point in try raw("pickupPoints") {
            #expect(Self.groupIds.contains(point["groupId"] as? String ?? ""), "\(point["id"] ?? "?")")
        }
    }

    @Test func pickupPointsHaveSlotsAndExistingHosts() throws {
        let userIds = Set(try users().map(\.id))
        for point in try pickupPoints() {
            #expect(point.id.hasPrefix("pickup-"), "\(point.id)")
            #expect(userIds.contains(point.hostUserId), "\(point.id) : hôte inconnu")
            #expect(!point.slots.isEmpty, "\(point.id)")
            #expect(point.slots.allSatisfy { $0.start < $0.end && $0.end > .now }, "\(point.id)")
            #expect(point.capacity > 0, "\(point.id)")
        }
    }

    @Test func jeanHostsParcExtension() throws {
        let point = try #require(try pickupPoints().first { $0.id == "pickup-parc-extension-1" })
        #expect(point.hostUserId == "user-jean")
        let jean = try #require(try users().first { $0.id == "user-jean" })
        #expect(jean.roles.contains(.host))
        #expect(jean.neighborhood == "parc-extension")
        #expect(jean.householdId == "household-jean")
    }

    @Test func demoPersonasAreConsistent() throws {
        let users = Dictionary(uniqueKeysWithValues: try users().map { ($0.id, $0) })
        let amina = try #require(users["user-amina"])
        #expect(amina.roles == [.family])
        #expect(amina.language == .french)
        #expect(amina.neighborhood == "parc-extension")
        #expect(amina.householdId == "household-amina")
        #expect(amina.dietaryPreferences.contains(.halal))

        let lafleur = try #require(users["user-ferme-lafleur"])
        #expect(lafleur.roles == [.vendor])
        let vendorId = try #require(lafleur.vendorId)
        #expect(Set(try vendors().map(\.id)).contains(vendorId))

        // Ménages fournis par B-028 : household-amina, household-jean, household-001…058.
        let householdIds = users.values.compactMap(\.householdId)
        #expect(householdIds.allSatisfy { ["household-amina", "household-jean"].contains($0) || $0.hasPrefix("household-0") })
    }
}
