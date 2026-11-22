// MapKitAddressValidator.swift
// T-185 : validation d'adresse avec Apple Maps, sans permission de localisation.
// - Suggestions : `MKLocalSearchCompleter` (adresses seulement), centré sur Montréal.
// - Validation : `MKLocalSearch` (adresses seulement) ; si l'adresse vient d'une suggestion, on la résout
//   directement (résultat plus précis). Un résultat n'est accepté que s'il a le même numéro civique et une rue
//   qui ressemble à celle tapée (`AddressMatching.matches`) : « 99999 rue Jarry » ne donne que la rue, refusé.
//
// Tout vit sur le main actor : le completer est un objet UIKit-like à délégué, appelé depuis les vues.

import MapKit

@MainActor
final class MapKitAddressValidator: NSObject, AddressValidating {
    /// Montréal et ses environs (~60 km) : les résultats d'ici passent devant.
    static let montrealRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.55, longitude: -73.62),
        latitudinalMeters: 60_000, longitudinalMeters: 60_000
    )

    /// Instance partagée par les champs d'adresse (un seul champ a le focus à la fois).
    static let shared = MapKitAddressValidator()

    private let region: MKCoordinateRegion
    private let completer = MKLocalSearchCompleter()
    private var pending: CheckedContinuation<[AddressSuggestion], Never>?
    /// Dernières suggestions montrées, pour résoudre celle qu'on choisit.
    private var recentCompletions: [String: MKLocalSearchCompletion] = [:]

    init(region: MKCoordinateRegion = MapKitAddressValidator.montrealRegion) {
        self.region = region
        super.init()
        completer.resultTypes = .address
        completer.region = region
        completer.delegate = self
    }

    func suggestions(for query: String) async -> [AddressSuggestion] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return [] }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                finishPending(with: [])
                pending = continuation
                if completer.queryFragment == query, !completer.isSearching {
                    finishPending(with: completer.results)
                } else {
                    completer.queryFragment = query
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishPending(with: []) }
        }
    }

    func validate(_ text: String) async throws -> ValidatedAddress? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressMatching.civicNumber(in: text) != nil else { return nil }
        let request: MKLocalSearch.Request
        if let completion = recentCompletions[text] {
            request = MKLocalSearch.Request(completion: completion)
        } else {
            request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
        }
        request.resultTypes = .address
        request.region = region
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            // Apple a bien cherché et n'a rien trouvé : vraiment introuvable.
            return nil
        }
        // Toute autre erreur (réseau, service indisponible, limite de requêtes) remonte : vérification impossible.
        return response.mapItems.lazy.compactMap { Self.validated(from: $0, input: text) }.first
    }

    /// Adresse normalisée d'un résultat, s'il correspond à ce qu'on a tapé.
    private static func validated(from item: MKMapItem, input: String) -> ValidatedAddress? {
        guard let full = item.address?.fullAddress
            ?? item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) else { return nil }
        let singleLine = full.replacingOccurrences(of: "\n", with: ", ")
        let formatted = AddressMatching.withoutCountry(singleLine)
        let streetLine = AddressMatching.streetLine(of: formatted)
        guard AddressMatching.matches(input: input, candidateStreetLine: streetLine) else { return nil }
        let coordinate = item.location.coordinate
        return ValidatedAddress(
            formatted: formatted, streetLine: streetLine, postalCode: AddressMatching.postalCode(in: formatted),
            coordinate: Geohash.Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    /// Termine la demande de suggestions en cours (5 au plus) et garde les complétions pour `validate(_:)`.
    private func finishPending(with results: [MKLocalSearchCompletion]) {
        guard let pending else { return }
        self.pending = nil
        let kept = Array(results.prefix(5))
        let suggestions = kept.map { AddressSuggestion(title: $0.title, subtitle: $0.subtitle) }
        if !kept.isEmpty {
            recentCompletions = Dictionary(zip(suggestions.map(\.id), kept), uniquingKeysWith: { first, _ in first })
        }
        pending.resume(returning: suggestions)
    }
}

extension MapKitAddressValidator: @MainActor MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        finishPending(with: completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        finishPending(with: [])
    }
}
