import Foundation
import LocalAuthentication
import Testing
@testable import AMC_MobileApp

@MainActor
struct AppLockTests {
    func makeDefaults() -> UserDefaults {
        let name = "AppLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func disabledByDefaultAndUnlocked() {
        let lock = AppLock(authenticator: FakeBiometricAuthenticator(), defaults: makeDefaults())
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
    }

    @Test func enableRequiresSuccessfulAuthentication() async {
        let ok = AppLock(authenticator: FakeBiometricAuthenticator(), defaults: makeDefaults())
        #expect(await ok.enable())
        #expect(ok.isEnabled)

        let ko = AppLock(authenticator: FakeBiometricAuthenticator(result: .failure(.permissionDenied)), defaults: makeDefaults())
        #expect(await ko.enable() == false)
        #expect(!ko.isEnabled)
        #expect(ko.lastError == .permissionDenied)
    }

    @Test func locksInBackgroundAndUnlocks() async {
        let lock = AppLock(authenticator: FakeBiometricAuthenticator(), defaults: makeDefaults())
        _ = await lock.enable()
        lock.lockIfEnabled()
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(!lock.isLocked)
    }

    @Test func failedUnlockStaysLockedWithError() async {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppLock.storageKey)
        let lock = AppLock(authenticator: FakeBiometricAuthenticator(result: .failure(.invalidInput("Déverrouillage annulé."))), defaults: defaults)
        #expect(lock.isLocked)
        await lock.unlock()
        #expect(lock.isLocked)
        #expect(lock.lastError == .invalidInput("Déverrouillage annulé."))
    }

    @Test func enabledStatePersistsAndRelocksAtLaunch() async {
        let defaults = makeDefaults()
        let first = AppLock(authenticator: FakeBiometricAuthenticator(), defaults: defaults)
        _ = await first.enable()
        let relaunched = AppLock(authenticator: FakeBiometricAuthenticator(), defaults: defaults)
        #expect(relaunched.isEnabled)
        #expect(relaunched.isLocked)
    }

    @Test func disableUnlocks() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppLock.storageKey)
        let lock = AppLock(authenticator: FakeBiometricAuthenticator(), defaults: defaults)
        lock.disable()
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
    }

    @Test func laErrorsMapToAppErrors() {
        #expect(DeviceBiometricAuthenticator.map(LAError(.userCancel)) == .invalidInput("Déverrouillage annulé."))
        #expect(DeviceBiometricAuthenticator.map(LAError(.authenticationFailed)) == .permissionDenied)
    }
}
