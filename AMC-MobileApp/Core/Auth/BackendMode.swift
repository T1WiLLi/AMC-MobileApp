// BackendMode.swift
// Choix du backend au lancement (B-013, RQ-003) : fakes, émulateur Firebase local ou projet de démo.
// Logique pure (sans Firebase ni réseau) pour être testée ; l'application des réglages est dans `FirebaseSetup`.

import Foundation

/// Backend utilisé par l'app pendant toute la session.
nonisolated enum BackendMode: String, Sendable, CaseIterable, CustomStringConvertible {
    /// Dépôts et authentification en mémoire (CI, previews, pas de `GoogleService-Info.plist`).
    case fake
    /// Firebase sur les émulateurs locaux (Auth 9099, Firestore 8080, Storage 9199).
    case emulator
    /// Le vrai projet Firebase de démo `amc-2026-8ab03`.
    case demoProject

    /// true si l'app doit configurer Firebase (`FirebaseApp.configure()`).
    var usesFirebase: Bool { self != .fake }

    var description: String {
        switch self {
        case .fake: "fake (données en mémoire)"
        case .emulator: "émulateur Firebase local"
        case .demoProject: "projet Firebase de démo"
        }
    }

    /// Règle de choix :
    /// 1. pas de config Firebase (plist absent ou SDK non lié) → `.fake` ;
    /// 2. build Release → toujours `.demoProject` (les arguments de lancement sont ignorés) ;
    /// 3. `-useFakeBackend YES` → `.fake` (prioritaire sur l'émulateur) ;
    /// 4. `-useFirebaseEmulator YES` → `.emulator` ;
    /// 5. sinon → `.demoProject`.
    static func resolve(hasFirebaseConfig: Bool, options: BackendLaunchOptions, isDebugBuild: Bool) -> BackendMode {
        guard hasFirebaseConfig else { return .fake }
        guard isDebugBuild else { return .demoProject }
        if options.useFakeBackend { return .fake }
        if options.useFirebaseEmulator { return .emulator }
        return .demoProject
    }
}

/// Hôte et ports des émulateurs (identiques à `firebase.json`).
nonisolated struct FirebaseEmulatorConfig: Sendable, Equatable {
    /// `127.0.0.1` marche sur le simulateur. Sur un iPhone réel, mettre l'IP du Mac (`-firebaseEmulatorHost 192.168.x.y`)
    /// et lancer les émulateurs avec `"host": "0.0.0.0"`.
    var host: String = "127.0.0.1"
    var authPort: Int = 9099
    var firestorePort: Int = 8080
    var storagePort: Int = 9199
}

/// Options lues au lancement : arguments (`-clé valeur`, comme `UserDefaults`) puis variables d'environnement.
nonisolated struct BackendLaunchOptions: Sendable, Equatable {
    static let fakeBackendArgument = "-useFakeBackend"
    static let firebaseEmulatorArgument = "-useFirebaseEmulator"
    static let emulatorHostArgument = "-firebaseEmulatorHost"
    static let fakeBackendVariable = "USE_FAKE_BACKEND"
    static let firebaseEmulatorVariable = "USE_FIREBASE_EMULATOR"
    static let emulatorHostVariable = "FIREBASE_EMULATOR_HOST"

    var useFakeBackend = false
    var useFirebaseEmulator = false
    var emulator = FirebaseEmulatorConfig()

    init(useFakeBackend: Bool = false, useFirebaseEmulator: Bool = false, emulator: FirebaseEmulatorConfig = .init()) {
        self.useFakeBackend = useFakeBackend
        self.useFirebaseEmulator = useFirebaseEmulator
        self.emulator = emulator
    }

    /// Un argument présent l'emporte sur la variable d'environnement du même réglage.
    init(arguments: [String], environment: [String: String]) {
        useFakeBackend = Self.flag(Self.fakeBackendArgument, in: arguments)
            ?? Self.isTruthy(environment[Self.fakeBackendVariable])
        useFirebaseEmulator = Self.flag(Self.firebaseEmulatorArgument, in: arguments)
            ?? Self.isTruthy(environment[Self.firebaseEmulatorVariable])
        let host = Self.value(Self.emulatorHostArgument, in: arguments) ?? environment[Self.emulatorHostVariable]
        if let host, !host.trimmingCharacters(in: .whitespaces).isEmpty {
            emulator.host = host.trimmingCharacters(in: .whitespaces)
        }
    }

    /// `-clé YES|1|true` → true, `-clé NO|0|false` → false, `-clé` seul → true, absent → nil.
    private static func flag(_ name: String, in arguments: [String]) -> Bool? {
        guard let index = arguments.lastIndex(of: name) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("-") else { return true }
        return isTruthy(arguments[next])
    }

    private static func value(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: name) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].hasPrefix("-") else { return nil }
        return arguments[next]
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["yes", "1", "true"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
