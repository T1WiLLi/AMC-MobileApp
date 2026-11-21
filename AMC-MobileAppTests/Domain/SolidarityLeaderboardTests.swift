import Foundation
import Testing
@testable import AMC_MobileApp

/// RQ-093 (T-114) : classement solidaire des arrondissements.
struct SolidarityLeaderboardTests {
    private func borough(
        _ id: String, households: Int, active: Int = 0, baskets: Int = 0, helped: Int = 0, savings: Cents = 0,
        neighborhoods: [String] = []
    ) -> BoroughStats {
        BoroughStats(id: id, name: id.capitalized, shortName: id.capitalized, neighborhoods: neighborhoods,
                     centerGeohash: "f25d", households: households, activeHouseholds: active, groupCount: 1,
                     basketsOffered: baskets, familiesHelped: helped, savingsCents: savings)
    }

    @Test func weightsSumToOne() {
        let total = SolidarityLeaderboard.Metric.allCases.reduce(0.0) { $0 + $1.weight }
        #expect(abs(total - 1) < 1e-9)
    }

    @Test func emptyAndHouseholdlessBoroughsAreNotRanked() {
        #expect(SolidarityLeaderboard.ranking([]).isEmpty)
        let entries = SolidarityLeaderboard.ranking([borough("vide", households: 0, baskets: 50), borough("a", households: 10)])
        #expect(entries.map(\.id) == ["a"])
    }

    /// Même total de paniers : le petit arrondissement gagne, car tout est rapporté au ménage.
    @Test func smallBoroughCanBeatBigOneWithSameTotals() {
        let small = borough("petit", households: 60, active: 45, baskets: 60, helped: 30, savings: 600_000)
        let big = borough("grand", households: 600, active: 300, baskets: 60, helped: 30, savings: 600_000)
        let entries = SolidarityLeaderboard.ranking([big, small])
        #expect(entries.first?.id == "petit")
        #expect(entries.first?.rank == 1)
        #expect(entries.last?.rank == 2)
    }

    /// Lissage : 2 ménages qui offrent 4 paniers ne passent pas devant un arrondissement constant de 200 ménages.
    @Test func smoothingTamesTinyOutliers() {
        let tiny = borough("minuscule", households: 2, active: 2, baskets: 4, helped: 2, savings: 20_000)
        let steady = borough("constant", households: 200, active: 170, baskets: 300, helped: 150, savings: 2_400_000)
        let average = borough("moyen", households: 300, active: 120, baskets: 90, helped: 40, savings: 2_000_000)
        let entries = SolidarityLeaderboard.ranking([tiny, steady, average])
        #expect(entries.first?.id == "constant")
    }

