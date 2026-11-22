// HouseholdAddress.swift
// T-159 : adresse d'un ménage, pour que deux comptes à la même adresse se retrouvent dans le même ménage.
//
// On ne garde jamais l'adresse telle quelle :
// - `key` : clé normalisée (minuscules, sans accents, sans espaces ni ponctuation, abréviations courantes
//   dépliées). Stockée sur le ménage (`households/{id}.addressKey`), lisible par ses membres seulement.
// - `lookupId` : empreinte SHA-256 de la clé, id du document `householdAddresses/{lookupId}`. Ce document
//   ne se lit que par son id exact (pas de liste) : il faut connaître l'adresse pour découvrir le ménage,
//   et on n'apprend alors que son nom.

import CryptoKit
import Foundation

nonisolated struct HouseholdAddress: Sendable, Hashable {
    var streetNumber: String
    var street: String
    var postalCode: String

    init(streetNumber: String, street: String, postalCode: String) {
        self.streetNumber = streetNumber
        self.street = street
        self.postalCode = postalCode
    }

    /// Abréviations dépliées avant de comparer : « 12 av. St-Denis » et « 12 avenue Saint-Denis » sont la même adresse.
    static let abbreviations: [String: String] = [
        "st": "saint", "ste": "sainte",
        "av": "avenue", "ave": "avenue",
        "boul": "boulevard", "bd": "boulevard", "blvd": "boulevard",
        "ch": "chemin", "rte": "route", "pl": "place", "rd": "road", "str": "street",
        // T-185 : Apple Maps abrège les directions (« Rue Jarry E »).
        "e": "est", "o": "ouest", "w": "ouest", "n": "nord", "s": "sud",
    ]

    /// Mots retirés : ils changent selon qui écrit l'adresse (« rue Jarry » ou « Jarry »).
    static let fillerWords: Set<String> = ["rue", "de", "du", "des", "la", "le", "l", "d"]

    /// Numéro civique : chiffres et lettre (« 1234 », « 1234a »). Vide s'il n'y a aucun chiffre.
    var normalizedNumber: String {
        let folded = Self.fold(streetNumber)
        guard folded.contains(where: \.isNumber) else { return "" }
        return folded.filter { $0.isLetter || $0.isNumber }
    }

    /// Nom de rue : mots pliés, abréviations dépliées, mots vides retirés, collés.
    var normalizedStreet: String {
        Self.fold(street)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { Self.abbreviations[String($0)] ?? String($0) }
            .filter { !Self.fillerWords.contains($0) }
            .joined()
    }

    /// Code postal canadien sans espace (« h2r1a1 »), vide s'il n'a pas la forme A1A 1A1 (V4).
    var normalizedPostalCode: String {
        PostalCode.normalized(Self.fold(postalCode)) ?? ""
    }

    /// Les trois parties sont-elles assez remplies pour chercher un ménage ?
    var isComplete: Bool {
        !normalizedNumber.isEmpty && !normalizedStreet.isEmpty && !normalizedPostalCode.isEmpty
    }

    /// Clé normalisée (`1234jarryest-h2r1a1`), `nil` si l'adresse est incomplète.
    var key: String? {
        guard isComplete else { return nil }
        return "\(normalizedNumber)\(normalizedStreet)-\(normalizedPostalCode)"
    }

    /// Id du document `householdAddresses/{lookupId}` : SHA-256 de la clé, en hexadécimal.
    static func lookupId(forKey key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var lookupId: String? { key.map(Self.lookupId(forKey:)) }

    /// Minuscules et sans accents (« Saint-Ézéchiel » → « saint-ezechiel »).
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_CA"))
            .lowercased()
    }
}

/// Document `householdAddresses/{lookupId}` : le ménage inscrit à cette adresse, avec son nom seulement.
nonisolated struct HouseholdAddressEntry: Identifiable, Codable, Sendable, Hashable {
    /// `HouseholdAddress.lookupId`.
    var id: String
    var householdId: String
    var name: String
    var ownerId: String
}

