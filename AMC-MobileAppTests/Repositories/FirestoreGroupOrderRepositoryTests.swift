// FirestoreGroupOrderRepositoryTests.swift
// B-019 : tests d'intégration du dépôt Firestore des commandes groupées, contre l'émulateur local
// (règles de `firestore.rules` comprises). Sautés quand l'émulateur ne répond pas (CI, Mac sans Node).
//
// Lancer l'émulateur depuis la racine du repo :
//   npx -y firebase-tools@latest emulators:start --project demo-grenier --only auth,firestore

#if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
import Foundation
import Testing
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
@testable import AMC_MobileApp

// MARK: - Support émulateur

/// Émulateurs Auth (9099) et Firestore (8080) joignables sur 127.0.0.1.
/// Autres ports : `TEST_RUNNER_FIRESTORE_EMULATOR_PORT=8181 TEST_RUNNER_AUTH_EMULATOR_PORT=9191 xcodebuild test …`
/// (xcodebuild retire le préfixe `TEST_RUNNER_` avant de passer la variable aux tests).
nonisolated enum FirestoreEmulator {
    static let host = "127.0.0.1"
    static let firestorePort = port("FIRESTORE_EMULATOR_PORT", default: 8080)
    static let authPort = port("AUTH_EMULATOR_PORT", default: 9099)
    static let projectId = "demo-grenier"

    private static func port(_ name: String, default value: Int) -> Int {
        ProcessInfo.processInfo.environment[name].flatMap(Int.init) ?? value
    }

    static let isAvailable: Bool = responds(port: firestorePort) && responds(port: authPort)

    private static func responds(port: Int) -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResponseFlag()
        URLSession.shared.dataTask(with: request) { _, response, _ in
            result.set(response != nil)
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return result.value
    }

    private final class ResponseFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool { lock.withLock { stored } }
        func set(_ value: Bool) { lock.withLock { stored = value } }
    }

    /// Écrit un document en contournant les règles (jeton « owner » de l'émulateur), pour préparer les données.
    static func seed(_ path: String, _ fields: [String: Any]) async throws {
        let url = try #require(URL(string:
            "http://\(host):\(firestorePort)/v1/projects/\(projectId)/databases/(default)/documents/\(path)"
        ))
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields.mapValues(restValue)])
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AppError.unknown("Seed \(path) : HTTP \(status) \(String(decoding: body, as: UTF8.self))")
        }
    }

    /// Valeur au format REST de Firestore.
    private static func restValue(_ value: Any) -> [String: Any] {
        switch value {
        case let value as Bool: ["booleanValue": value]
        case let value as Int: ["integerValue": String(value)]
        case let value as String: ["stringValue": value]
        case let value as Date: ["timestampValue": ISO8601DateFormatter().string(from: value)]
        case let value as [Any]: ["arrayValue": ["values": value.map(restValue)]]
        case let value as [String: Any]: ["mapValue": ["fields": value.mapValues(restValue)]]
        default: ["nullValue": NSNull()]
        }
    }
}

/// Un appareil connecté à l'émulateur : sa propre app Firebase, son compte anonyme, son dépôt.
nonisolated struct EmulatorDevice: @unchecked Sendable {
    let uid: String
    let db: Firestore
    let repository: FirestoreGroupOrderRepository

    static func signIn() async throws -> EmulatorDevice {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:b019b019b019b019", gcmSenderID: "1234567890")
        options.projectID = FirestoreEmulator.projectId
        options.apiKey = "fake-api-key-emulator"
        let name = "b019-\(UUID().uuidString)"
        FirebaseApp.configure(name: name, options: options)
        let app = try #require(FirebaseApp.app(name: name))

        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: FirestoreEmulator.host, port: FirestoreEmulator.authPort)
        let uid = try await auth.signInAnonymously().user.uid

        let db = Firestore.firestore(app: app)
        let settings = db.settings
        settings.host = "\(FirestoreEmulator.host):\(FirestoreEmulator.firestorePort)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        db.settings = settings
        return EmulatorDevice(uid: uid, db: db, repository: FirestoreGroupOrderRepository(db: db))
    }

    /// Écriture brute, sans passer par le dépôt (pour vérifier les règles).
    func write(_ path: String, _ data: [String: Any]) async throws {
        do {
            try await db.document(path).setData(data)
        } catch {
            throw FirestoreGroupOrderRepository.appError(from: error)
        }
    }
}

