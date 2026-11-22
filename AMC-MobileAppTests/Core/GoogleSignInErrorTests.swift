#if canImport(FirebaseAuth) && canImport(GoogleSignIn)
import Foundation
import GoogleSignIn
import FirebaseAuth
import Testing
@testable import AMC_MobileApp

/// QA : les erreurs du SDK Google Sign-In deviennent des `AuthError` en français, jamais le texte brut du SDK.
struct GoogleSignInErrorTests {
    @Test func cancellationIsSilent() {
        let error = NSError(domain: kGIDSignInErrorDomain, code: GIDSignInError.canceled.rawValue)
        #expect(FirebaseAuthService.googleSignInError(from: error) == .cancelled)
    }

    @Test func urlErrorsAreNetworkErrors() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(FirebaseAuthService.googleSignInError(from: error) == .network)
    }

    @Test func underlyingUrlErrorIsANetworkError() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let error = NSError(domain: kGIDSignInErrorDomain, code: GIDSignInError.unknown.rawValue,
                            userInfo: [NSUnderlyingErrorKey: underlying])
        #expect(FirebaseAuthService.googleSignInError(from: error) == .network)
    }

    @Test func otherErrorsGetAFrenchMessage() {
        let error = NSError(domain: "SDK", code: 42, userInfo: [NSLocalizedDescriptionKey: "Raw SDK text"])
        guard case .failed(let message) = FirebaseAuthService.googleSignInError(from: error) else {
            Issue.record("Une erreur inconnue doit devenir .failed")
            return
        }
        #expect(!message.contains("Raw SDK text"))
    }
}
#endif
