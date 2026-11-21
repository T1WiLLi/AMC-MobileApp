// AppRepositories+Cache.swift
// Enveloppe les dépôts lus souvent et suivis en temps réel dans un cache mémoire (T-112).

import Foundation

nonisolated extension AppRepositories {
    /// Mêmes dépôts, avec un cache mémoire (durée de vie `ttl` secondes) sur les groupes, lots et commandes groupées.
    /// Les snapshots temps réel remplacent les entrées du cache. Les autres dépôts sont gardés tels quels.
    func cached(ttl: TimeInterval = 60) -> AppRepositories {
        cached(by: RepositoryCache(ttl: ttl))
    }

    /// Variante qui partage un cache existant (tests, horloge injectée, `invalidateAll()` à la déconnexion).
    func cached(by cache: RepositoryCache) -> AppRepositories {
        var repositories = self
        repositories.groups = CachedGroupRepository(base: groups, cache: cache)
        repositories.offers = CachedOfferRepository(base: offers, cache: cache)
        repositories.groupOrders = CachedGroupOrderRepository(base: groupOrders, cache: cache)
        return repositories
    }
}