/// Monde de test isolé : ids uniques, un groupe, un lot, des familles membres.
nonisolated struct EmulatorWorld: Sendable {
    let groupId: String
    let offerId: String
    let vendorId: String

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        groupId = "group-\(suffix)"
        offerId = "offer-\(suffix)"
        vendorId = "vendor-\(suffix)"
    }

    /// Lot : 20 parts, lancement à 5 parts, paliers à 5 (10 $) et 10 (8 $).
    func seedOffer(deadline: Date, status: String = "active") async throws {
        try await FirestoreEmulator.seed("offers/\(offerId)", [
            "id": offerId, "vendorId": vendorId, "productId": "product-test", "totalShares": 20,
            "shareUnit": "5 kg", "minimumSharesToLaunch": 5, "deadline": deadline, "zones": ["test"],
            "status": status,
            "tiers": [["minShares": 10, "priceCents": 800], ["minShares": 5, "priceCents": 1000]],
        ])
    }

    func seedGroup(coordinatorIds: [String] = []) async throws {
        try await FirestoreEmulator.seed("groups/\(groupId)", [
            "id": groupId, "name": "Groupe test", "neighborhood": "test", "centerGeohash": "f25dv",
            "radiusMeters": 500, "coordinatorIds": coordinatorIds, "householdCount": 0, "isPublic": true,
            "inviteCode": "TEST",
        ])
    }

    /// Crée le ménage de l'utilisateur, membre du groupe si demandé. Renvoie l'id du ménage.
    @discardableResult
    func seedFamily(_ device: EmulatorDevice, member: Bool = true) async throws -> String {
        let householdId = "household-\(device.uid)"
        try await FirestoreEmulator.seed("users/\(device.uid)", [
            "id": device.uid, "displayName": "Famille", "language": "fr", "roles": ["family"],
            "neighborhood": "test", "dietaryPreferences": [String](), "seniorMode": false, "householdId": householdId,
        ])
        if member {
            try await FirestoreEmulator.seed("groups/\(groupId)/members/\(householdId)", [
                "householdId": householdId, "role": "member", "joinedAt": Date(),
            ])
        }
        return householdId
    }
}

// MARK: - Tests

@Suite(.serialized, .enabled(if: FirestoreEmulator.isAvailable, "Émulateur Firebase absent (127.0.0.1:8080 et :9099)"))
struct FirestoreGroupOrderRepositoryTests {
    @Test func openGroupOrderCreatesThenReusesTheOrder() async throws {
        let world = EmulatorWorld()
        try await world.seedGroup()
        try await world.seedOffer(deadline: .now.addingTimeInterval(86_400))
        let amina = try await EmulatorDevice.signIn()
        try await world.seedFamily(amina)

        let order = try await amina.repository.openGroupOrder(groupId: world.groupId, offerId: world.offerId)
        #expect(order.status == .open)
        #expect(order.committedShares == 0)
        let again = try await amina.repository.openGroupOrder(groupId: world.groupId, offerId: world.offerId)
        #expect(again.id == order.id)
        #expect(try await amina.repository.groupOrders(ofGroup: world.groupId).map(\.id) == [order.id])
        #expect(try await amina.repository.groupOrders(ofOffer: world.offerId).map(\.id) == [order.id])
    }

