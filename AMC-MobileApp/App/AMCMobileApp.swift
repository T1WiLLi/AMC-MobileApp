import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct AMCMobileApp: App {
    // Créé dans init(), APRÈS la configuration de Firebase : jamais d'initialiseur de propriété qui touche Firebase.
    @State private var session: SessionViewModel
    @State private var appLock = AppLock()

    init() {
        let firebaseReady = FirebaseSetup.configureIfAvailable()
        _session = State(initialValue: SessionViewModel(auth: FirebaseSetup.makeAuthService(firebaseReady: firebaseReady)))
        // Démo : -resetOnboarding rejoue l'accueil, -demoFamilyPortal rouvre côté Familles. Ne touche pas Firebase.
        OnboardingKeys.applyLaunchArguments(ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup {
            SessionGate(session: session)
                .appLock(appLock)
                #if canImport(GoogleSignIn)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
                #endif
        }
    }
}
