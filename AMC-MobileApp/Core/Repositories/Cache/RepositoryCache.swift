// RepositoryCache.swift
// Cache mémoire des dépôts, invalidé par les snapshots temps réel (T-112, S-10 / S-05).
// Sans serveur : les décorateurs `Cached*Repository` lisent ici avant d'appeler le dépôt sous-jacent,
// et chaque snapshot d'`observe…` remplace l'entrée concernée.

import Foundation

/// Clé d'une entrée du cache : une lecture d'un dépôt et ses paramètres.
nonisolated enum CacheKey: Hashable, Sendable {
    // Lots
    case offer(String)
    case activeOffers(zone: String?)
    case offersOfVendor(String)
    // Groupes
    case group(String)
    case groupsInNeighborhood(String?)
    case groupsOfHousehold(String)
    case members(ofGroup: String)
    // Commandes groupées
    case groupOrder(String)
    case groupOrdersOfGroup(String)
    case groupOrdersOfOffer(String)
    case shares(ofGroupOrder: String)
}

/// Stockage clé → valeur datée, avec durée de vie (TTL) et flux des clés remplacées ou retirées.
actor RepositoryCache {
    private struct Entry {
        var value: any Sendable
        var storedAt: Date
    }

    /// Durée de vie d'une entrée, en secondes.
    let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [CacheKey: Entry] = [:]
    /// Incrémenté à chaque écriture d'une clé : une lecture lancée avant un snapshot n'écrase pas celui-ci.
    private var versions: [CacheKey: Int] = [:]
    private var subscribers: [UUID: AsyncStream<CacheKey>.Continuation] = [:]

    init(ttl: TimeInterval = 60, now: @escaping @Sendable () -> Date = { .now }) {
        self.ttl = ttl
        self.now = now
    }

    /// Valeur en cache si elle existe, est du bon type et n'a pas expiré.
    func value<Value: Sendable>(for key: CacheKey, as type: Value.Type = Value.self) -> Value? {
        guard let entry = entries[key] else { return nil }
        guard now().timeIntervalSince(entry.storedAt) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.value as? Value
    }

    /// Remplace l'entrée et l'annonce dans `changes()`.
    func store<Value: Sendable>(_ value: Value, for key: CacheKey) {
        entries[key] = Entry(value: value, storedAt: now())
        bump(key)
    }

    func invalidate(_ key: CacheKey) {
        entries[key] = nil
        bump(key)
    }

    /// Retire toutes les entrées dont la clé satisfait `predicate` (ex. tous les fils `activeOffers`).
    func invalidate(where predicate: (CacheKey) -> Bool) {
        // `versions` connaît aussi les clés en cours de chargement.
        for key in versions.keys where predicate(key) {
            invalidate(key)
        }
    }

    func invalidateAll() {
        for key in versions.keys {
            invalidate(key)
        }
    }

    /// Clés remplacées ou retirées, à partir de l'abonnement.
    func changes() -> AsyncStream<CacheKey> {
        let (stream, continuation) = AsyncStream<CacheKey>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let token = UUID()
        subscribers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(token) }
        }
        return stream
    }

    // MARK: Aides pour les décorateurs

    /// Valeur en cache, sinon `load()` puis mise en cache (sauf si la clé a changé pendant le chargement).
    func cached<Value: Sendable>(
        _ key: CacheKey, load: @Sendable () async throws -> Value
    ) async throws -> Value {
        if let hit: Value = value(for: key) { return hit }
        let version = versions[key, default: 0]
        versions[key] = version
        let loaded = try await load()
        if versions[key, default: 0] == version {
            store(loaded, for: key)
        } else if let fresher: Value = value(for: key) {
            return fresher
        }
        return loaded
    }

    /// Remplace `element` dans chaque liste en cache de clé `matching` qui le contient déjà.
    func replaceInLists<Element: Identifiable & Sendable>(
        _ element: Element, matching predicate: (CacheKey) -> Bool
    ) {
        for (key, entry) in entries where predicate(key) {
            guard var list = entry.value as? [Element],
                  let index = list.firstIndex(where: { $0.id == element.id }) else { continue }
            list[index] = element
            entries[key]?.value = list
            bump(key)
        }
    }

    private func bump(_ key: CacheKey) {
        versions[key, default: 0] += 1
        for continuation in subscribers.values {
            continuation.yield(key)
        }
    }

    private func unsubscribe(_ token: UUID) {
        subscribers[token] = nil
    }
}

/// Relaie un flux temps réel en appliquant `apply` à chaque snapshot avant de le ré-émettre.
nonisolated func relayingSnapshots<Value: Sendable>(
    of upstream: AsyncThrowingStream<Value, any Error>,
    apply: @escaping @Sendable (Value) async -> Void,
    onFailure: @escaping @Sendable () async -> Void
) -> AsyncThrowingStream<Value, any Error> {
    let (stream, continuation) = AsyncThrowingStream<Value, any Error>.makeStream()
    let task = Task {
        do {
            for try await value in upstream {
                await apply(value)
                continuation.yield(value)
            }
            continuation.finish()
        } catch {
            await onFailure()
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
}
