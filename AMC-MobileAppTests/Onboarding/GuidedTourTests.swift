import Foundation
import Testing
@testable import AMC_MobileApp

/// Visite guidée avec Noisette (FB-19) : ordre des étapes, drapeau « rejouer », activation en tests et en démo.
@MainActor
struct GuidedTourTests {
    private func makeStore() -> GuidedTourStore {
        GuidedTourStore(defaults: UserDefaults(suiteName: "GuidedTourTests-\(UUID().uuidString)")!)
    }

    @Test func stepsFollowTheTourOrder() {
        #expect(TourStep.allCases == [.nearbyOffers, .reserveShare, .pickup, .groups, .impact])
        #expect(TourStep.allCases.map(\.screen) == [.home, .home, .pickup, .groups, .impact])
        #expect((4...6).contains(TourStep.allCases.count))
        #expect(makeStore().tips.map(\.step) == TourStep.allCases)
    }

    @Test func everyScreenHasAStep() {
        for screen in TourScreen.allCases {
            #expect(TourStep.allCases.contains { $0.screen == screen })
        }
    }

    @Test func tipIdsAreUniqueAndChangeOnReplay() {
        let store = makeStore()
        let first = store.tips.map(\.id)
        #expect(Set(first).count == first.count)
        store.replay()
        let second = store.tips.map(\.id)
        #expect(Set(first).isDisjoint(with: second))
        #expect(second.first == TourTip.id(step: .nearbyOffers, run: 1))
    }

    @Test func welcomeThenTouringOrSkipped() {
        let store = makeStore()
        #expect(store.phase == .welcome)
        store.finishWelcome(accepted: true)
        #expect(store.phase == .touring)

        let skipped = makeStore()
        skipped.finishWelcome(accepted: false)
        #expect(skipped.phase == .skipped)
    }

    @Test func replayBringsTheWelcomeBack() {
        let store = makeStore()
        store.finishWelcome(accepted: false)
        #expect(store.run == 0)
        store.replay()
        #expect(store.phase == .welcome)
        #expect(store.run == 1)
        store.finishWelcome(accepted: true)
        store.replay()
        #expect(store.phase == .welcome)
        #expect(store.run == 2)
    }

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
        let store = makeStore()
        let tour = GuidedTour(store: store, isEnabled: false)
        #expect(!tour.showsWelcome)
        #expect(tour.tip(on: .home) == nil)
        tour.replay()
        #expect(store.run == 0)
    }

    @Test func sharedTourIsOffWhileUnitTestsRun() {
        #expect(!GuidedTour.shared.isEnabled)
    }
}
