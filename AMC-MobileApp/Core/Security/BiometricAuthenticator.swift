import Foundation
import LocalAuthentication

/// Type de biométrie disponible sur l'appareil.
enum BiometryKind: Equatable, Sendable {
    case faceID, touchID, opticID
    /// Pas de biométrie inscrite : on retombe sur le code de l'appareil.
    case passcodeOnly
    /// Ni biométrie ni code : impossible de verrouiller.
    case unavailable

    var title: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcodeOnly: "le code de l'appareil"
        case .unavailable: "aucune méthode"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcodeOnly: "lock.fill"
        case .unavailable: "lock.slash"
        }
    }

    var canAuthenticate: Bool { self != .unavailable }
}

/// Vérifie l'identité de l'utilisateur (Face ID, Touch ID ou code). Réutilisé par le verrou de l'app et
/// pour confirmer un paiement (E07).
protocol BiometricAuthenticator: Sendable {
    func availability() -> BiometryKind
    /// Lève `AppError` : `.invalidInput` si l'utilisateur annule, `.permissionDenied` si l'identité n'est pas confirmée.
    func authenticate(reason: String) async throws
}

/// Implémentation réelle (LocalAuthentication), avec repli sur le code de l'appareil.
struct DeviceBiometricAuthenticator: BiometricAuthenticator {
    func availability() -> BiometryKind {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: break
            }
        }
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? .passcodeOnly : .unavailable
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        context.localizedFallbackTitle = "Utiliser le code"
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError {
            throw Self.map(error)
        } catch {
            throw AppError(error)
        }
    }

    static func map(_ error: LAError) -> AppError {
        switch error.code {
        case .userCancel, .systemCancel, .appCancel:
            .invalidInput("Déverrouillage annulé.")
        case .biometryLockout:
            .permissionDenied
        case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled:
            .unknown("Aucune méthode de déverrouillage sur cet appareil.")
        default:
            .permissionDenied
        }
    }
}

/// Fake pour les previews, les tests et le simulateur sans Face ID inscrit.
struct FakeBiometricAuthenticator: BiometricAuthenticator {
    var kind: BiometryKind = .faceID
    var result: Result<Void, AppError> = .success(())

    func availability() -> BiometryKind { kind }

    func authenticate(reason: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        try result.get()
    }
}
