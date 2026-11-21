import Foundation
import SwiftUI
import Testing
@testable import AMC_MobileApp

/// Rechargement automatique et indicateur hors ligne (S-10, T-090).
struct AutoRefreshStateTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func later(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    // MARK: - Premier plan

    @Test func returningFromBackgroundRequestsRefresh() {
        var state = AutoRefreshState()
        #expect(state.phaseChanged(to: .inactive, at: start) == nil)
        #expect(state.phaseChanged(to: .background, at: start) == nil)
        #expect(state.phaseChanged(to: .inactive, at: later(10)) == nil)
        #expect(state.phaseChanged(to: .active, at: later(10)) == .foreground)
        #expect(state.generation == 1)
        #expect(state.lastReason == .foreground)
    }

    @Test func inactiveOnlyDoesNotRefresh() {
        var state = AutoRefreshState()
        state.phaseChanged(to: .active, at: start)
        state.phaseChanged(to: .inactive, at: later(5))
        #expect(state.phaseChanged(to: .active, at: later(10)) == nil)
        #expect(state.generation == 0)
    }

    @Test func launchActivationDoesNotRefresh() {
        var state = AutoRefreshState()
        #expect(state.phaseChanged(to: .active, at: start) == nil)
        #expect(state.generation == 0)
    }

    @Test func foregroundWhileOfflineWaitsForNetwork() {
        var state = AutoRefreshState(isOnline: false)
        state.phaseChanged(to: .background, at: start)
        #expect(state.phaseChanged(to: .active, at: later(10)) == nil)
        #expect(state.connectivityChanged(isOnline: true, at: later(20)) == .reconnected)
        #expect(state.generation == 1)
    }

    @Test func eachBackgroundTripRefreshesOnce() {
        var state = AutoRefreshState()
        for trip in 1...3 {
            let base = Double(trip) * 60
            state.phaseChanged(to: .background, at: later(base))
            state.phaseChanged(to: .active, at: later(base + 30))
            #expect(state.phaseChanged(to: .active, at: later(base + 40)) == nil)
            #expect(state.generation == trip)
        }
    }

    // MARK: - Réseau

    @Test func reconnectionRequestsRefresh() {
        var state = AutoRefreshState()
        #expect(state.connectivityChanged(isOnline: false, at: start) == nil)
        #expect(!state.isOnline)
        #expect(state.connectivityChanged(isOnline: true, at: later(30)) == .reconnected)
        #expect(state.isOnline)
        #expect(state.generation == 1)
    }

    @Test func repeatedSameStatusIsIgnored() {
        var state = AutoRefreshState()
        #expect(state.connectivityChanged(isOnline: true, at: start) == nil)
        #expect(state.connectivityChanged(isOnline: true, at: later(30)) == nil)
        #expect(state.generation == 0)
    }

    // MARK: - Fusion des demandes rapprochées

    @Test func closeRequestsAreCoalesced() {
        var state = AutoRefreshState()
        state.connectivityChanged(isOnline: false, at: start)
        state.phaseChanged(to: .background, at: start)
        state.connectivityChanged(isOnline: true, at: later(10))
        state.phaseChanged(to: .active, at: later(10.5))
        #expect(state.generation == 1)
        #expect(state.lastReason == .reconnected)
    }

    @Test func requestsAfterIntervalAreNotCoalesced() {
        var state = AutoRefreshState()
        state.connectivityChanged(isOnline: false, at: start)
        state.connectivityChanged(isOnline: true, at: later(1))
        state.phaseChanged(to: .background, at: later(2))
        state.phaseChanged(to: .active, at: later(1 + AutoRefreshState.coalescingInterval))
        #expect(state.generation == 2)
        #expect(state.lastReason == .foreground)
    }

    // MARK: - Écrans

    @Test func screenSkipsFirstAppearance() {
        #expect(!AutoRefreshState.shouldRefresh(lastHandled: nil, current: 0))
        #expect(!AutoRefreshState.shouldRefresh(lastHandled: nil, current: 4))
    }

    @Test func screenRefreshesWhenGenerationChanged() {
        #expect(AutoRefreshState.shouldRefresh(lastHandled: 0, current: 1))
        #expect(AutoRefreshState.shouldRefresh(lastHandled: 1, current: 3))
        #expect(!AutoRefreshState.shouldRefresh(lastHandled: 2, current: 2))
    }

    // MARK: - Moniteur

    @MainActor
    @Test func monitorExposesStateWithoutNetworkAccess() {
        let clock = Clock()
        let monitor = NetworkMonitor(startsMonitoring: false, now: { clock.now })
        #expect(monitor.isOnline)
        monitor.connectivityChanged(isOnline: false)
        #expect(!monitor.isOnline)
        clock.now = clock.now.addingTimeInterval(30)
        monitor.connectivityChanged(isOnline: true)
        #expect(monitor.refreshGeneration == 1)

        clock.now = clock.now.addingTimeInterval(30)
        monitor.scenePhaseChanged(to: .background)
        monitor.scenePhaseChanged(to: .active)
        #expect(monitor.refreshGeneration == 2)
    }

    @MainActor
    @Test func scenePhaseMapping() {
        #expect(AutoRefreshState.Phase(.active) == .active)
        #expect(AutoRefreshState.Phase(.inactive) == .inactive)
        #expect(AutoRefreshState.Phase(.background) == .background)
    }

    // MARK: - Cache Firestore

    @Test func demoProjectUsesPersistentCache() {
        let hundredMegabytes: Int64 = 100 * 1_024 * 1_024
        #expect(BackendMode.demoProject.firestoreCache == .persistent(sizeBytes: hundredMegabytes))
        #expect(BackendMode.emulator.firestoreCache == .memory)
        #expect(BackendMode.fake.firestoreCache == nil)
    }
}

/// Horloge réglable pour les tests du moniteur.
private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 0)
}
