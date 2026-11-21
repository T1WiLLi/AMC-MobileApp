// FamilyLocationRequester.swift
// Position de la famille pour la carte (T-091) : lit l'autorisation sans rien demander, puis, seulement
// après l'explication à l'écran, ouvre une session « pendant l'utilisation » et renvoie la première position.
// Refus, restriction ou absence de position : nil, et la carte reste sur le quartier du ménage.

import CoreLocation
import Observation

@Observable
@MainActor
final class FamilyLocationRequester {
    enum Authorization: Equatable {
        /// Jamais demandée : on explique d'abord, puis le système pose la question.
        case notDetermined
        case authorized
        /// Refusée, restreinte ou services de localisation coupés.
        case denied
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isLocating = false
    /// Gardée en vie pendant la recherche : c'est elle qui déclenche la demande d'autorisation.
    @ObservationIgnored private var session: CLServiceSession?

    init() {
        refreshAuthorization()
    }

    /// Relit l'autorisation actuelle (au retour des Réglages, par exemple), sans rien demander.
    func refreshAuthorization() {
        authorization = switch CLLocationManager().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }

    /// Demande l'autorisation si besoin et renvoie la première position connue ; nil si refusée ou introuvable.
    func currentLocation() async -> CLLocationCoordinate2D? {
        isLocating = true
        session = CLServiceSession(authorization: .whenInUse)
        defer {
            isLocating = false
            session = nil
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    authorization = .denied
                    return nil
                }
                if let location = update.location {
                    authorization = .authorized
                    return location.coordinate
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
