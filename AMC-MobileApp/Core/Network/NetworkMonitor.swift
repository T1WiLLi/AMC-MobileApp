import Foundation
import Network
import Observation
import SwiftUI

/// État du réseau et signal de rechargement automatique (S-10, T-090).
///
/// Créé une fois par l'app (`AMCMobileApp`) et injecté avec `.environment(network)`. Les écrans ne le lisent pas
/// directement : ils posent `.refreshOnForeground { … }` (voir `RefreshOnForeground.swift`).
/// - `isOnline` alimente l'indicateur « Hors ligne » de `RootView` ;
/// - `refreshGeneration` augmente au retour au premier plan et au retour du réseau (règles dans `AutoRefreshState`).
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var state: AutoRefreshState

    var isOnline: Bool { state.isOnline }
    var refreshGeneration: Int { state.generation }

    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - isOnline: état de départ (previews, tests).
    ///   - startsMonitoring: false pour les previews et les tests, qui pilotent l'état à la main.
    init(isOnline: Bool = true, startsMonitoring: Bool = true, now: @escaping @Sendable () -> Date = { .now }) {
        state = AutoRefreshState(isOnline: isOnline)
        self.now = now
        if startsMonitoring { start() }
    }

    isolated deinit {
        stop()
    }

    /// Démarre l'écoute du réseau (`NWPathMonitor`), sans effet si elle tourne déjà.
    func start() {
        guard pathMonitor == nil else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        // Appelé sur la file du moniteur : on ne passe qu'un Bool (Sendable) au MainActor.
        monitor.pathUpdateHandler = Self.makePathHandler(continuation)
        monitor.start(queue: DispatchQueue(label: "ca.amc2026.mobileapp.network-monitor", qos: .utility))
        pathMonitor = monitor
        updates = Task { [weak self] in
            for await online in stream {
                self?.connectivityChanged(isOnline: online)
            }
        }
    }

    /// Arrête l'écoute du réseau.
    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        updates?.cancel()
        updates = nil
    }

    /// À appeler à chaque changement de `scenePhase` (fait par `RootView`).
    func scenePhaseChanged(to phase: ScenePhase) {
        state.phaseChanged(to: AutoRefreshState.Phase(phase), at: now())
    }

    /// Nouvel état de la connexion (appelé par l'écoute du réseau, ou à la main dans les tests).
    func connectivityChanged(isOnline: Bool) {
        state.connectivityChanged(isOnline: isOnline, at: now())
    }

    /// Fermeture non isolée : `NWPathMonitor` l'appelle hors du MainActor.
    private nonisolated static func makePathHandler(
        _ continuation: AsyncStream<Bool>.Continuation
    ) -> @Sendable (NWPath) -> Void {
        { path in continuation.yield(path.status == .satisfied) }
    }
}

extension AutoRefreshState.Phase {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        default: self = .inactive
        }
    }
}
