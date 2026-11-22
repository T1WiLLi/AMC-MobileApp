// ReportRepository.swift
// Dépôt des signalements (T-106). Implémentation fake en mémoire seulement : pas de collection
// Firestore ni de propriété dans `AppRepositories` tant que ce n'est pas annoncé sur le board.

import Foundation
import SwiftUI

nonisolated protocol ReportRepository: Sendable {
    /// Enregistre un signalement.
    func submit(_ report: Report) async throws
    /// Signalements déjà envoyés pour une cible (le plus récent en premier).
    func reports(for target: ReportTarget) async throws -> [Report]
}

/// Signalements gardés en mémoire, avec latence et mode erreur (`FakeBehavior`).
actor InMemoryReportRepository: ReportRepository {
    /// Dépôt partagé par défaut de `.reportable(target:)` (démo).
    static let shared = InMemoryReportRepository(behavior: .demo)

    private let behavior: FakeBehavior
    private(set) var all: [Report] = []

    init(behavior: FakeBehavior = .instant, reports: [Report] = []) {
        self.behavior = behavior
        self.all = reports
    }

    func submit(_ report: Report) async throws {
        try await behavior.simulate()
        all.append(report)
    }

    func reports(for target: ReportTarget) async throws -> [Report] {
        try await behavior.simulate()
        return all.filter { $0.target == target }.sorted { $0.createdAt > $1.createdAt }
    }
}

extension EnvironmentValues {
    /// Dépôt utilisé par `.reportable(target:)` ; remplace-le avec `.environment(\.reportRepository, …)`.
    @Entry var reportRepository: any ReportRepository = InMemoryReportRepository.shared
}
