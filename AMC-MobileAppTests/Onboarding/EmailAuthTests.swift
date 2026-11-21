import Foundation
import Testing
@testable import AMC_MobileApp

/// Horloge réglable pour tester le délai de renvoi sans attendre 60 s.
@MainActor
private final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date += seconds }
}

@MainActor
struct EmailSessionTests {
    private func makeSession(_ auth: FakeAuthService = FakeAuthService(latency: .zero)) -> (SessionViewModel, FakeAuthService, TestClock) {
        let clock = TestClock()
        let session = SessionViewModel(auth: auth, now: { clock.date })
        return (session, auth, clock)
    }

    @Test func signUpLeadsToVerificationAndSendsLink() async {
        let (session, auth, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        #expect(session.pendingVerificationUser?.email == "amina@example.com")
        #expect(session.pendingVerificationUser?.displayName == "Amina")
        #expect(session.currentUser == nil)
        #expect(auth.sentVerificationCount == 1)
        #expect(session.emailAuthError == nil)
    }

    @Test func unverifiedUserSeesVerificationStep() async {
        let (session, _, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        let step = AppFlowStep.resolve(
            hasSeenIntro: true,
            isSignedIn: session.currentUser != nil,
            hasChosenPortal: true,
            needsEmailVerification: session.pendingVerificationUser != nil
        )
        #expect(step == .emailVerification)
    }

    @Test func checkBeforeClickingLinkExplains() async {
        let (session, _, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        let verified = await session.checkEmailVerification()
        #expect(!verified)
        #expect(session.pendingVerificationUser != nil)
        #expect(session.verificationMessage != nil)
    }

    @Test func verifiedUserEntersApp() async {
        let (session, auth, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        auth.markEmailVerified()
        let verified = await session.checkEmailVerification()
        #expect(verified)
        #expect(session.currentUser?.isEmailVerified == true)
        #expect(session.pendingVerificationUser == nil)
        let step = AppFlowStep.resolve(hasSeenIntro: true, isSignedIn: true, hasChosenPortal: true, needsEmailVerification: false)
        #expect(step == .app)
    }

    @Test func silentCheckOnForegroundShowsNothing() async {
        let (session, _, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        await session.checkEmailVerification(silent: true)
        #expect(session.verificationMessage == nil)
    }

    @Test func restoredUnverifiedSessionWaitsForVerification() {
        let session = SessionViewModel(auth: FakeAuthService(signedInUser: .unverifiedSample, latency: .zero))
        #expect(session.pendingVerificationUser == .unverifiedSample)
        #expect(session.currentUser == nil)
    }

    @Test func googleUserIsNeverAskedToVerify() {
        #expect(!AuthUser.sample.needsEmailVerification)
        #expect(AuthUser.unverifiedSample.needsEmailVerification)
    }

    @Test func signInWithVerifiedAccountOpensApp() async {
        let auth = FakeAuthService(latency: .zero)
        auth.addAccount(email: "amina@example.com", password: "secret12", verified: true)
        let (session, _, _) = makeSession(auth)
        await session.signIn(email: "Amina@example.com ", password: "secret12")
        #expect(session.currentUser?.email == "amina@example.com")
    }

    @Test func signInWithUnverifiedAccountAsksVerification() async {
        let auth = FakeAuthService(latency: .zero)
        auth.addAccount(email: "amina@example.com", password: "secret12", verified: false)
        let (session, _, _) = makeSession(auth)
        await session.signIn(email: "amina@example.com", password: "secret12")
        #expect(session.pendingVerificationUser != nil)
    }

    @Test func wrongPasswordShowsUnderPasswordField() async {
        let auth = FakeAuthService(latency: .zero)
        auth.addAccount(email: "amina@example.com", password: "secret12")
        let (session, _, _) = makeSession(auth)
        await session.signIn(email: "amina@example.com", password: "mauvais")
        #expect(session.state == .signedOut)
        #expect(session.emailAuthError == .wrongPassword)
        #expect(session.emailAuthError?.field == .password)
    }

    @Test func emailAlreadyInUseShowsUnderEmailField() async {
        let auth = FakeAuthService(latency: .zero)
        auth.addAccount(email: "amina@example.com", password: "secret12")
        let (session, _, _) = makeSession(auth)
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        #expect(session.emailAuthError == .emailAlreadyInUse)
        #expect(session.emailAuthError?.field == .email)
    }

    @Test func weakPasswordIsRefused() async {
        let (session, _, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "abc", displayName: "Amina")
        #expect(session.emailAuthError == .weakPassword)
    }

    @Test func networkErrorIsGeneralAndOffline() async {
        let (session, _, _) = makeSession(FakeAuthService(nextError: .network, latency: .zero))
        await session.signIn(email: "amina@example.com", password: "secret12")
        #expect(session.emailAuthError == .network)
        #expect(session.emailAuthError?.field == .general)
        #expect(AuthError.network.appError == .offline)
        #expect(AuthError.tooManyRequests.errorDescription?.contains("Trop de tentatives") == true)
    }

    @Test func editingTheFieldClearsItsError() async {
        let auth = FakeAuthService(latency: .zero)
        auth.addAccount(email: "amina@example.com", password: "secret12")
        let (session, _, _) = makeSession(auth)
        await session.signIn(email: "amina@example.com", password: "mauvais")
        session.clearEmailError(for: .email)
        #expect(session.emailAuthError != nil)
        session.clearEmailError(for: .password)
        #expect(session.emailAuthError == nil)
    }

    @Test func resendWaitsSixtySeconds() async {
        let (session, auth, clock) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        #expect(session.resendSecondsRemaining() == 60)
        #expect(!session.canResendVerification())

        await session.resendVerificationEmail()
        #expect(auth.sentVerificationCount == 1)

        clock.advance(45)
        #expect(session.resendSecondsRemaining() == 15)

        clock.advance(15)
        #expect(session.canResendVerification())
        await session.resendVerificationEmail()
        #expect(auth.sentVerificationCount == 2)
        #expect(session.resendSecondsRemaining() == 60)
        #expect(session.verificationMessage != nil)
    }

    @Test func passwordResetSendsLink() async {
        let (session, auth, _) = makeSession()
        let error = await session.sendPasswordReset(email: "amina@example.com")
        #expect(error == nil)
        #expect(auth.passwordResetEmails == ["amina@example.com"])
        #expect(await session.sendPasswordReset(email: "amina") == .invalidEmail)
    }

    @Test func changeAddressSignsOut() async {
        let (session, _, _) = makeSession()
        await session.signUp(email: "amina@example.com", password: "secret12", displayName: "Amina")
        session.signOut()
        #expect(session.state == .signedOut)
        #expect(session.resendSecondsRemaining() == 0)
    }
}

@MainActor
struct EmailAuthValidationTests {
    @Test func emailFormat() {
        #expect(EmailAuthValidation.isValidEmail("amina@example.com"))
        #expect(EmailAuthValidation.isValidEmail(" amina.t+grenier@quartier.qc.ca "))
        #expect(!EmailAuthValidation.isValidEmail("amina"))
        #expect(!EmailAuthValidation.isValidEmail("amina@example"))
        #expect(!EmailAuthValidation.isValidEmail("am ina@example.com"))
        #expect(EmailAuthValidation.emailIssue("") == nil)
        #expect(EmailAuthValidation.emailIssue("amina") != nil)
        #expect(EmailAuthValidation.emailIssue("amina@") != nil)
    }

    @Test func passwordMinimumIsSix() {
        #expect(EmailAuthValidation.passwordIssue("") == nil)
        #expect(EmailAuthValidation.passwordIssue("abcde") == "Encore 1 caractère (6 minimum).")
        #expect(EmailAuthValidation.passwordIssue("abc") == "Encore 3 caractères (6 minimum).")
        #expect(EmailAuthValidation.passwordIssue("abcdef") == nil)
    }

    @Test func strengthGrowsWithVariety() {
        #expect(PasswordStrength("abc") == .tooShort)
        #expect(PasswordStrength("abcdef") == .weak)
        #expect(PasswordStrength("abcdef12") == .weak)
        #expect(PasswordStrength("Abcdef12") == .fair)
        #expect(PasswordStrength("Abcdef12!xyz") == .strong)
        #expect(PasswordStrength("abc") < PasswordStrength("Abcdef12!xyz"))
    }
}
