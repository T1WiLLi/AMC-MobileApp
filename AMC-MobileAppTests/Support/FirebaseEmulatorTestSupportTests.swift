import Foundation
import Testing
@testable import AMC_MobileApp

/// Gardes du support émulateur : sans réseau, tournent partout (CI comprise).
@MainActor
struct FirebaseEmulatorGuardTests {
    @Test func refusesNonLocalURLs() async {
        let production = URL(string: "https://firestore.googleapis.com/v1/projects/amc-2026-8ab03/databases/(default)/documents")!
        await #expect(throws: FirebaseEmulatorTestSupport.EmulatorError.self) {
            try await FirebaseEmulatorTestSupport.send(method: "DELETE", to: production)
        }
    }

    @Test func emulatorProjectIsDemo() {
        #expect(FirebaseEmulatorTestSupport.projectID == "demo-grenier")
        #expect(FirebaseEmulatorTestSupport.config.isSafeEmulatorTarget)
    }

    @Test func unsafeTargetsAreRejected() {
        #expect(!FirebaseEmulatorConfig(projectID: "amc-2026-8ab03").isSafeEmulatorTarget)
        #expect(!FirebaseEmulatorConfig(host: "firestore.googleapis.com").isSafeEmulatorTarget)
        #expect(FirebaseEmulatorConfig(host: "192.168.1.20").isSafeEmulatorTarget)
    }

    #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
    @Test func sessionRefusesRealProject() {
        #expect(throws: FirebaseEmulatorSessionError.self) {
            try FirebaseEmulatorSession.make(name: "guard", config: FirebaseEmulatorConfig(projectID: "amc-2026-8ab03"))
        }
    }
    #endif
}

/// Vérifie le support émulateur lui-même. Sauté si l'émulateur Firestore ne tourne pas (CI).
@MainActor
@Suite(.serialized, .firestoreEmulator)
struct FirebaseEmulatorIntegrationTests {
    @Test func clearFirestoreRemovesDocuments() async throws {
        let document = FirebaseEmulatorTestSupport.documentsURL.appending(path: "emulatorSmoke/doc1")
        let body = Data(#"{"fields":{"label":{"stringValue":"test"}}}"#.utf8)

        let (_, written) = try await FirebaseEmulatorTestSupport.send(method: "PATCH", to: document, json: body)
        #expect(written.statusCode == 200)
        let (_, before) = try await FirebaseEmulatorTestSupport.send(method: "GET", to: document)
        #expect(before.statusCode == 200)

        try await FirebaseEmulatorTestSupport.clearFirestore()

        let (_, after) = try await FirebaseEmulatorTestSupport.send(method: "GET", to: document)
        #expect(after.statusCode == 404)
    }

    #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
    @Test func twoIndependentSessions() async throws {
        let vendor = try FirebaseEmulatorTestSupport.session("vendor")
        let family = try FirebaseEmulatorTestSupport.session("family")
        #expect(vendor.name != family.name)
        #expect(vendor.projectID == "demo-grenier")
        #expect(vendor.host == "127.0.0.1")
        #expect(FirebaseSetup.isEmulatorTarget(vendor.firestore))
        #expect(FirebaseSetup.isEmulatorTarget(family.firestore))
    }
    #endif
}
