import Foundation
import Testing

/// Vérifie le support émulateur lui-même. Sauté si l'émulateur Firestore ne tourne pas (CI).
@Suite(.serialized, .firestoreEmulator)
struct FirebaseEmulatorTests {
    @Test func clearFirestoreRemovesDocuments() async throws {
        let document = FirebaseEmulator.documentsURL.appending(path: "emulatorSmoke/doc1")
        let body = Data(#"{"fields":{"label":{"stringValue":"test"}}}"#.utf8)

        let (_, written) = try await FirebaseEmulator.send(method: "PATCH", to: document, json: body)
        #expect(written.statusCode == 200)
        let (_, before) = try await FirebaseEmulator.send(method: "GET", to: document)
        #expect(before.statusCode == 200)

        try await FirebaseEmulator.clearFirestore()

        let (_, after) = try await FirebaseEmulator.send(method: "GET", to: document)
        #expect(after.statusCode == 404)
    }
}
