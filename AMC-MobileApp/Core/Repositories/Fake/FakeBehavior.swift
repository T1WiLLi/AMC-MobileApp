// FakeBehavior.swift
// Latence simulée et mode erreur des dépôts fake.

import Foundation

nonisolated struct FakeBehavior: Sendable {
    /// Délai simulé avant chaque réponse, en millisecondes ; `nil` = immédiat.
    var latencyMilliseconds: ClosedRange<Int>?
    /// Si non nil, chaque appel lève cette erreur (après la latence).
    var failure: AppError?

    /// Previews et démo : 300 à 800 ms, comme un vrai réseau.
    static let realistic = FakeBehavior(latencyMilliseconds: 300...800, failure: nil)
    /// App en mode `-useFakeData` (démo du jury) : 5 à 25 ms par appel. Un écran enchaîne plusieurs appels ;
    /// avec `realistic`, la Cueillette attendait 5 à 7 s, la carte Demande 3 s et l'Accueil 2 s. Ici, moins
    /// de 300 ms par écran, et les états de chargement existent encore (une image ou deux).
    static let demo = FakeBehavior(latencyMilliseconds: 5...25, failure: nil)
    /// Tests : aucune attente.
    static let instant = FakeBehavior(latencyMilliseconds: nil, failure: nil)
    /// État d'erreur, par exemple pour une preview hors ligne.
    static func failing(_ error: AppError = .offline) -> FakeBehavior {
        FakeBehavior(latencyMilliseconds: nil, failure: error)
    }

    /// Attend la latence, puis lève l'erreur configurée s'il y en a une.
    func simulate() async throws {
        if let latencyMilliseconds {
            try await Task.sleep(for: .milliseconds(Int.random(in: latencyMilliseconds)))
        }
        if let failure { throw failure }
    }
}

/// Diffuse les mises à jour d'un document à ses écouteurs (temps réel simulé).
nonisolated struct FakeBroadcaster<Value: Sendable>: Sendable {
    private var continuations: [String: [UUID: AsyncThrowingStream<Value, any Error>.Continuation]] = [:]

    mutating func add(_ continuation: AsyncThrowingStream<Value, any Error>.Continuation, for id: String) -> UUID {
        let token = UUID()
        continuations[id, default: [:]][token] = continuation
        return token
    }

    mutating func remove(token: UUID, for id: String) {
        continuations[id]?[token] = nil
    }

    func send(_ value: Value, for id: String) {
        continuations[id]?.values.forEach { $0.yield(value) }
    }
}
