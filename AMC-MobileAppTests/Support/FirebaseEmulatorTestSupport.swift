// FirebaseEmulatorTestSupport.swift
// Support des tests d'intégration sur l'émulateur Firebase local (B-013).
//
// Lancer les émulateurs (projet local demo-grenier) :
//     npx -y firebase-tools@latest emulators:start --only auth,firestore,storage --project demo-grenier
// Un test (ou une suite) marqué `.firestoreEmulator` est sauté si l'émulateur Firestore ne répond pas
// (CI, Mac sans émulateur). Vider la base entre deux tests avec `clearFirestore()`.
//
//     @MainActor @Suite(.serialized, .firestoreEmulator)
//     struct FirestoreOfferRepositoryTests {
//         @Test func vendorWritesFamilyReads() async throws {
//             try await FirebaseEmulatorTestSupport.clearFirestore()
//             let vendor = try FirebaseEmulatorTestSupport.session("vendor")   // Auth + Firestore du compte vendeur
//             let family = try FirebaseEmulatorTestSupport.session("family")   // second compte, session indépendante
//             let repo = FirestoreOfferRepository(firestore: vendor.firestore, auth: vendor.auth)
//             ...
//         }
//     }

import Foundation
import Testing
@testable import AMC_MobileApp

@MainActor
enum FirebaseEmulatorTestSupport {
    static let config = FirebaseEmulatorConfig()
    static var host: String { config.host }
    /// `demo-grenier` : un projet `demo-` n'a aucune ressource réelle.
    static var projectID: String { config.projectID }

    nonisolated static var firestoreBaseURL: URL { URL(string: "http://127.0.0.1:8080")! }
    nonisolated static var authBaseURL: URL { URL(string: "http://127.0.0.1:9099")! }

    /// Racine REST des documents de la base `(default)` de l'émulateur.
    static var documentsURL: URL {
        firestoreBaseURL.appending(path: "v1/projects/\(projectID)/databases/(default)/documents")
    }

    /// true si l'émulateur Firestore répond sur 127.0.0.1:8080 (délai court : pas d'attente en CI).
    nonisolated static func isFirestoreRunning(timeout: TimeInterval = 1) async -> Bool {
        let request = URLRequest(url: firestoreBaseURL, timeoutInterval: timeout)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
    /// Session Firebase indépendante (app nommée) sur l'émulateur : `auth`, `firestore`, `projectID`, `host`.
    /// Deux noms différents = deux comptes connectés en même temps. Lève une erreur si la cible n'est pas l'émulateur.
    static func session(_ name: String) throws -> FirebaseEmulatorSession {
        try FirebaseEmulatorSession.make(name: "test-\(name)", config: config)
    }
    #endif

    /// Supprime tous les documents de l'émulateur Firestore.
    static func clearFirestore() async throws {
        let url = firestoreBaseURL.appending(path: "emulator/v1/projects/\(projectID)/databases/(default)/documents")
        try expectSuccess(await send(method: "DELETE", to: url))
    }

    /// Supprime tous les comptes de l'émulateur Auth.
    static func clearAuth() async throws {
        try expectSuccess(await send(method: "DELETE", to: authBaseURL.appending(path: "emulator/v1/projects/\(projectID)/accounts")))
    }

    /// Requête REST vers l'émulateur. `Authorization: Bearer owner` contourne les règles de sécurité
    /// (pratique pour préparer des données de test) ; ne l'utilisez pas pour tester les règles.
    /// Garde : refuse toute URL qui ne vise pas l'émulateur local.
    @discardableResult
    static func send(method: String, to url: URL, json: Data? = nil, asOwner: Bool = true) async throws -> (Data, HTTPURLResponse) {
        guard url.scheme == "http", let urlHost = url.host(), FirebaseEmulatorConfig.isLocalHost(urlHost) else {
            throw EmulatorError.notEmulator(url)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = method
        if asOwner { request.setValue("Bearer owner", forHTTPHeaderField: "Authorization") }
        if let json {
            request.httpBody = json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EmulatorError.noHTTPResponse }
        return (data, http)
    }

    private static func expectSuccess(_ result: (Data, HTTPURLResponse)) throws {
        guard (200..<300).contains(result.1.statusCode) else {
            throw EmulatorError.status(result.1.statusCode, String(decoding: result.0, as: UTF8.self))
        }
    }

    enum EmulatorError: Error {
        case notEmulator(URL)
        case noHTTPResponse
        case status(Int, String)
    }
}

extension Trait where Self == ConditionTrait {
    /// Ne lance le test que si l'émulateur Firestore tourne sur 127.0.0.1:8080.
    static var firestoreEmulator: Self {
        .enabled("Émulateur Firestore lancé sur 127.0.0.1:8080") { await FirebaseEmulatorTestSupport.isFirestoreRunning() }
    }
}
