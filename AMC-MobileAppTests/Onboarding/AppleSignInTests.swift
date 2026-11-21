import AuthenticationServices
import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
struct AppleSignInTests {
    private func makeSession(_ auth: FakeAuthService = FakeAuthService(latency: .zero)) -> (SessionViewModel, FakeAuthService) {
        (SessionViewModel(auth: auth), auth)
    }

    private func preparedRequest(for session: SessionViewModel) -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        session.prepareAppleSignIn(request)
        return request
    }

    @Test func sha256MatchesKnownVector() {
        #expect(AppleSignIn.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func randomNonceHasRequestedLengthAndChanges() {
        let first = AppleSignIn.randomNonce()
        #expect(first.count == 32)
        #expect(first != AppleSignIn.randomNonce())
    }

    @Test func flagReadsInfoPlist() {
        #expect(AppleSignIn.isEnabled(in: [AppleSignIn.infoPlistKey: true]))
        #expect(!AppleSignIn.isEnabled(in: [AppleSignIn.infoPlistKey: false]))
        #expect(!AppleSignIn.isEnabled(in: [:]))
    }

    @Test func requestAsksForNameAndEmailWithHashedNonce() throws {
        let (session, _) = makeSession()
        let request = preparedRequest(for: session)
        #expect(request.requestedScopes == [.fullName, .email])
        let nonce = try #require(request.nonce)
        #expect(nonce.count == 64)
    }

    @Test func successSignsInWithRawNonceOfTheRequest() async throws {
        let (session, auth) = makeSession()
        let request = preparedRequest(for: session)
        var name = PersonNameComponents()
        name.givenName = "Amina"

        await session.signInWithApple(.init(idToken: "jeton-apple", fullName: name))

        let raw = try #require(auth.lastAppleNonce)
        #expect(AppleSignIn.sha256(raw) == request.nonce)
        #expect(session.currentUser?.displayName == "Amina")
        #expect(session.errorMessage == nil)
    }

    @Test func cancellationShowsNoError() async {
        let (session, _) = makeSession()
        _ = preparedRequest(for: session)
        await session.completeAppleSignIn(.failure(ASAuthorizationError(.canceled)))
        #expect(session.state == .signedOut)
        #expect(session.errorMessage == nil)
    }

    @Test func appleFailureShowsFrenchMessage() async {
        let (session, _) = makeSession()
        _ = preparedRequest(for: session)
        await session.completeAppleSignIn(.failure(ASAuthorizationError(.failed)))
        #expect(session.state == .signedOut)
        #expect(session.errorMessage == "La connexion avec Apple n'a pas abouti. Réessaie dans un instant.")
    }

    @Test func firebaseFailureShowsItsMessage() async {
        let (session, _) = makeSession(FakeAuthService(nextError: .network, latency: .zero))
        _ = preparedRequest(for: session)
        await session.signInWithApple(.init(idToken: "jeton", fullName: nil))
        #expect(session.state == .signedOut)
        #expect(session.errorMessage == AuthError.network.errorDescription)
    }

    @Test func credentialWithoutPreparedNonceIsRefused() async {
        let (session, auth) = makeSession()
        await session.signInWithApple(.init(idToken: "jeton", fullName: nil))
        #expect(session.state == .signedOut)
        #expect(session.errorMessage != nil)
        #expect(auth.lastAppleNonce == nil)
    }

    @Test func nonceIsSingleUse() async {
        let (session, auth) = makeSession()
        _ = preparedRequest(for: session)
        await session.signInWithApple(.init(idToken: "jeton", fullName: nil))
        session.signOut()
        let firstNonce = auth.lastAppleNonce
        await session.signInWithApple(.init(idToken: "jeton", fullName: nil))
        #expect(session.state == .signedOut)
        #expect(auth.lastAppleNonce == firstNonce)
    }
}
