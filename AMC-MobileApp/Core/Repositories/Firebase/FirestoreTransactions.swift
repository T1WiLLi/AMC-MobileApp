// FirestoreTransactions.swift
// Petits outils partagés par les dépôts Firestore de l'entraide entre voisins (livraison RQ-069, covoiturage RQ-070) :
// transaction avec des erreurs Swift et décodage d'un document avec son id.

#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

/// Résultat d'une transaction : le bloc peut tourner plusieurs fois, on garde le dernier passage.
/// Sûr : le bloc et la complétion s'exécutent l'un après l'autre, jamais en même temps.
private nonisolated final class NeighbourTransactionOutcome<Value>: @unchecked Sendable {
    var value: Value?
    var error: (any Error)?
}

nonisolated enum FirestoreTransactions {
    /// `runTransaction` avec un bloc qui lève des `AppError`. Le bloc peut tourner plusieurs fois (conflit
    /// entre deux voisins) : il ne doit rien faire d'autre que lire et écrire. Une erreur levée annule sans réessai.
    static func run<Value>(
        _ db: Firestore, _ block: @escaping (Transaction) throws -> Value
    ) async throws -> Value {
        let outcome = NeighbourTransactionOutcome<Value>()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            db.runTransaction({ transaction, errorPointer in
                outcome.value = nil
                outcome.error = nil
                do {
                    outcome.value = try block(transaction)
                } catch {
                    outcome.error = error
                    errorPointer?.pointee = error as NSError
                }
                return nil
            }, completion: { _, error in
                if let thrown = outcome.error {
                    continuation.resume(throwing: FirestoreGroupOrderRepository.appError(from: thrown))
                } else if let error {
                    continuation.resume(throwing: FirestoreGroupOrderRepository.appError(from: error))
                } else if let value = outcome.value {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: AppError.unknown("Transaction sans résultat."))
                }
            })
        }
    }

    /// Décode un document ; son id fait foi (`idKey`), même s'il manque dans les champs (seed, console).
    static func decode<T: Decodable>(_ type: T.Type, _ snapshot: DocumentSnapshot, idKey: String = "id") throws -> T {
        var data = snapshot.data() ?? [:]
        data[idKey] = snapshot.documentID
        do {
            return try Firestore.Decoder().decode(T.self, from: data)
        } catch {
            throw AppError.unknown("Document \(snapshot.reference.path) illisible : \(error.localizedDescription)")
        }
    }
}
#endif
