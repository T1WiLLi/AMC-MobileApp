import Foundation
import Testing
@testable import AMC_MobileApp

/// B-037 : sections réorganisables (ordre, masquage, Réinitialiser), persistées en une chaîne.
struct SectionLayoutTests {
    private let defaults = ["group", "savings", "orders", "offers"]

    @Test func emptyRawIsTheDefaultOrder() {
        let layout = SectionLayout(raw: "", defaults: defaults)
        #expect(layout.visible == defaults)
        #expect(layout.isDefault)
        #expect(layout.raw == "")
    }

    @Test func orderAndHiddenRoundTrip() {
        var layout = SectionLayout(raw: "", defaults: defaults)
        layout.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        layout.toggle("savings")
        let reread = SectionLayout(raw: layout.raw, defaults: defaults)
        #expect(reread.order == ["offers", "group", "savings", "orders"])
        #expect(reread.visible == ["offers", "group", "orders"])
    }

    @Test func unknownSectionsAreDroppedAndNewOnesAppended() {
        let layout = SectionLayout(raw: "orders,ancienne,group|ancienne", defaults: defaults)
        #expect(layout.order == ["orders", "group", "savings", "offers"])
        #expect(layout.hidden.isEmpty)
    }

    @Test func theLastVisibleSectionCannotBeHidden() {
        var layout = SectionLayout(raw: "|group,savings,orders", defaults: defaults)
        #expect(layout.visible == ["offers"])
        layout.toggle("offers")
        #expect(layout.visible == ["offers"])
        layout.toggle("group")
        #expect(layout.visible == ["group", "offers"])
    }

    @Test func shiftMovesOneStepAndStopsAtTheEdges() {
        var layout = SectionLayout(raw: "", defaults: defaults)
        layout.shift("group", by: -1)
        #expect(layout.order.first == "group")
        layout.shift("savings", by: -1)
        #expect(layout.order == ["savings", "group", "orders", "offers"])
        layout.shift("offers", by: 1)
        #expect(layout.order.last == "offers")
    }

    @Test func resetRestoresTheDefaults() {
        var layout = SectionLayout(raw: "offers,orders|group", defaults: defaults)
        #expect(!layout.isDefault)
        layout.reset()
        #expect(layout.isDefault)
        #expect(layout.raw == "")
    }

    @Test @MainActor func homeSectionsMatchTheirEditorInfos() {
        #expect(HomeSection.infos.map(\.id) == HomeSection.allCases.map(\.rawValue))
    }
}

/// B-037 (2/2) : sections du tableau vendeur.
struct DashboardSectionTests {
    @Test @MainActor func dashboardSectionsMatchTheirEditorInfos() {
        #expect(DashboardSection.infos.map(\.id) == DashboardSection.allCases.map(\.rawValue))
    }

    @Test func hidingTheStatsKeepsTheOtherSectionsInOrder() {
        var layout = SectionLayout(raw: "", defaults: DashboardSection.allCases.map(\.rawValue))
        layout.toggle(DashboardSection.stats.rawValue)
        #expect(layout.visible == ["highlight", "closingSoon", "offers"])
    }
}
