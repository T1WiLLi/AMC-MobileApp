import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct DemoToolsTests {
    @Test func gateIsOpenInDebugAndClosedInReleaseWithoutArgument() {
        #expect(DemoToolsGate.isEnabled(isDebugBuild: true, arguments: []))
        #expect(!DemoToolsGate.isEnabled(isDebugBuild: false, arguments: ["-resetOnboarding"]))
        #expect(DemoToolsGate.isEnabled(isDebugBuild: false, arguments: ["-demoTools"]))
    }

    @Test func planDependsOnBackendMode() {
        #expect(DemoResetPlan.plan(for: .fake) == .reloadFakeData)
        guard case let .runSeed(emulator, _) = DemoResetPlan.plan(for: .emulator),
              case let .runSeed(project, _) = DemoResetPlan.plan(for: .demoProject) else {
            Issue.record("Firebase doit afficher une commande de seed")
            return
        }
        #expect(emulator == "npm --prefix scripts/seed run seedDemo")
        #expect(project.contains("seed:firestore"))
    }

    @Test func fakeResetReloadsRepositoriesAndClearsOnboarding() throws {
        let defaults = try #require(UserDefaults(suiteName: "DemoToolsTests-fake"))
        defer { defaults.removePersistentDomain(forName: "DemoToolsTests-fake") }
        defaults.set(true, forKey: OnboardingKeys.hasSeenIntro)
        defaults.set(true, forKey: OnboardingKeys.hasChosenPortal)
        defaults.set("vendor", forKey: OnboardingKeys.portalChoice)

        let demo = DemoEnvironment(context: .instant, mode: .fake)
        let before = demo.context.repositories.offers as AnyObject
        #expect(demo.resetFakeDemo(defaults: defaults))

        #expect(demo.generation == 1)
        #expect(demo.lastResetAt != nil)
        #expect(demo.context.repositories.offers as AnyObject !== before)
        #expect(demo.context.householdId == FakeData.ID.aminaHousehold)
        #expect(defaults.object(forKey: OnboardingKeys.hasSeenIntro) == nil)
        #expect(defaults.object(forKey: OnboardingKeys.hasChosenPortal) == nil)
        #expect(defaults.object(forKey: OnboardingKeys.portalChoice) == nil)
    }

    @Test(arguments: [BackendMode.emulator, .demoProject])
    func firebaseModesNeverResetInApp(mode: BackendMode) throws {
        let defaults = try #require(UserDefaults(suiteName: "DemoToolsTests-\(mode.rawValue)"))
        defer { defaults.removePersistentDomain(forName: "DemoToolsTests-\(mode.rawValue)") }
        defaults.set(true, forKey: OnboardingKeys.hasSeenIntro)

        let demo = DemoEnvironment(context: .instant, mode: mode)
        #expect(!demo.resetFakeDemo(defaults: defaults))
        #expect(demo.generation == 0)
        #expect(defaults.bool(forKey: OnboardingKeys.hasSeenIntro))
    }

    @Test func fiveQuickTapsOpenTheTools() {
        var counter = TapBurstCounter()
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<4 {
            let opened = counter.register(at: start.addingTimeInterval(Double(i) * 0.3))
            #expect(!opened)
        }
        let opened = counter.register(at: start.addingTimeInterval(1.5))
        #expect(opened)
        #expect(counter.taps.isEmpty)
    }

    @Test func slowTapsDoNotOpenTheTools() {
        var counter = TapBurstCounter()
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<10 {
            let opened = counter.register(at: start.addingTimeInterval(Double(i) * 1.0))
            #expect(!opened)
        }
    }
}
