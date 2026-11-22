import Foundation
import Testing
@testable import AMC_MobileApp

/// Visites guidées (FB-19) : Noisette (Familles) et Racoonette (Vendeurs). Étapes de chaque visite, machine à états
/// (suivant, précédent, passer, rejouer), persistance séparée par visite, activation en tests et en démo.
@MainActor
struct GuidedTourTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GuidedTourTests-\(UUID().uuidString)")!
    }

    private func makeStore(_ defaults: UserDefaults? = nil) -> GuidedTourStore {
        GuidedTourStore(defaults: defaults ?? makeDefaults())
    }

    private func makeTour(_ tour: TourID = .noisette, _ defaults: UserDefaults? = nil, enabled: Bool = true) -> GuidedTour {
        GuidedTour(tour: tour, store: makeStore(defaults), isEnabled: enabled)
    }

    // MARK: Étapes

    @Test func noisetteStepsFollowTheTourOrder() {
        #expect(TourID.noisette.steps == [
            .intro, .homeGroup, .homeSavings, .homeOrders, .homeOffers, .offerTiers, .offerShare,
            .groups, .groupsActions, .pickup, .impact, .profile
        ])
        #expect(GuidedTourMachine().steps == TourID.noisette.steps)
    }

    @Test func racoonetteStepsFollowTheTourOrder() {
        #expect(TourID.racoonette.steps == [
            .vendorIntro, .vendorStats, .vendorRisk, .vendorShop, .vendorCreate, .vendorTiers,
            .vendorProducts, .vendorDemand, .vendorRevenue, .vendorProfile
        ])
        #expect(GuidedTourMachine(tour: .racoonette).steps == TourID.racoonette.steps)
    }

    @Test func everyStepBelongsToExactlyOneTourAndTheToursPartitionTheSteps() {
        let all = TourID.allCases.flatMap(\.steps)
        #expect(all.count == TourStep.allCases.count)
        #expect(Set(all) == Set(TourStep.allCases))
        for tour in TourID.allCases {
            #expect(tour.steps.allSatisfy { $0.tour == tour })
            #expect((8...12).contains(tour.steps.count))
        }
    }

    @Test func familyScreensMapToFamilyTabsAndVendorScreensToVendorTabs() {
        let family: [TourScreen] = [.home, .offerDetail, .groups, .pickup, .impact]
        #expect(family.map(FamilyTabView.tab(for:)) == [.home, .home, .groups, .pickup, .impact])
        let vendor: [TourScreen] = [.vendorDashboard, .vendorOffers, .vendorTierEditor, .vendorDemand, .vendorRevenue]
        #expect(vendor.map(VendorTabView.tab(for:)) == [.dashboard, .offers, .offers, .demand, .revenue])
        // Chaque écran de chaque visite est montré par au moins une étape de sa visite.
        for screen in family { #expect(TourID.noisette.steps.contains { $0.screen == screen }) }
        for screen in vendor { #expect(TourID.racoonette.steps.contains { $0.screen == screen }) }
    }

    @Test func pushedScreensAreFlaggedAndOnlyPushedInsideTheirTab() {
        #expect(TourScreen.allCases.filter(\.isPushed) == [.offerDetail, .vendorTierEditor])
        #expect(TourStep.offerTiers.screen.isPushed && TourStep.offerShare.screen.isPushed)
        #expect(TourStep.vendorTiers.screen.isPushed)
    }

    @Test func introAndFormStepsHaveNoElementAndOthersExpectOne() {
        #expect(TourStep.allCases.filter { !$0.expectsAnchor } == [.intro, .vendorIntro, .vendorTiers])
        // Les boutons de la barre d'outils ont une place connue : SwiftUI ne donne pas leur cadre.
        #expect(TourStep.allCases.filter { $0.toolbarSlot != nil } == [
            .groupsActions, .profile, .vendorShop, .vendorCreate, .vendorProducts, .vendorProfile
        ])
        // Un remplaçant existe pour les éléments qui peuvent manquer, dans la même visite.
        for step in TourStep.allCases {
            if let fallback = step.fallback { #expect(fallback.tour == step.tour) }
        }
    }

    // MARK: Machine à états

    @Test func startsOnTheWelcomeCard() {
        let machine = GuidedTourMachine()
        #expect(machine.phase == .welcome)
        #expect(machine.currentStep == nil)
        #expect(!machine.isTouring)
    }

    @Test(arguments: TourID.allCases)
    func nextWalksEveryStepThenFinishes(tour: TourID) {
        var machine = GuidedTourMachine(tour: tour)
        machine.start()
        var seen: [TourStep] = []
        while let step = machine.currentStep {
            seen.append(step)
            machine.next()
        }
        #expect(seen == tour.steps)
        #expect(machine.phase == .finished)
        #expect(machine.isDone)
        // Plus rien ne bouge une fois terminée.
        machine.next()
        machine.back()
        #expect(machine.phase == .finished)
    }

    @Test func backGoesToThePreviousStepAndStopsAtTheFirst() {
        var machine = GuidedTourMachine()
        machine.start()
        #expect(machine.isFirstStep)
        machine.back()
        #expect(machine.phase == .touring(index: 0))
        machine.next()
        machine.next()
        #expect(machine.currentStep == .homeSavings)
        machine.back()
        #expect(machine.currentStep == .homeGroup)
    }

    @Test(arguments: TourID.allCases)
    func lastStepIsFlagged(tour: TourID) {
        var machine = GuidedTourMachine(tour: tour, phase: .touring(index: tour.steps.count - 1))
        #expect(machine.isLastStep)
        #expect(machine.currentStep == tour.steps.last)
        machine.next()
        #expect(machine.phase == .finished)
    }

    @Test(arguments: TourID.allCases)
    func skipStopsTheTourFromAnyStep(tour: TourID) {
        for index in tour.steps.indices {
            var machine = GuidedTourMachine(tour: tour, phase: .touring(index: index))
            machine.skip()
            #expect(machine.phase == .skipped)
            #expect(machine.currentStep == nil)
        }
        var fromWelcome = GuidedTourMachine(tour: tour)
        fromWelcome.skip()
        #expect(fromWelcome.phase == .skipped)
    }

    @Test func laterSkipsWithoutStarting() {
        var machine = GuidedTourMachine()
        machine.postpone()
        #expect(machine.phase == .skipped)
        // « C'est parti » n'a plus d'effet sans « Revoir ».
        machine.start()
        #expect(machine.phase == .skipped)
    }

    @Test(arguments: TourID.allCases)
    func replayBringsTheWelcomeBackAfterFinishOrSkip(tour: TourID) {
        var finished = GuidedTourMachine(tour: tour, phase: .finished)
        finished.replay()
        #expect(finished.phase == .welcome)
        finished.start()
        #expect(finished.currentStep == tour.steps.first)

        var skipped = GuidedTourMachine(tour: tour, phase: .skipped)
        skipped.replay()
        #expect(skipped.phase == .welcome)
    }

    @Test func outOfRangeSavedStepRestartsAtTheFirst() {
        #expect(GuidedTourMachine(phase: .touring(index: 42)).phase == .touring(index: 0))
        #expect(GuidedTourMachine(tour: .racoonette, phase: .touring(index: 11)).phase == .touring(index: 0))
        #expect(GuidedTourMachine(steps: [], phase: .touring(index: 0)).phase == .finished)
    }

    // MARK: Persistance

    @Test func phaseRoundTripsThroughTheStore() {
        let phases: [GuidedTourMachine.Phase] = [.welcome, .touring(index: 0), .touring(index: 3), .finished, .skipped]
        for phase in phases {
            #expect(GuidedTourStore.decode(GuidedTourStore.encode(phase)) == phase)
        }
        #expect(GuidedTourStore.decode("touring:-1") == nil)
        #expect(GuidedTourStore.decode("n'importe quoi") == nil)
    }

    @Test func everyMoveIsSavedAndSurvivesARelaunch() {
        let defaults = makeDefaults()
        let tour = makeTour(.noisette, defaults)
        #expect(tour.showsWelcome)
        tour.start()
        tour.next()
        tour.next()
        tour.next()
        #expect(tour.currentStep == .homeOrders)

        // Nouveau lancement (ou nouveau rendu) : la visite reprend à la même étape.
        let relaunched = makeTour(.noisette, defaults)
        #expect(relaunched.currentStep == .homeOrders)
        relaunched.back()
        #expect(makeTour(.noisette, defaults).currentStep == .homeSavings)
    }

    @Test(arguments: TourID.allCases)
    func completionIsPersistedAndNeverShownAgain(tourID: TourID) {
        let defaults = makeDefaults()
        let tour = makeTour(tourID, defaults)
        tour.start()
        for _ in tourID.steps { tour.next() }
        #expect(tour.machine.phase == .finished)
        #expect(tour.currentStep == nil)

        let relaunched = makeTour(tourID, defaults)
        #expect(!relaunched.showsWelcome)
        #expect(relaunched.currentStep == nil)
    }

    @Test(arguments: TourID.allCases)
    func skipIsPersistedAndReplayRestartsFromTheWelcome(tourID: TourID) {
        let defaults = makeDefaults()
        let tour = makeTour(tourID, defaults)
        tour.start()
        tour.next()
        tour.skip()
        #expect(makeTour(tourID, defaults).machine.phase == .skipped)

        tour.replay()
        #expect(tour.showsWelcome)
        #expect(makeTour(tourID, defaults).showsWelcome)
        tour.start()
        #expect(tour.currentStep == tourID.steps.first)
    }

    @Test func tourAlreadySeenWithTheOldVersionDoesNotComeBackForNoisetteOnly() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: GuidedTourStore.legacyWelcomeSeenKey)
        #expect(makeStore(defaults).load(tour: .noisette).phase == .finished)
        // Racoonette n'existait pas : sa première fois reste à faire.
        #expect(makeStore(defaults).load(tour: .racoonette).phase == .welcome)
    }

    // MARK: Plusieurs visites

    @Test func eachTourKeepsItsOwnProgress() {
        let defaults = makeDefaults()
        let noisette = makeTour(.noisette, defaults)
        let racoonette = makeTour(.racoonette, defaults)
        noisette.start()
        noisette.next()
        noisette.next()
        racoonette.start()
        racoonette.next()
        #expect(noisette.currentStep == .homeSavings)
        #expect(racoonette.currentStep == .vendorStats)

        // Terminer ou passer l'une ne touche pas l'autre, même après un relancement.
        racoonette.skip()
        let relaunchedNoisette = makeTour(.noisette, defaults)
        let relaunchedRacoonette = makeTour(.racoonette, defaults)
        #expect(relaunchedNoisette.currentStep == .homeSavings)
        #expect(relaunchedRacoonette.machine.phase == .skipped)
        #expect(!relaunchedRacoonette.showsWelcome)
    }

    @Test func storageKeysAreDistinctAndNoisetteKeepsItsFirstVersionKey() {
        #expect(TourID.noisette.storageKey == "guidedTour.phase")
        #expect(GuidedTourStore.phaseKey == TourID.noisette.storageKey)
        #expect(Set(TourID.allCases.map(\.storageKey)).count == TourID.allCases.count)
    }

    @Test func replayOfOneTourLeavesTheOtherAlone() {
        let defaults = makeDefaults()
        let noisette = makeTour(.noisette, defaults)
        let racoonette = makeTour(.racoonette, defaults)
        noisette.postpone()
        racoonette.postpone()
        racoonette.replay()
        #expect(racoonette.showsWelcome)
        #expect(!noisette.showsWelcome)
        #expect(makeTour(.noisette, defaults).machine.phase == .skipped)
    }

    @Test func firstEntryToTheVendorPortalShowsTheWelcomeThenNeverAgain() {
        let defaults = makeDefaults()
        // Première fois dans le portail Vendeurs : la carte d'accueil de Racoonette se présente.
        let first = makeTour(.racoonette, defaults)
        #expect(first.showsWelcome)
        first.start()
        #expect(first.currentStep == .vendorIntro)
        for _ in TourID.racoonette.steps { first.next() }
        // Retour dans le portail plus tard : rien ne s'affiche.
        let later = makeTour(.racoonette, defaults)
        #expect(!later.showsWelcome)
        #expect(later.currentStep == nil)
    }

    @Test func replayEntryIsInTheProfileOfTheMascotsPortal() {
        #expect(TourID.noisette.portal == .family)
        #expect(TourID.racoonette.portal == .vendor)
        #expect(TourID.allCases.map(\.portal).count == Set(TourID.allCases.map(\.portal)).count)
    }

    @Test func mascotsHaveTheirOwnNames() {
        #expect(TourID.noisette.mascotName == MascotView.name)
        #expect(TourID.racoonette.mascotName == RacoonetteView.name)
        #expect(MascotView.name != RacoonetteView.name)
    }

    // MARK: Démo

    @Test func demoTourReplaysAtLaunchOnlyForItsOwnArgument() {
        let defaults = makeDefaults()
        let noisette = makeTour(.noisette, defaults)
        let racoonette = makeTour(.racoonette, defaults)
        noisette.postpone()
        racoonette.postpone()
        noisette.configureAtLaunch(arguments: ["-useFakeData"])
        #expect(!noisette.showsWelcome)

        noisette.configureAtLaunch(arguments: ["-useFakeData", "-demoTour"])
        racoonette.configureAtLaunch(arguments: ["-useFakeData", "-demoTour"])
        #expect(noisette.showsWelcome)
        #expect(!racoonette.showsWelcome)

        racoonette.configureAtLaunch(arguments: ["-useFakeData", "-demoVendorTour"])
        #expect(racoonette.showsWelcome)
    }

    // MARK: Ancres

    @Test func anchorsAreRememberedForTheBubbleAndForgottenWhenTheirScreenGoes() {
        let tour = makeTour()
        let anchor = TourAnchor(frame: CGRect(x: 16, y: 300, width: 360, height: 80), cornerRadius: 24, padding: 6)
        tour.updateAnchor(anchor, for: .pickup)
        #expect(tour.anchor(for: .pickup) == anchor)
        tour.removeAnchor(for: .pickup)
        #expect(tour.anchor(for: .pickup) == nil)
    }

    @Test func demoTourStepJumpsStraightToThatStep() {
        let tour = makeTour(.racoonette)
        tour.configureAtLaunch(arguments: ["-demoVendorTour", "-demoTourStep", "4"])
        #expect(tour.currentStep == TourID.racoonette.steps[4])
    }

    @Test func newAnchorOfTheCurrentStepAsksForAScroll() {
        let tour = makeTour()
        tour.start()
        let before = tour.scrollTick
        let anchor = TourAnchor(frame: CGRect(x: 0, y: 900, width: 300, height: 60), cornerRadius: 24, padding: 6)
        // Ancre d'une autre étape : pas de défilement.
        tour.updateAnchor(anchor, for: .pickup)
        #expect(tour.scrollTick == before)
        // Ancre de l'étape en cours (l'étape 1 est sans élément : on avance jusqu'à « Ton groupe »).
        tour.next()
        tour.updateAnchor(anchor, for: .homeGroup)
        #expect(tour.scrollTick == before + 1)
        // Un simple déplacement de cette ancre ne redemande rien.
        tour.updateAnchor(TourAnchor(frame: anchor.frame.offsetBy(dx: 0, dy: -40), cornerRadius: 24, padding: 6), for: .homeGroup)
        #expect(tour.scrollTick == before + 1)
    }

    @Test func anchorsOfEachTourStayInTheirOwnTour() {
        let noisette = makeTour(.noisette)
        let racoonette = makeTour(.racoonette)
        let anchor = TourAnchor(frame: CGRect(x: 0, y: 100, width: 100, height: 100), cornerRadius: 24, padding: 6)
        noisette.updateAnchor(anchor, for: .homeGroup)
        #expect(racoonette.anchor(for: .homeGroup) == nil)
        #expect(racoonette.anchor(for: .vendorStats) == nil)
    }

    // MARK: Activation

    @Test func tourIsOffInTestsPreviewsAndFakeDataUnlessItsDemoArgument() {
        let xcTest = [BackendLaunchOptions.xcTestVariable: "/tmp/x.xctestconfiguration"]
        #expect(GuidedTourPolicy.isEnabled(arguments: [], environment: [:]))
        #expect(!GuidedTourPolicy.isEnabled(arguments: [], environment: xcTest))
        #expect(!GuidedTourPolicy.isEnabled(arguments: [], environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        #expect(!GuidedTourPolicy.isEnabled(arguments: ["-useFakeData"], environment: [:]))
        #expect(!GuidedTourPolicy.isEnabled(arguments: ["-useFakeBackend", "YES"], environment: [:]))
        #expect(GuidedTourPolicy.isEnabled(arguments: ["-useFakeData", "-demoTour"], environment: [:]))
        #expect(GuidedTourPolicy.replaysAtLaunch(arguments: ["-demoTour"]))
        #expect(!GuidedTourPolicy.replaysAtLaunch(arguments: ["-useFakeData"]))
        // Racoonette a son propre argument.
        #expect(!GuidedTourPolicy.isEnabled(tour: .racoonette, arguments: ["-useFakeData", "-demoTour"], environment: [:]))
        #expect(GuidedTourPolicy.isEnabled(tour: .racoonette, arguments: ["-useFakeData", "-demoVendorTour"], environment: [:]))
        #expect(GuidedTourPolicy.replaysAtLaunch(tour: .racoonette, arguments: ["-demoVendorTour"]))
        #expect(!GuidedTourPolicy.replaysAtLaunch(tour: .racoonette, arguments: ["-demoTour"]))
    }

    @Test func disabledTourShowsNothingAndIgnoresReplay() {
        let tour = makeTour(.racoonette, enabled: false)
        #expect(!tour.showsWelcome)
        #expect(tour.currentStep == nil)
        tour.replay()
        #expect(!tour.showsWelcome)
    }

    @Test func sharedToursAreOffWhileUnitTestsRun() {
        #expect(!GuidedTour.noisette.isEnabled)
        #expect(!GuidedTour.racoonette.isEnabled)
        #expect(GuidedTour.instance(for: .noisette) === GuidedTour.noisette)
        #expect(GuidedTour.instance(for: .racoonette) === GuidedTour.racoonette)
    }
}
