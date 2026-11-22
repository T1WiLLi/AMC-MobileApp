import Testing
@testable import AMC_MobileApp

/// T-181 : mode aîné partout dans l'app (Accueil simplifié, langage simple, 2 taps pour l'activer).
@MainActor
struct SeniorModeAppWideTests {
    @Test func homeKeepsOnlyOrdersAndGroupInSeniorMode() {
        let chosen = HomeSection.allCases
        #expect(SeniorMode.visibleHomeSections(chosen, isSenior: true) == [.orders, .group])
        #expect(SeniorMode.visibleHomeSections(chosen, isSenior: false) == chosen)
    }

    @Test func seniorHomeIgnoresHiddenOrReorderedSections() {
        // Même si la personne avait masqué « Mon groupe » avant, le mode aîné montre l'essentiel.
        #expect(SeniorMode.visibleHomeSections([.offers], isSenior: true) == [.orders, .group])
    }

    @Test func plainTitlesUseSimpleWords() {
        #expect(SeniorMode.plainTitle(for: .orders) == "Ma commande")
        #expect(SeniorMode.plainTitle(for: .group) == "Mon groupe")
        #expect(SeniorMode.plainTitle(for: .offers) == nil)
    }

    @Test func enablingTakesTwoTapsFromAnyTab() {
        // Bouton Profil, puis l'interrupteur « Mode aîné » (SeniorModeToggleRow dans le Profil).
        #expect(SeniorMode.tapsToEnable <= 2)
    }

    @Test func tapTargetsAreComfortable() {
        #expect(SeniorMode.minRowHeight >= 44)
    }
}
