import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct AMCMobileApp: App {
    // Créé dans init(), APRÈS la configuration de Firebase : jamais d'initialiseur de propriété qui touche Firebase.
    @State private var session: SessionViewModel

    init() {
        let firebaseReady = FirebaseSetup.configureIfAvailable()
        _session = State(initialValue: SessionViewModel(auth: FirebaseSetup.makeAuthService(firebaseReady: firebaseReady)))
    }

    var body: some Scene {
        WindowGroup {
            SessionGate(session: session)
                #if canImport(GoogleSignIn)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
                #endif
        }
    }
}