/// Demande pour rejoindre un ménage (`households/{householdId}/joinRequests/{userId}`).
nonisolated struct HouseholdJoinRequest: Identifiable, Codable, Sendable, Hashable {
    enum Status: String, Codable, Sendable {
        /// En attente du propriétaire.
        case pending
        /// Acceptée : l'uid est dans `userIds`, la personne n'a plus qu'à pointer son profil vers le ménage.
        case accepted
    }

    var householdId: String
    var userId: String
    /// Nom affiché au propriétaire (« Karim Benali »).
    var displayName: String
    /// Nom du ménage demandé, pour l'écran d'attente (la personne ne lit pas encore le ménage).
    var householdName: String? = nil
    var createdAt: Date
    var status: Status

    var id: String { userId }
}

/// Règles pures du partage d'un ménage entre plusieurs comptes (T-159). Partagées par les dépôts Fake et Firestore.
nonisolated enum HouseholdMembership {
    /// Nombre de comptes par ménage (même limite que `firestore.rules`).
    static let maxMembers = 10
    /// Taille d'un ménage acceptée (même limite que `firestore.rules`, `isIntIn(data.size, 1, 30)`, V6).
    static let sizeRange = 1...30

    /// Propriétaire : `ownerId`, sinon (ménage d'avant T-159) le premier compte du ménage.
    static func ownerId(of household: Household) -> String? {
        if let ownerId = household.ownerId, !ownerId.isEmpty { return ownerId }
        return household.userIds.first
    }

    static func isOwner(_ userId: String, of household: Household) -> Bool {
        ownerId(of: household) == userId
    }

    /// Ménage après l'acceptation de `request` par `ownerId`.
    static func accepting(_ request: HouseholdJoinRequest, in household: Household, byUserId ownerId: String) throws -> Household {
        guard isOwner(ownerId, of: household) else { throw AppError.permissionDenied }
        guard request.householdId == household.id, request.status == .pending else { throw AppError.notFound }
        var household = household
        if !household.userIds.contains(request.userId) {
            guard household.userIds.count < maxMembers else {
                throw AppError.invalidInput(String(localized: "Un ménage compte \(maxMembers) comptes au plus."))
            }
            household.userIds.append(request.userId)
        }
        household.memberNames = (household.memberNames ?? [:]).merging([request.userId: request.displayName]) { _, new in new }
        return household
    }

    /// Ménage après le retrait de `userId` : par le propriétaire (un autre membre), ou par la personne elle-même.
    /// Le propriétaire ne se retire pas (le ménage resterait sans propriétaire) : il cède d'abord son rôle
    /// à un autre membre (`transferringOwnership`).
    static func removing(_ userId: String, from household: Household, byUserId callerId: String) throws -> Household {
        guard household.userIds.contains(userId) else { throw AppError.notFound }
        let owner = ownerId(of: household)
        guard userId != owner else {
            throw AppError.invalidInput(String(localized: "Nomme d'abord un autre membre propriétaire, puis quitte le ménage."))
        }
        guard callerId == owner || callerId == userId else { throw AppError.permissionDenied }
        var household = household
        household.userIds.removeAll { $0 == userId }
        household.memberNames?[userId] = nil
        return household
    }

    /// Ménage après que le propriétaire a cédé son rôle à `newOwnerId`, un autre membre (FB-22).
    /// Les membres et leurs noms ne bougent pas ; seul `ownerId` change.
    static func transferringOwnership(to newOwnerId: String, in household: Household, byUserId callerId: String) throws -> Household {
        guard isOwner(callerId, of: household) else { throw AppError.permissionDenied }
        guard newOwnerId != callerId else {
            throw AppError.invalidInput(String(localized: "Tu es déjà propriétaire du ménage."))
        }
        guard household.userIds.contains(newOwnerId) else { throw AppError.notFound }
        var household = household
        household.ownerId = newOwnerId
        return household
    }

    /// Prénom à afficher pour un membre (« Amina »), `nil` s'il est inconnu.
    static func firstName(of userId: String, in household: Household?) -> String? {
        guard let name = household?.memberNames?[userId] else { return nil }
        return name.split(separator: " ").first.map(String.init)
    }
}
