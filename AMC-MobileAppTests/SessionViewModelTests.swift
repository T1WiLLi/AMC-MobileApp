import Testing
@testable import AMC_MobileApp

@MainActor
struct SessionViewModelTests {
    @Test func startsSignedOutWithoutUser() {
        let session = SessionViewModel(auth: FakeAuthService())
        #expect(session.state == .signedOut)
        #expect(session.currentUser == nil)
    }

    @Test func restoresExistingSession() {
        let session = SessionViewModel(auth: FakeAuthService(signedInUser: .sample))
        #expect(session.currentUser == .sample)
    }

    @Test func googleSignInSucceeds() async {
        let session = SessionViewModel(auth: FakeAuthService())
        await session.signInWithGoogle()
        #expect(session.state == .signedIn(.sample))
        #expect(session.errorMessage == nil)
    }

    @Test func cancelledSignInShowsNoError() async {
        let session = SessionViewModel(auth: FakeAuthService(nextError: .cancelled))
        await session.signInWithGoogle()
        #expect(session.state == .signedOut)
        #expect(session.errorMessage == nil)
    }

    @Test func failedSignInShowsFrenchMessage() async {
        let session = SessionViewModel(auth: FakeAuthService(nextError: .failed("Réseau indisponible.")))
        await session.signInWithGoogle()
        #expect(session.state == .signedOut)
        #expect(session.errorMessage == "Réseau indisponible.")
    }

    @Test func signOutReturnsToSignIn() async {
        let session = SessionViewModel(auth: FakeAuthService(signedInUser: .sample))
        session.signOut()
        #expect(session.state == .signedOut)
    }
}
