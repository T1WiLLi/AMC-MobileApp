import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Démarrage de Firebase (B-012) et choix des implémentations.
/// - Sans SDK lié (B-011 pas encore fait) ou sans `GoogleService-Info.plist` (repo cloné, CI) :
///   l'app tourne sur les fakes au lieu de planter.
enum FirebaseSetup {
    /// true si Firebase a été configuré. À appeler une seule fois, au tout début de `App.init()`.
    @discardableResult
    static func configureIfAvailable() -> Bool {
        #if canImport(FirebaseCore)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("⚠️ GoogleService-Info.plist absent : services fake (voir docs/firebase.md).")
            return false
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        return true
        #else
        return false
        #endif
    }

    /// Service d'authentification : Firebase + Google si disponible, sinon fake.
    static func makeAuthService(firebaseReady: Bool) -> AuthService {
        #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        if firebaseReady { return FirebaseAuthService() }
        #endif
        return FakeAuthService()
    }
}
