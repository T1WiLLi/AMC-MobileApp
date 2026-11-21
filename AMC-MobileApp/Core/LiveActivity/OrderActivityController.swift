// OrderActivityController.swift
// Démarre, met à jour et termine la Live Activity d'une commande (RQ-085), localement depuis l'app :
// pas de serveur, pas de push. Le mode démo enchaîne les étapes pour la présentation au jury.

import ActivityKit
import Foundation
import Observation
import UIKit

/// Accès à ActivityKit, derrière un protocole pour tester le contrôleur sans système.
@MainActor
protocol LiveActivityClient {
    var areActivitiesEnabled: Bool { get }
    /// Démarre une activité et rend son identifiant.
    func request(attributes: GrenierOrderAttributes, state: GrenierOrderAttributes.ContentState) throws -> String
    func update(id: String, state: GrenierOrderAttributes.ContentState, alert: (title: String, body: String)?) async
    func end(id: String, state: GrenierOrderAttributes.ContentState?) async
    /// Termine toutes les activités Grenier encore ouvertes (relance de l'app, nouvelle démo).
    func endAll() async
}

/// Implémentation réelle, sur ActivityKit.
struct ActivityKitClient: LiveActivityClient {
    typealias OrderActivity = Activity<GrenierOrderAttributes>

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func request(attributes: GrenierOrderAttributes, state: GrenierOrderAttributes.ContentState) throws -> String {
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)
        return try OrderActivity.request(attributes: attributes, content: content, pushType: nil).id
    }

    func update(id: String, state: GrenierOrderAttributes.ContentState, alert: (title: String, body: String)?) async {
        await Self.updateActivity(id: id, state: state, alertTitle: alert?.title, alertBody: alert?.body)
    }

    func end(id: String, state: GrenierOrderAttributes.ContentState?) async {
        await Self.endActivities(id: id, state: state)
    }

    func endAll() async {
        await Self.endActivities(id: nil, state: nil)
    }

    // `Activity` n'est pas Sendable : on la cherche et on l'utilise dans le même contexte non isolé,
    // sans jamais la faire passer par le MainActor.
    @concurrent
    private nonisolated static func updateActivity(
        id: String, state: GrenierOrderAttributes.ContentState, alertTitle: String?, alertBody: String?
    ) async {
        guard let activity = OrderActivity.activities.first(where: { $0.id == id }) else { return }
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)
        if let alertTitle, let alertBody {
            let configuration = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: alertTitle),
                body: LocalizedStringResource(stringLiteral: alertBody),
                sound: .default
            )
            await activity.update(content, alertConfiguration: configuration)
        } else {
            await activity.update(content)
        }
    }

    /// Termine l'activité `id` avec son dernier état, ou toutes les activités immédiatement si `id` est nil.
    @concurrent
    private nonisolated static func endActivities(id: String?, state: GrenierOrderAttributes.ContentState?) async {
        for activity in OrderActivity.activities where id == nil || activity.id == id {
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: id == nil ? .immediate : .default)
        }
    }
}

/// Pilote la Live Activity de la commande en cours. Une seule activité à la fois.
@MainActor
@Observable
final class OrderActivityController {
    /// Instance de l'app (le bouton de démo et l'argument de lancement s'en servent).
    static let shared = OrderActivityController()

    private(set) var attributes: GrenierOrderAttributes?
    private(set) var state: GrenierOrderAttributes.ContentState?
    private(set) var isDemoRunning = false
    /// Dernière erreur à montrer (Activités en direct désactivées, refus du système).
    var error: AppError?

    var isActive: Bool { activityID != nil }

    @ObservationIgnored private var activityID: String?
    @ObservationIgnored private var demoTask: Task<Void, Never>?
    @ObservationIgnored private let client: any LiveActivityClient

    init(client: any LiveActivityClient = ActivityKitClient()) {
        self.client = client
    }

    /// Démarre l'activité (remplace celle en cours). Lance `AppError.liveActivitiesDisabled`
    /// si l'utilisateur a coupé les Activités en direct pour Grenier.
    func start(
        attributes: GrenierOrderAttributes = .demo,
        state: GrenierOrderAttributes.ContentState = .demo(.ouverte)
    ) async throws(AppError) {
        guard client.areActivitiesEnabled else {
            error = .liveActivitiesDisabled
            throw .liveActivitiesDisabled
        }
        stopDemo()
        await client.endAll()
        do {
            activityID = try client.request(attributes: attributes, state: state)
        } catch {
            let appError = AppError.unknown("Live Activity refusée : \(error)")
            self.error = appError
            throw appError
        }
        self.attributes = attributes
        self.state = state
        error = nil
    }

    /// Passe à un nouvel état ; une alerte allume la Dynamic Island aux étapes clés.
    func update(to newState: GrenierOrderAttributes.ContentState) async {
        guard let activityID, let attributes else { return }
        state = newState
        let alert = OrderActivityPresentation(attributes, newState).alert
        await client.update(id: activityID, state: newState, alert: alert)
    }

    /// Termine l'activité (elle reste un moment sur l'écran verrouillé avec son dernier état).
    func end() async {
        stopDemo()
        guard let activityID else { return }
        await client.end(id: activityID, state: state.map { var final = $0; final.stage = .recuperee; return final })
        self.activityID = nil
        attributes = nil
        state = nil
    }

    // MARK: - Mode démo

    /// Démarre l'activité de démo puis enchaîne palier franchi → en route → arrivée toutes les `stepInterval`.
    func startDemo(stepInterval: Duration = .seconds(5)) async throws(AppError) {
        let pickupTime = GrenierOrderAttributes.demoPickupTime()
        let stages = GrenierOrderAttributes.ContentState.demoSequence
        try await start(attributes: .demo, state: .demo(stages[0], pickupTime: pickupTime))
        isDemoRunning = true
        // Le jury verrouille l'iPhone juste après le lancement : on demande un peu de temps en arrière-plan
        // pour que l'enchaînement (≈ 15 s) continue app fermée. Sans serveur, pas d'autre moyen.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "GrenierLiveActivityDemo")
        demoTask = Task { [weak self] in
            defer { UIApplication.shared.endBackgroundTask(backgroundTask) }
            for stage in stages.dropFirst() {
                try? await Task.sleep(for: stepInterval)
                guard !Task.isCancelled, let self else { return }
                await self.update(to: .demo(stage, pickupTime: pickupTime))
            }
            self?.isDemoRunning = false
        }
    }

    /// Attend la fin de l'enchaînement de démo (tests).
    func waitForDemo() async { await demoTask?.value }

    func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        isDemoRunning = false
    }
}