    @Test func setShareRecalculatesTierInATransactionAndStreamsIt() async throws {
        let world = EmulatorWorld()
        try await world.seedGroup()
        try await world.seedOffer(deadline: .now.addingTimeInterval(86_400))
        let amina = try await EmulatorDevice.signIn()
        let bruno = try await EmulatorDevice.signIn()
        let aminaHousehold = try await world.seedFamily(amina)
        let brunoHousehold = try await world.seedFamily(bruno)
        let order = try await amina.repository.openGroupOrder(groupId: world.groupId, offerId: world.offerId)

        // Bruno écoute la commande en temps réel.
        var updates = await bruno.repository.observeGroupOrder(id: order.id).makeAsyncIterator()
        #expect(try await updates.next()?.committedShares == 0)

        let afterAmina = try await amina.repository.setShare(quantity: 6, householdId: aminaHousehold, groupOrderId: order.id)
        #expect(afterAmina.committedShares == 6)
        #expect(afterAmina.committedHouseholds == 1)
        #expect(afterAmina.currentTierIndex == 0)
        #expect(afterAmina.status == .reached)
        #expect(try await updates.next()?.committedShares == 6)

        let afterBruno = try await bruno.repository.setShare(quantity: 4, householdId: brunoHousehold, groupOrderId: order.id)
        #expect(afterBruno.committedShares == 10)
        #expect(afterBruno.committedHouseholds == 2)
        #expect(afterBruno.currentTierIndex == 1)
        #expect(try await updates.next()?.currentTierIndex == 1)

        // Changer puis retirer sa part.
        _ = try await amina.repository.setShare(quantity: 2, householdId: aminaHousehold, groupOrderId: order.id)
        let removed = try await amina.repository.setShare(quantity: 0, householdId: aminaHousehold, groupOrderId: order.id)
        #expect(removed.committedShares == 4)
        #expect(removed.committedHouseholds == 1)
        #expect(removed.currentTierIndex == nil)
        #expect(removed.status == .open)
        let shares = try await bruno.repository.shares(ofGroupOrder: order.id)
        #expect(shares.map(\.householdId) == [brunoHousehold])
        #expect(shares.first?.updatedAt != nil)

        // Plus de parts que le lot : refusé avant d'écrire.
        await #expect(throws: AppError.invalidInput("Il ne reste que 16 parts dans ce lot.")) {
            try await amina.repository.setShare(quantity: 17, householdId: aminaHousehold, groupOrderId: order.id)
        }
    }

    @Test func concurrentSharesKeepTheTotalConsistent() async throws {
        let world = EmulatorWorld()
        try await world.seedGroup()
        try await world.seedOffer(deadline: .now.addingTimeInterval(86_400))
        let devices = [try await EmulatorDevice.signIn(), try await EmulatorDevice.signIn(), try await EmulatorDevice.signIn()]
        var households: [String] = []
        for device in devices { households.append(try await world.seedFamily(device)) }
        let order = try await devices[0].repository.openGroupOrder(groupId: world.groupId, offerId: world.offerId)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (device, household) in zip(devices, households) {
                group.addTask {
                    _ = try await device.repository.setShare(quantity: 3, householdId: household, groupOrderId: order.id)
                }
            }
            try await group.waitForAll()
        }
        let final = try await devices[0].repository.groupOrder(id: order.id)
        #expect(final.committedShares == 9)
        #expect(final.committedHouseholds == 3)
        #expect(final.currentTierIndex == 0)
    }

    @Test func setShareIsRefusedAfterTheDeadline() async throws {
        let world = EmulatorWorld()
        try await world.seedGroup()
        try await world.seedOffer(deadline: .now.addingTimeInterval(-60))
        let amina = try await EmulatorDevice.signIn()
        let household = try await world.seedFamily(amina)
        let orderId = FirestoreGroupOrderRepository.orderId(groupId: world.groupId, offerId: world.offerId)
        try await FirestoreEmulator.seed("groupOrders/\(orderId)", [
            "id": orderId, "groupId": world.groupId, "offerId": world.offerId, "status": "open",
            "committedShares": 0, "committedHouseholds": 0, "pickupSlots": [Any](),
        ])

        await #expect(throws: AppError.orderClosed) {
            try await amina.repository.setShare(quantity: 1, householdId: household, groupOrderId: orderId)
        }
        // Les règles refusent aussi, même sans passer par le dépôt.
        await #expect(throws: AppError.permissionDenied) {
            try await amina.write("groupOrders/\(orderId)/shares/\(household)", [
                "householdId": household, "quantity": 1, "isPaid": false, "suspendedAmountCents": 0,
                "subsidyCents": 0, "isPickedUp": false,
            ])
        }
        // Ni ouvrir une nouvelle commande sur un lot échu.
        await #expect(throws: AppError.orderClosed) {
            try await amina.repository.openGroupOrder(groupId: "autre-groupe", offerId: world.offerId)
        }
    }

    @Test func rulesRejectForeignSharesAndForgedCounters() async throws {
        let world = EmulatorWorld()
        try await world.seedGroup()
        try await world.seedOffer(deadline: .now.addingTimeInterval(86_400))
        let amina = try await EmulatorDevice.signIn()
        let outsider = try await EmulatorDevice.signIn()
        let aminaHousehold = try await world.seedFamily(amina)
        let outsiderHousehold = try await world.seedFamily(outsider, member: false)
        let order = try await amina.repository.openGroupOrder(groupId: world.groupId, offerId: world.offerId)

        // Hors du groupe : pas de part.
        await #expect(throws: AppError.permissionDenied) {
            try await outsider.repository.setShare(quantity: 1, householdId: outsiderHousehold, groupOrderId: order.id)
        }
        // La part d'un autre ménage : refusée.
        await #expect(throws: AppError.permissionDenied) {
            try await outsider.repository.setShare(quantity: 1, householdId: aminaHousehold, groupOrderId: order.id)
        }
        // Gonfler le compteur sans part : refusé.
        await #expect(throws: AppError.permissionDenied) {
            try await amina.write("groupOrders/\(order.id)", [
                "id": order.id, "groupId": world.groupId, "offerId": world.offerId, "status": "reached",
                "committedShares": 15, "committedHouseholds": 1, "currentTierIndex": 1, "pickupSlots": [Any](),
            ])
        }
        // Une part sans mise à jour de la commande : refusée.
        await #expect(throws: AppError.permissionDenied) {
            try await amina.write("groupOrders/\(order.id)/shares/\(aminaHousehold)", [
                "householdId": aminaHousehold, "quantity": 3, "isPaid": false, "suspendedAmountCents": 0,
                "subsidyCents": 0, "isPickedUp": false,
            ])
        }
        // Un prix figé par une famille : refusé.
        await #expect(throws: AppError.permissionDenied) {
            try await amina.write("groupOrders/\(order.id)/shares/\(aminaHousehold)", [
                "householdId": aminaHousehold, "quantity": 3, "finalPriceCents": 1, "isPaid": true,
                "suspendedAmountCents": 0, "subsidyCents": 0, "isPickedUp": false,
            ])
        }
        #expect(try await amina.repository.groupOrder(id: order.id).committedShares == 0)
    }

    @Test func coordinatorClosesWithTierEngineAndShareAllocator() async throws {
        let world = EmulatorWorld()
        let coordinator = try await EmulatorDevice.signIn()
        try await world.seedGroup(coordinatorIds: [coordinator.uid])
        try await world.seedOffer(deadline: .now.addingTimeInterval(-60))
        let coordinatorHousehold = try await world.seedFamily(coordinator)
        let orderId = FirestoreGroupOrderRepository.orderId(groupId: world.groupId, offerId: world.offerId)
        try await FirestoreEmulator.seed("groupOrders/\(orderId)", [
            "id": orderId, "groupId": world.groupId, "offerId": world.offerId, "status": "reached",
            "currentTierIndex": 1, "committedShares": 12, "committedHouseholds": 2, "pickupSlots": [Any](),
        ])
        for (household, quantity) in [(coordinatorHousehold, 7), ("household-voisin", 5)] {
            try await FirestoreEmulator.seed("groupOrders/\(orderId)/shares/\(household)", [
                "householdId": household, "quantity": quantity, "isPaid": false, "suspendedAmountCents": 0,
                "subsidyCents": 0, "isPickedUp": false,
            ])
        }

        let closure = try await coordinator.repository.closeGroupOrder(
            id: orderId, eligibleHouseholdIds: ["household-voisin"], solidarityFundCents: 1_000
        )
        #expect(closure.order.status == .closed)
        #expect(closure.outcome == .confirmed(tierIndex: 1, unitPriceCents: 800))
        let shares = try await coordinator.repository.shares(ofGroupOrder: orderId)
        let byHousehold = Dictionary(uniqueKeysWithValues: shares.map { ($0.householdId, $0) })
        #expect(byHousehold[coordinatorHousehold]?.finalPriceCents == 5_600)
        #expect(byHousehold["household-voisin"]?.finalPriceCents == 4_000)
        #expect(byHousehold["household-voisin"]?.subsidyCents == 1_000)
        #expect(shares.allSatisfy { $0.qrCode != nil })
        #expect(try await coordinator.repository.groupOrder(id: orderId).status == .closed)

        // Fermée : plus de changement possible.
        await #expect(throws: AppError.orderClosed) {
            try await coordinator.repository.setShare(quantity: 1, householdId: coordinatorHousehold, groupOrderId: orderId)
        }
    }
}
#endif
