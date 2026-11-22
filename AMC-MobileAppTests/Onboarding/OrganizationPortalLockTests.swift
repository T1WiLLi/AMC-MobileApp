import Foundation
import Testing
@testable import AMC_MobileApp

/// Un compte d'organisme n'a que le portail Organismes : pas de choix du portail, pas de bascule.
@MainActor
struct OrganizationPortalLockTests {
    @Test func organizationAccountOnlyHasOrganizationPortal() {
        #expect(Portal.available(hasOrganization: true) == [.organization])
        #expect(Portal.available(hasOrganization: false) == [.family, .vendor])
    }

    @Test func lockToOrganizationSkipsPortalChoice() throws {
        let defaults = try #require(UserDefaults(suiteName: "org-lock-\(UUID().uuidString)"))
        Portal.lockToOrganization(in: defaults)
        #expect(defaults.string(forKey: Portal.storageKey) == Portal.organization.rawValue)
        #expect(defaults.bool(forKey: OnboardingKeys.hasChosenPortal))
        #expect(AppFlowStep.resolve(hasSeenIntro: true, isSignedIn: true,
                                    hasChosenPortal: defaults.bool(forKey: OnboardingKeys.hasChosenPortal)) == .app)
    }
}
