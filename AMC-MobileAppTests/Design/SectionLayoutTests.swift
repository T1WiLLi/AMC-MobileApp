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

    @Test func editingShowsHiddenSectionsInOrderWhileViewingDoesNot() {
        let layout = SectionLayout(raw: "offers,group,savings,orders|group", defaults: defaults)
        #expect(layout.displayed(isEditing: true) == ["offers", "group", "savings", "orders"])
        #expect(layout.displayed(isEditing: false) == ["offers", "savings", "orders"])
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

/// Mode édition de la mise en page : vue isométrique, identique pour chaque section, jamais sous Reduce Motion.
struct IsoLayoutStyleTests {
    @Test @MainActor func everySectionGetsTheSameAngleWhileEditing() {
        #expect(IsoLayoutStyle.angle(isActive: true, reduceMotion: false) > 0)
        #expect(IsoLayoutStyle.scale(isActive: true, reduceMotion: false) < 1)
        #expect(IsoLayoutStyle.angle(isActive: false, reduceMotion: false) == 0)
        #expect(IsoLayoutStyle.scale(isActive: false, reduceMotion: false) == 1)
    }

    @Test @MainActor func reduceMotionKeepsTheSectionsFlat() {
        #expect(IsoLayoutStyle.angle(isActive: true, reduceMotion: true) == 0)
        #expect(IsoLayoutStyle.scale(isActive: true, reduceMotion: true) == 1)
    }

    @Test @MainActor func hiddenSectionsAreDimmedOnlyWhileEditing() {
        #expect(IsoLayoutStyle.opacity(isActive: true, isDimmed: true) < 0.6)
        #expect(IsoLayoutStyle.opacity(isActive: true, isDimmed: false) == 1)
        #expect(IsoLayoutStyle.opacity(isActive: false, isDimmed: true) == 1)
    }

    @Test @MainActor func panelWidthIsNarrowerOnIPad() {
        #expect(LayoutEditorPanel.width(in: 393, isRegular: false) == 393 * 0.72)
        #expect(LayoutEditorPanel.width(in: 1024, isRegular: true) <= 400)
    }

    @Test @MainActor func swipeLeftBeyondTheThresholdCloses() {
        #expect(LayoutEditorPanel.shouldClose(translation: -90, predictedEnd: -120))
        #expect(!LayoutEditorPanel.shouldClose(translation: -10, predictedEnd: -20))
        #expect(!LayoutEditorPanel.shouldClose(translation: 80, predictedEnd: 200))
    }
}