    @Test func scoresAreBetweenZeroAndHundredAndLeaderIsNormalized() {
        let entries = SolidarityLeaderboard.ranking(FakeData.montrealBoroughs)
        #expect(entries.count == FakeData.montrealBoroughs.count)
        #expect(entries.allSatisfy { (0...100).contains($0.score) })
        for metric in SolidarityLeaderboard.Metric.allCases {
            #expect(entries.contains { ($0.normalized[metric] ?? 0) >= 0.999 })
            #expect(entries.allSatisfy { ($0.normalized[metric] ?? 0) <= 1 })
        }
        // Trié par score décroissant.
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.score >= $1.score })
    }

    @Test func tiesShareTheSameRank() {
        let first = borough("a", households: 50, active: 25, baskets: 10, helped: 5, savings: 100_000)
        var twin = first
        twin.id = "b"
        twin.name = "B"
        let weaker = borough("c", households: 50, active: 5, baskets: 1, helped: 0, savings: 10_000)
        let entries = SolidarityLeaderboard.ranking([weaker, twin, first])
        #expect(entries.map(\.rank) == [1, 1, 3])
        #expect(entries[0].pointsToNextRank == nil && entries[1].pointsToNextRank == nil)
        #expect((entries[2].pointsToNextRank ?? 0) > 0)
    }

    @Test func singleMetricRankingFollowsThatMetric() {
        let generous = borough("genereux", households: 100, active: 10, baskets: 80, helped: 10, savings: 50_000)
        let mobilized = borough("mobilise", households: 100, active: 95, baskets: 5, helped: 10, savings: 50_000)
        #expect(SolidarityLeaderboard.ranking([generous, mobilized], metric: .baskets).first?.id == "genereux")
        #expect(SolidarityLeaderboard.ranking([generous, mobilized], metric: .participation).first?.id == "mobilise")
        let byBaskets = SolidarityLeaderboard.ranking([generous, mobilized], metric: .baskets)
        #expect(byBaskets.first?.score == 100)
        #expect(byBaskets.first?.championOf.contains(.baskets) == true)
        #expect(byBaskets.first?.strength == .baskets)
    }

    @Test func homeBoroughMatchesNeighborhoodIgnoringCaseAndAccents() {
        let vsp = borough("vsp", households: 100, neighborhoods: ["Villeray", "Saint-Michel", "Parc-Extension"])
        let hochelaga = borough("hm", households: 100, neighborhoods: ["Hochelaga"])
        let entries = SolidarityLeaderboard.ranking([vsp, hochelaga], homeNeighborhood: "saint michel")
        #expect(entries.filter(\.isHome).map(\.id) == ["vsp"])
        #expect(SolidarityLeaderboard.ranking([vsp], homeNeighborhood: nil).allSatisfy { !$0.isHome })
        let accented = borough("cdn", households: 10, neighborhoods: ["Côte-des-Neiges"])
        #expect(SolidarityLeaderboard.ranking([accented], homeNeighborhood: "Cote-des-Neiges").first?.isHome == true)
    }

    @Test func participationNeverExceedsHouseholds() {
        let odd = borough("bizarre", households: 10, active: 50)
        #expect(SolidarityLeaderboard.rawValue(.participation, of: odd) == 10)
        let negative = borough("negatif", households: 10, baskets: -4)
        #expect(SolidarityLeaderboard.rawValue(.baskets, of: negative) == 0)
    }

    @Test func cheerIsAlwaysPositive() {
        let entries = SolidarityLeaderboard.ranking(FakeData.montrealBoroughs, homeNeighborhood: "Saint-Michel")
        #expect(SolidarityLeaderboard.cheer(for: entries[0]).contains("bravo"))
        for entry in entries {
            let text = SolidarityLeaderboard.cheer(for: entry).lowercased()
            #expect(!text.contains("dernier"))
            #expect(!text.isEmpty)
        }
        #expect(entries.contains(where: \.isHome))
    }

    /// Le jeu de démo met un petit arrondissement (Lachine, 64 ménages) dans le haut du classement.
    @Test func demoDataShowsASmallBoroughNearTheTop() {
        let entries = SolidarityLeaderboard.ranking(FakeData.montrealBoroughs)
        let lachine = entries.first { $0.id == "lachine" }
        #expect((lachine?.rank ?? 99) <= 5)
    }

    @Test func fakeRepositoryReturnsStats() async throws {
        let repository = FakeBoroughStatsRepository(stats: FakeData.montrealBoroughs)
        #expect(try await repository.boroughStats().count == FakeData.montrealBoroughs.count)
        let failing = FakeBoroughStatsRepository(behavior: .failing(), stats: FakeData.montrealBoroughs)
        await #expect(throws: AppError.offline) { try await failing.boroughStats() }
    }

    @MainActor
    @Test func viewModelHighlightsHomeAndSwitchesMetric() async {
        let model = SolidarityLeaderboardViewModel(repositories: .fake(behavior: .instant), groupId: FakeData.ID.saintMichel)
        await model.load()
        #expect(model.home?.stats.id == "villeray-saint-michel-parc-extension")
        let overall = model.entries.map(\.id)
        model.metric = .participation
        #expect(model.entries.first?.score == 100)
        #expect(model.entries.map(\.id) != overall || model.entries.count < 2)
    }

    @MainActor
    @Test func viewModelIsEmptyWithoutStats() async {
        var repositories = AppRepositories.fake(behavior: .instant)
        repositories.boroughStats = FakeBoroughStatsRepository()
        let model = SolidarityLeaderboardViewModel(repositories: repositories, groupId: nil)
        await model.load()
        #expect(model.state == .empty)
    }
}
