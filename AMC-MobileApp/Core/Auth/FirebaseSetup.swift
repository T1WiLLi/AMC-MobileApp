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
/// - En mode émulateur, l'app Firebase par défaut vise le projet local `demo-grenier`, et Auth, Firestore et Storage
///   sont pointés sur l'émulateur ICI, juste après `FirebaseApp.configure(options:)` et avant tout autre appel à
///   `Auth.auth()`, `Firestore.firestore()` ou `Storage.storage()` (sinon Firebase plante).
enum FirebaseSetup {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AMC-MobileApp", category: "Backend")

    /// Mode retenu au lancement (`.fake` tant que `configure()` n'a pas été appelé).
    private(set) static var mode: BackendMode = .fake
    /// Réglages d'émulateur utilisés au lancement (projet, hôte, ports).
    private(set) static var emulatorConfig = FirebaseEmulatorConfig()
    private static var isConfigured = false

    static var sdkAvailable: Bool {
        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        true
        #else
        false
        #endif
    }

    static var configFilePath: String? {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Compatibilité (B-012) : configure Firebase selon le mode choisi ; true si Firebase est actif (émulateur ou démo).
    @discardableResult
    static func configureIfAvailable() -> Bool {
        configure().usesFirebase
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
        let resolved = BackendMode.resolve(
            sdkAvailable: sdkAvailable,
            hasConfigFile: configFilePath != nil,
            options: options,
            isDebugBuild: isDebugBuild
        )
        mode = resolved
        emulatorConfig = options.emulator

        #if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        switch resolved {
        case .fake:
            break
        case .demoProject:
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
        case .emulator:
            if FirebaseApp.app() == nil {
                FirebaseApp.configure(options: emulatorOptions(options.emulator))
            }
            if let app = FirebaseApp.app() { PerfSignposts.measure("firebase.connect") { connect(app, to: options.emulator) } }
        }
        #endif

        switch resolved {
        case .fake where configFilePath == nil:
            logger.notice("Backend : \(resolved.description, privacy: .public) — GoogleService-Info.plist absent (voir docs/firebase.md).")
        case .emulator:
            let emulator = options.emulator
            logger.notice("Backend : \(resolved.description, privacy: .public) — projet \(emulator.projectID, privacy: .public) sur \(emulator.host, privacy: .public) (Auth \(emulator.authPort), Firestore \(emulator.firestorePort), Storage \(emulator.storagePort)).")
        default:
            logger.notice("Backend : \(resolved.description, privacy: .public).")
        }
        return resolved
    }

    /// Service d'authentification : Firebase + Google en mode émulateur ou démo, sinon fake.
    static func makeAuthService(mode: BackendMode) -> AuthService {
        #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        if mode.usesFirebase { return FirebaseAuthService() }
        #endif
        return FakeAuthService()
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
extension FirebaseSetup {
    /// Options d'une app Firebase pour l'émulateur : celles du plist s'il est là (le client Google reste utilisable),
    /// sinon des valeurs factices ; dans les deux cas le projet est forcé à `config.projectID` (`demo-grenier`).
    static func emulatorOptions(_ config: FirebaseEmulatorConfig) -> FirebaseOptions {
        let options: FirebaseOptions
        if let path = configFilePath, let fromFile = FirebaseOptions(contentsOfFile: path) {
            options = fromFile
        } else {
            options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000000", gcmSenderID: "000000000000")
            options.apiKey = "ADemoGrenierEmulatorOnly000000000000000"
            options.bundleID = Bundle.main.bundleIdentifier ?? "ca.amc2026.mobileapp"
        }
        options.projectID = config.projectID
        options.storageBucket = "\(config.projectID).appspot.com"
        return options
    }

    /// Pointe Auth, Firestore et Storage de `app` sur l'émulateur. À appeler une seule fois par app,
    /// avant tout autre usage de ses clients.
    static func connect(_ app: FirebaseApp, to config: FirebaseEmulatorConfig) {
        Auth.auth(app: app).useEmulator(withHost: config.host, port: config.authPort)
        // Cache en mémoire : les données de l'émulateur ne se mélangent pas au cache disque du projet de démo.
        let firestore = Firestore.firestore(app: app)
        let settings = firestore.settings
        settings.host = "\(config.host):\(config.firestorePort)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        firestore.settings = settings
        #if canImport(FirebaseStorage)
        Storage.storage(app: app).useEmulator(withHost: config.host, port: config.storagePort)
        #endif
    }

    /// true si ce Firestore vise un émulateur local d'un projet `demo-` (garde pour les tests).
    static func isEmulatorTarget(_ firestore: Firestore) -> Bool {
        let settings = firestore.settings
        let host = settings.host.split(separator: ":").dropLast().joined(separator: ":")
        let target = FirebaseEmulatorConfig(projectID: firestore.app.options.projectID ?? "", host: host)
        return !settings.isSSLEnabled && target.isSafeEmulatorTarget
    }
}
#endif
