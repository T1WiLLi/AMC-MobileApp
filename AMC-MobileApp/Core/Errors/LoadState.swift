import Foundation

/// État d'un chargement pour un ViewModel : idle → loading → loaded / empty / failed.
enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(AppError)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    var error: AppError? {
        if case .failed(let error) = self { error } else { nil }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

extension LoadState: Equatable where Value: Equatable {}

extension LoadState where Value: Collection {
    /// Construit l'état à partir d'une collection : vide → `.empty`, sinon `.loaded`.
    static func from(_ collection: Value) -> LoadState {
        collection.isEmpty ? .empty : .loaded(collection)
    }
}

extension LoadState {
    /// Exécute `operation` et renvoie l'état final ; les erreurs deviennent `.failed(AppError)`.
    static func run(_ operation: () async throws -> Value) async -> LoadState {
        do {
            return .loaded(try await operation())
        } catch {
            return .failed(AppError(error))
        }
    }
}
