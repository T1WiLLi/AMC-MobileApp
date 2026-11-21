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
    }

    var body: some Scene {
        WindowGroup {
            SessionGate(session: session)
                .appLock(appLock)
                #if canImport(GoogleSignIn)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
                #endif
                #if DEBUG
                // Démo jury : `-GrenierLiveActivityDemo` au lancement démarre la Live Activity
                // et enchaîne palier franchi → en route → arrivée (OrderActivityController).
                // `-GrenierLiveActivityDemoStep 8` règle l'intervalle entre les étapes (5 s par défaut).
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("-GrenierLiveActivityDemo") else { return }
                    let step = UserDefaults.standard.integer(forKey: "GrenierLiveActivityDemoStep")
                    try? await OrderActivityController.shared.startDemo(stepInterval: .seconds(step > 0 ? step : 5))
                }
                #endif
        }
    }
}
