import Foundation
import OSLog
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

/// Démarrage de Firebase (B-012), choix du backend (B-013) et des implémentations.
/// - Sans SDK lié ou sans `GoogleService-Info.plist` (repo cloné, CI) : l'app tourne sur les fakes au lieu de planter.
/// - Tout réglage d'émulateur est appliqué ICI, juste après `FirebaseApp.configure()` et avant tout autre appel à
///   `Auth.auth()`, `Firestore.firestore()` ou `Storage.storage()` (sinon Firebase plante).
enum FirebaseSetup {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AMC-MobileApp", category: "Backend")

    /// Mode retenu au lancement (`.fake` tant que `configure()` n'a pas été appelé).
    private(set) static var mode: BackendMode = .fake
    private static var isConfigured = false

    /// true si le SDK est lié et que `GoogleService-Info.plist` est dans le bundle.
    static var hasFirebaseConfig: Bool {
        #if canImport(FirebaseCore)
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        #else
        false
        #endif
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Choisit le mode, configure Firebase (et les émulateurs) si besoin, et l'écrit dans le log.
    /// À appeler une seule fois, au tout début de `App.init()` ; les appels suivants renvoient le premier mode.
    @discardableResult
    static func configure(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BackendMode {
        if isConfigured { return mode }
        isConfigured = true

        let options = BackendLaunchOptions(arguments: arguments, environment: environment)
        let resolved = BackendMode.resolve(hasFirebaseConfig: hasFirebaseConfig, options: options, isDebugBuild: isDebugBuild)
        mode = resolved

        #if canImport(FirebaseCore)
        if resolved.usesFirebase {
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
            if resolved == .emulator { connectToEmulators(options.emulator) }
        }
        #endif

        switch resolved {
        case .fake where !hasFirebaseConfig:
            logger.notice("Backend : \(resolved.description, privacy: .public) — GoogleService-Info.plist absent (voir docs/firebase.md).")
        case .emulator:
            let emulator = options.emulator
            logger.notice("Backend : \(resolved.description, privacy: .public) — \(emulator.host, privacy: .public) (Auth \(emulator.authPort), Firestore \(emulator.firestorePort), Storage \(emulator.storagePort)).")
        default:
            logger.notice("Backend : \(resolved.description, privacy: .public).")
        }
        return resolved
    }

    #if canImport(FirebaseCore)
    private static func connectToEmulators(_ config: FirebaseEmulatorConfig) {
        #if canImport(FirebaseAuth)
        Auth.auth().useEmulator(withHost: config.host, port: config.authPort)
        #endif
        #if canImport(FirebaseFirestore)
        // Cache en mémoire : les données de l'émulateur ne se mélangent pas au cache disque du projet de démo.
        let settings = Firestore.firestore().settings
        settings.host = "\(config.host):\(config.firestorePort)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        #endif
        #if canImport(FirebaseStorage)
        Storage.storage().useEmulator(withHost: config.host, port: config.storagePort)
        #endif
    }
    #endif

    /// Service d'authentification : Firebase + Google en mode émulateur ou démo, sinon fake.
    static func makeAuthService(mode: BackendMode) -> AuthService {
        #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        if mode.usesFirebase { return FirebaseAuthService() }
        #endif
        return FakeAuthService()
    }
}
