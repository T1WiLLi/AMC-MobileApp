// FirebaseEmulator.swift
// Support des tests d'intégration sur l'émulateur Firebase local (B-013).
//
// Lancer les émulateurs : `npx -y firebase-tools@latest emulators:start --only auth,firestore,storage`
// Un test (ou une suite) marqué `.firestoreEmulator` est sauté si l'émulateur Firestore ne répond pas
// (CI, Mac sans émulateur). Vider la base entre deux tests avec `try await FirebaseEmulator.clearFirestore()`.
//
//     @Suite(.serialized, .firestoreEmulator)
//     struct FirestoreOfferRepositoryTests {
//         @Test func saveThenRead() async throws {
//             try await FirebaseEmulator.clearFirestore()
//             ...
//         }
//     }

import Foundation
import Testing

enum FirebaseEmulator {
    static let host = "127.0.0.1"
    static let projectID = "amc-2026-8ab03"
    static let authPort = 9099
    static let firestorePort = 8080
    static let storagePort = 9199

    static var firestoreBaseURL: URL { URL(string: "http://\(host):\(firestorePort)")! }
    static var authBaseURL: URL { URL(string: "http://\(host):\(authPort)")! }

    /// Racine REST des documents de la base `(default)` de l'émulateur.
    static var documentsURL: URL {
        firestoreBaseURL.appending(path: "v1/projects/\(projectID)/databases/(default)/documents")
    }

    /// true si l'émulateur Firestore répond sur 127.0.0.1:8080 (délai court : pas d'attente en CI).
    static func isFirestoreRunning(timeout: TimeInterval = 1) async -> Bool {
        let request = URLRequest(url: firestoreBaseURL, timeoutInterval: timeout)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Supprime tous les documents de l'émulateur Firestore.
    static func clearFirestore() async throws {
        let url = firestoreBaseURL.appending(path: "emulator/v1/projects/\(projectID)/databases/(default)/documents")
        try await expectSuccess(send(method: "DELETE", to: url))
    }

    /// Supprime tous les comptes de l'émulateur Auth.
    static func clearAuth() async throws {
        try await expectSuccess(send(method: "DELETE", to: authBaseURL.appending(path: "emulator/v1/projects/\(projectID)/accounts")))
    }

    /// Requête REST vers l'émulateur. `Authorization: Bearer owner` contourne les règles de sécurité
    /// (pratique pour préparer des données de test) ; ne l'utilisez pas pour tester les règles.
    @discardableResult
    static func send(method: String, to url: URL, json: Data? = nil, asOwner: Bool = true) async throws -> (Data, HTTPURLResponse) {
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
        case noHTTPResponse
        case status(Int, String)
    }
}

extension Trait where Self == ConditionTrait {
    /// Ne lance le test que si l'émulateur Firestore tourne sur 127.0.0.1:8080.
    static var firestoreEmulator: Self {
        .enabled("Émulateur Firestore lancé sur 127.0.0.1:8080") { await FirebaseEmulator.isFirestoreRunning() }
    }
}
