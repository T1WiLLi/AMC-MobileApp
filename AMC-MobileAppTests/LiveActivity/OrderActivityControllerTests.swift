import Foundation
import Testing
@testable import AMC_MobileApp

/// Faux ActivityKit : enregistre les appels.
@MainActor
final class FakeLiveActivityClient: LiveActivityClient {
    var areActivitiesEnabled = true
    var requestError: (any Error)?
    private(set) var requested: [GrenierOrderAttributes.ContentState] = []
    private(set) var updates: [(stage: GrenierOrderAttributes.Stage, alertTitle: String?)] = []
    private(set) var ended: [String] = []
    private(set) var endAllCount = 0

    func request(attributes: GrenierOrderAttributes, state: GrenierOrderAttributes.ContentState) throws -> String {
        if let requestError { throw requestError }
        requested.append(state)
        return "activity-\(requested.count)"
    }

    func update(id: String, state: GrenierOrderAttributes.ContentState, alert: (title: String, body: String)?) async {
        updates.append((state.stage, alert?.title))
    }

    func end(id: String, state: GrenierOrderAttributes.ContentState?) async {
        ended.append(id)
    }

    func endAll() async { endAllCount += 1 }
}

@MainActor
struct OrderActivityControllerTests {
    @Test func disabledActivitiesThrowAppError() async {
        let client = FakeLiveActivityClient()
        client.areActivitiesEnabled = false
        let controller = OrderActivityController(client: client)

        await #expect(throws: AppError.liveActivitiesDisabled) {
            try await controller.start()
        }
        #expect(controller.error == .liveActivitiesDisabled)
        #expect(!controller.isActive)
        #expect(client.requested.isEmpty)
        #expect(AppError.liveActivitiesDisabled.isRetryable == false)
    }

    @Test func systemRefusalBecomesUnknownError() async {
        let client = FakeLiveActivityClient()
        client.requestError = CancellationError()
        let controller = OrderActivityController(client: client)

        await #expect(throws: AppError.self) { try await controller.start() }
        #expect(!controller.isActive)
        if case .unknown = controller.error {} else { Issue.record("attendu .unknown, reçu \(String(describing: controller.error))") }
    }

    @Test func startUpdateEnd() async throws {
        let client = FakeLiveActivityClient()
        let controller = OrderActivityController(client: client)

        try await controller.start()
        #expect(controller.isActive)
        #expect(controller.state?.stage == .ouverte)
        #expect(client.endAllCount == 1)

        await controller.update(to: .demo(.palierFranchi))
        #expect(controller.state?.stage == .palierFranchi)
        #expect(client.updates.last?.alertTitle == "Palier débloqué !")

        await controller.end()
        #expect(!controller.isActive)
        #expect(controller.state == nil)
        #expect(client.ended == ["activity-1"])
    }

    @Test func updateWithoutActivityDoesNothing() async {
        let client = FakeLiveActivityClient()
        let controller = OrderActivityController(client: client)
        await controller.update(to: .demo(.enRoute))
        #expect(client.updates.isEmpty)
        #expect(controller.state == nil)
    }

    @Test func refreshResendsCurrentStateWithoutAlert() async throws {
        let client = FakeLiveActivityClient()
        let controller = OrderActivityController(client: client)

        await controller.refresh()
        #expect(client.updates.isEmpty)

        try await controller.start(state: .demo(.enRoute))
        await controller.refresh()
        #expect(client.updates.count == 1)
        #expect(client.updates.last?.stage == .enRoute)
        #expect(client.updates.last?.alertTitle == nil)
        #expect(controller.state?.stage == .enRoute)
    }

    @Test func demoChainsStagesInOrder() async throws {
        let client = FakeLiveActivityClient()
        let controller = OrderActivityController(client: client)

        try await controller.startDemo(stepInterval: .milliseconds(10))
        #expect(controller.isDemoRunning)
        await controller.waitForDemo()

        #expect(client.requested.map(\.stage) == [.ouverte])
        #expect(client.updates.map(\.stage) == [.palierFranchi, .enRoute, .arrivee])
        #expect(controller.state?.stage == .arrivee)
        #expect(!controller.isDemoRunning)
    }

    @Test func endStopsTheDemo() async throws {
        let client = FakeLiveActivityClient()
        let controller = OrderActivityController(client: client)

        try await controller.startDemo(stepInterval: .seconds(30))
        await controller.end()
        #expect(!controller.isDemoRunning)
        #expect(client.updates.isEmpty)
    }
}
