// NeedsPlanStore.swift
// Stockage local du plan mensuel (T-105, RQ-099). Pas de collection Firestore : le plan reste sur l'appareil.
//
//     let store: any NeedsPlanStore = UserDefaultsNeedsPlanStore()   // app
//     let store: any NeedsPlanStore = InMemoryNeedsPlanStore()       // previews, tests

import Foundation

/// Lit et écrit le plan d'un ménage.
nonisolated protocol NeedsPlanStore: Sendable {
    /// Plan enregistré, nil si le ménage n'en a pas encore.
    func plan(forHousehold householdId: String) -> MonthlyNeedsPlan?
    func save(_ plan: MonthlyNeedsPlan, forHousehold householdId: String)
}

/// Plan encodé en JSON dans `UserDefaults`, une clé par ménage.
nonisolated struct UserDefaultsNeedsPlanStore: NeedsPlanStore, @unchecked Sendable {
    // UserDefaults est thread-safe ; il n'est simplement pas marqué Sendable.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(forHousehold householdId: String) -> String { "needsPlan.\(householdId)" }

    func plan(forHousehold householdId: String) -> MonthlyNeedsPlan? {
        guard let data = defaults.data(forKey: Self.key(forHousehold: householdId)) else { return nil }
        return try? JSONDecoder().decode(MonthlyNeedsPlan.self, from: data)
    }

    func save(_ plan: MonthlyNeedsPlan, forHousehold householdId: String) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: Self.key(forHousehold: householdId))
    }
}

/// Plans en mémoire (previews et tests).
nonisolated final class InMemoryNeedsPlanStore: NeedsPlanStore, @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [String: MonthlyNeedsPlan]

    init(plans: [String: MonthlyNeedsPlan] = [:]) {
        self.plans = plans
    }

    func plan(forHousehold householdId: String) -> MonthlyNeedsPlan? {
        lock.withLock { plans[householdId] }
    }

    func save(_ plan: MonthlyNeedsPlan, forHousehold householdId: String) {
        lock.withLock { plans[householdId] = plan }
    }
}
