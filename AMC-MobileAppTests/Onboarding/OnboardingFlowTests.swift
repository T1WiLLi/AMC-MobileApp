import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct AppFlowStepTests {
    @Test func introComesFirstEvenWhenSignedIn() {
        #expect(AppFlowStep.resolve(hasSeenIntro: false, isSignedIn: false, hasChosenPortal: false) == .intro)
        #expect(AppFlowStep.resolve(hasSeenIntro: false, isSignedIn: true, hasChosenPortal: true) == .intro)
    }

    @Test func signInAfterIntro() {
        #expect(AppFlowStep.resolve(hasSeenIntro: true, isSignedIn: false, hasChosenPortal: false) == .signIn)
        #expect(AppFlowStep.resolve(hasSeenIntro: true, isSignedIn: false, hasChosenPortal: true) == .signIn)
    }

    @Test func portalChoiceOnlyAfterFirstSignIn() {
        #expect(AppFlowStep.resolve(hasSeenIntro: true, isSignedIn: true, hasChosenPortal: false) == .portalChoice)
    }

    @Test func appOnceEverythingIsDone() {
        #expect(AppFlowStep.resolve(hasSeenIntro: true, isSignedIn: true, hasChosenPortal: true) == .app)
    }

    @Test func fullOrderIsIntroSignInChoiceApp() {
        var seen = false, signedIn = false, chosen = false
        var steps: [AppFlowStep] = [AppFlowStep.resolve(hasSeenIntro: seen, isSignedIn: signedIn, hasChosenPortal: chosen)]
        seen = true
        steps.append(.resolve(hasSeenIntro: seen, isSignedIn: signedIn, hasChosenPortal: chosen))
        signedIn = true
        steps.append(.resolve(hasSeenIntro: seen, isSignedIn: signedIn, hasChosenPortal: chosen))
        chosen = true
        steps.append(.resolve(hasSeenIntro: seen, isSignedIn: signedIn, hasChosenPortal: chosen))
        #expect(steps == [.intro, .signIn, .portalChoice, .app])
    }
}

@MainActor
struct IntroPageTests {
    @Test func threePagesInOrder() {
        #expect(IntroPage.allCases == [.problem, .solution, .solidarity])
        #expect(IntroPage.problem.next == .solution)
        #expect(IntroPage.solution.next == .solidarity)
        #expect(IntroPage.solidarity.next == nil)
        #expect(IntroPage.solidarity.isLast)
        #expect(!IntroPage.problem.isLast)
    }

    @Test func everyPageHasFrenchCopy() {
        for page in IntroPage.allCases {
            #expect(!page.title.isEmpty)
            #expect(!page.message.isEmpty)
            #expect(!page.eyebrow.isEmpty)
        }
    }
}

@MainActor
struct PortalChoiceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "portal-choice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func choiceFromSelection() {
        #expect(PortalChoice(selection: []) == nil)
        #expect(PortalChoice(selection: [.family]) == .family)
        #expect(PortalChoice(selection: [.vendor]) == .vendor)
        #expect(PortalChoice(selection: [.family, .vendor]) == .both)
    }

    @Test func bothOpensFamilyFirst() {
        #expect(PortalChoice.both.initialPortal == .family)
        #expect(PortalChoice.vendor.initialPortal == .vendor)
        #expect(PortalChoice.both.portals == [.family, .vendor])
    }

    @Test func cannotContinueWithoutSelection() {
        let model = PortalChoiceViewModel()
        let defaults = makeDefaults()
        #expect(!model.canContinue)
        #expect(!model.confirm(in: defaults))
        #expect(!defaults.bool(forKey: OnboardingKeys.hasChosenPortal))
    }

    @Test func toggleSelectsAndDeselects() {
        let model = PortalChoiceViewModel()
        model.toggle(.vendor)
        #expect(model.isSelected(.vendor))
        #expect(model.choice == .vendor)
        model.toggle(.family)
        #expect(model.choice == .both)
        model.toggle(.vendor)
        #expect(model.choice == .family)
        #expect(!model.isSelected(.vendor))
    }

    @Test func confirmWritesPortalAndFlag() {
        let defaults = makeDefaults()
        let model = PortalChoiceViewModel(selection: [.vendor])
        #expect(model.confirm(in: defaults))
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.vendor.rawValue)
        #expect(defaults.string(forKey: OnboardingKeys.portalChoice) == PortalChoice.vendor.rawValue)
        #expect(defaults.bool(forKey: OnboardingKeys.hasChosenPortal))
    }

    @Test func confirmBothStoresFamilyAsActive() {
        let defaults = makeDefaults()
        let model = PortalChoiceViewModel(selection: [.family, .vendor])
        model.confirm(in: defaults)
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.family.rawValue)
        #expect(defaults.string(forKey: OnboardingKeys.portalChoice) == PortalChoice.both.rawValue)
    }

    @Test func hintFollowsSelection() {
        let model = PortalChoiceViewModel()
        let empty = model.hint
        model.toggle(.family)
        let family = model.hint
        model.toggle(.vendor)
        #expect(Set([empty, family, model.hint]).count == 3)
    }

    @Test func portalsHaveTaglines() {
        #expect(Portal.family.tagline == "J'achète avec mon quartier")
        #expect(Portal.vendor.tagline == "Je vends aux quartiers")
        for portal in Portal.allCases { #expect(!portal.detail.isEmpty) }
    }
}

@MainActor
struct OnboardingLaunchArgumentsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "onboarding-args-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func resetClearsFlagsAndPortal() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: OnboardingKeys.hasSeenIntro)
        defaults.set(true, forKey: OnboardingKeys.hasChosenPortal)
        defaults.set(Portal.vendor.rawValue, forKey: Portal.storageKey)
        OnboardingKeys.applyLaunchArguments([OnboardingKeys.resetArgument], to: defaults)
        #expect(!defaults.bool(forKey: OnboardingKeys.hasSeenIntro))
        #expect(!defaults.bool(forKey: OnboardingKeys.hasChosenPortal))
        #expect(defaults.string(forKey: Portal.storageKey) == nil)
    }

    @Test func demoArgumentForcesFamily() {
        let defaults = makeDefaults()
        defaults.set(Portal.vendor.rawValue, forKey: Portal.storageKey)
        OnboardingKeys.applyLaunchArguments([OnboardingKeys.familyArgument], to: defaults)
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.family.rawValue)
    }

    @Test func noArgumentChangesNothing() {
        let defaults = makeDefaults()
        defaults.set(Portal.vendor.rawValue, forKey: Portal.storageKey)
        defaults.set(true, forKey: OnboardingKeys.hasSeenIntro)
        OnboardingKeys.applyLaunchArguments([], to: defaults)
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.vendor.rawValue)
        #expect(defaults.bool(forKey: OnboardingKeys.hasSeenIntro))
    }
}
