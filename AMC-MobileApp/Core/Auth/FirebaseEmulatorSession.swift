// FirebaseEmulatorSession.swift
// Sessions Firebase indépendantes sur l'émulateur (B-013, pour les tests d'intégration B-017 à B-019).
// Chaque session est une `FirebaseApp` nommée du projet `demo-grenier` : son Auth a son propre utilisateur connecté,
// ce qui permet de tester deux comptes en même temps (ex. un vendeur et une famille).
// Debug seulement : jamais compilé dans une build Release.

#if DEBUG && canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

enum FirebaseEmulatorSessionError: Error, Equatable {
    /// Cible refusée : hôte non local ou projet sans préfixe `demo-`.
    case unsafeTarget(projectID: String, host: String)
    case invalidName(String)
}

struct FirebaseEmulatorSession {
    let name: String
    let config: FirebaseEmulatorConfig
    let app: FirebaseApp
    let auth: Auth
    let firestore: Firestore

    var projectID: String { config.projectID }
    var host: String { config.host }

    /// Crée (ou retrouve) l'app nommée `name`, pointée sur l'émulateur AVANT tout usage de ses clients.
    /// Refuse toute cible hors émulateur (`unsafeTarget`).
    static func make(name: String, config: FirebaseEmulatorConfig = .init()) throws -> FirebaseEmulatorSession {
        guard config.isSafeEmulatorTarget else {
            throw FirebaseEmulatorSessionError.unsafeTarget(projectID: config.projectID, host: config.host)
        }
        guard !name.isEmpty, name != "__FIRAPP_DEFAULT" else { throw FirebaseEmulatorSessionError.invalidName(name) }

        let app: FirebaseApp
        if let existing = FirebaseApp.app(name: name) {
            app = existing
        } else {
            FirebaseApp.configure(name: name, options: FirebaseSetup.emulatorOptions(config))
            guard let created = FirebaseApp.app(name: name) else { throw FirebaseEmulatorSessionError.invalidName(name) }
            FirebaseSetup.connect(created, to: config)
            app = created
        }

        let firestore = Firestore.firestore(app: app)
        guard FirebaseSetup.isEmulatorTarget(firestore) else {
            throw FirebaseEmulatorSessionError.unsafeTarget(projectID: app.options.projectID ?? "", host: firestore.settings.host)
        }
        return FirebaseEmulatorSession(name: name, config: config, app: app, auth: Auth.auth(app: app), firestore: firestore)
    }
}
#endif
