import Foundation
import Testing
@testable import AMC_MobileApp

/// Visite guidée avec Noisette (FB-19) : ordre des étapes, machine à états (suivant, précédent, passer, rejouer),
/// persistance, activation en tests et en démo.
@MainActor
struct GuidedTourTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "GuidedTourTests-\(UUID().uuidString)")!
    }

    private func makeStore(_ defaults: UserDefaults? = nil) -> GuidedTourStore {
        GuidedTourStore(defaults: defaults ?? makeDefaults())
    }

    // MARK: Étapes

    @Test func stepsFollowTheTourOrder() {
        #expect(TourStep.allCases == [.nearbyOffers, .reserveShare, .pickup, .groups, .impact])
        #expect(TourStep.allCases.map(\.screen) == [.home, .home, .pickup, .groups, .impact])
        #expect(GuidedTourMachine().steps == TourStep.allCases)
    }

    @Test func everyScreenHasAStepAndATab() {
        for screen in TourScreen.allCases {
            #expect(TourStep.allCases.contains { $0.screen == screen })
        }
        #expect(TourScreen.allCases.map(FamilyTabView.tab(for:)) == [.home, .pickup, .groups, .impact])
    }

    // MARK: Machine à états

    @Test func startsOnTheWelcomeCard() {
        let machine = GuidedTourMachine()
        #expect(machine.phase == .welcome)
        #expect(machine.currentStep == nil)
        #expect(!machine.isTouring)
    }

    @Test func nextWalksEveryStepThenFinishes() {
        var machine = GuidedTourMachine()
        machine.start()
        var seen: [TourStep] = []
        while let step = machine.currentStep {
            seen.append(step)
            machine.next()
        }
        #expect(seen == TourStep.allCases)
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
        #expect(machine.currentStep == .pickup)
        machine.back()
        #expect(machine.currentStep == .reserveShare)
    }

    @Test func lastStepIsFlagged() {
        var machine = GuidedTourMachine(phase: .touring(index: TourStep.allCases.count - 1))
        #expect(machine.isLastStep)
        #expect(machine.currentStep == .impact)
        machine.next()
        #expect(machine.phase == .finished)
    }

    @Test func skipStopsTheTourFromAnyStep() {
        for index in TourStep.allCases.indices {
            var machine = GuidedTourMachine(phase: .touring(index: index))
            machine.skip()
            #expect(machine.phase == .skipped)
            #expect(machine.currentStep == nil)
        }
        var fromWelcome = GuidedTourMachine()
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

    @Test func replayBringsTheWelcomeBackAfterFinishOrSkip() {
        var finished = GuidedTourMachine(phase: .finished)
        finished.replay()
        #expect(finished.phase == .welcome)
        finished.start()
        #expect(finished.currentStep == .nearbyOffers)

        var skipped = GuidedTourMachine(phase: .skipped)
        skipped.replay()
        #expect(skipped.phase == .welcome)
    }

    @Test func outOfRangeSavedStepRestartsAtTheFirst() {
        #expect(GuidedTourMachine(phase: .touring(index: 42)).phase == .touring(index: 0))
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
        let tour = GuidedTour(store: makeStore(defaults), isEnabled: true)
        #expect(tour.showsWelcome)
        tour.start()
        tour.next()
        tour.next()
        #expect(tour.currentStep == .pickup)

        // Nouveau lancement (ou nouveau rendu) : la visite reprend à la même étape.
        let relaunched = GuidedTour(store: makeStore(defaults), isEnabled: true)
        #expect(relaunched.currentStep == .pickup)
        relaunched.back()
        #expect(GuidedTour(store: makeStore(defaults), isEnabled: true).currentStep == .reserveShare)
    }

    @Test func completionIsPersistedAndNeverShownAgain() {
        let defaults = makeDefaults()
        let tour = GuidedTour(store: makeStore(defaults), isEnabled: true)
        tour.start()
        for _ in TourStep.allCases { tour.next() }
        #expect(tour.machine.phase == .finished)
        #expect(tour.currentStep == nil)

        let relaunched = GuidedTour(store: makeStore(defaults), isEnabled: true)
        #expect(!relaunched.showsWelcome)
        #expect(relaunched.currentStep == nil)
    }

    @Test func skipIsPersistedAndReplayRestartsFromTheWelcome() {
        let defaults = makeDefaults()
        let tour = GuidedTour(store: makeStore(defaults), isEnabled: true)
        tour.start()
        tour.next()
        tour.skip()
        #expect(GuidedTour(store: makeStore(defaults), isEnabled: true).machine.phase == .skipped)

        tour.replay()
        #expect(tour.showsWelcome)
        #expect(GuidedTour(store: makeStore(defaults), isEnabled: true).showsWelcome)
        tour.start()
        #expect(tour.currentStep == .nearbyOffers)
    }

    @Test func tourAlreadySeenWithTheOldVersionDoesNotComeBack() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: GuidedTourStore.legacyWelcomeSeenKey)
        #expect(makeStore(defaults).load().phase == .finished)
    }

    @Test func demoTourReplaysAtLaunch() {
        let defaults = makeDefaults()
        let tour = GuidedTour(store: makeStore(defaults), isEnabled: true)
        tour.postpone()
        tour.configureAtLaunch(arguments: ["-useFakeData"])
        #expect(!tour.showsWelcome)
        tour.configureAtLaunch(arguments: ["-useFakeData", "-demoTour"])
        #expect(tour.showsWelcome)
    }

    @Test func anchorsAreRememberedForTheBubble() {
        let tour = GuidedTour(store: makeStore(), isEnabled: true)
        let frame = CGRect(x: 16, y: 300, width: 360, height: 80)
        tour.updateAnchor(frame, for: .pickup)
        #expect(tour.anchorFrames[.pickup] == frame)
    }

    // MARK: Activation

    @Test func tourIsOffInTestsPreviewsAndFakeDataUnlessDemoTour() {
        let xcTest = [BackendLaunchOptions.xcTestVariable: "/tmp/x.xctestconfiguration"]
        #expect(GuidedTourPolicy.isEnabled(arguments: [], environment: [:]))
        #expect(!GuidedTourPolicy.isEnabled(arguments: [], environment: xcTest))
        #expect(!GuidedTourPolicy.isEnabled(arguments: [], environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]))
        #expect(!GuidedTourPolicy.isEnabled(arguments: ["-useFakeData"], environment: [:]))
        #expect(!GuidedTourPolicy.isEnabled(arguments: ["-useFakeBackend", "YES"], environment: [:]))
        #expect(GuidedTourPolicy.isEnabled(arguments: ["-useFakeData", "-demoTour"], environment: [:]))
        #expect(GuidedTourPolicy.replaysAtLaunch(arguments: ["-demoTour"]))
        #expect(!GuidedTourPolicy.replaysAtLaunch(arguments: ["-useFakeData"]))
    }

    @Test func disabledTourShowsNothingAndIgnoresReplay() {
        let tour = GuidedTour(store: makeStore(), isEnabled: false)
        #expect(!tour.showsWelcome)
        #expect(tour.currentStep == nil)
        tour.replay()
        #expect(!tour.showsWelcome)
    }

    @Test func sharedTourIsOffWhileUnitTestsRun() {
        #expect(!GuidedTour.shared.isEnabled)
    }
}
