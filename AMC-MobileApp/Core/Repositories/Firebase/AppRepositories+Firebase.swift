// AppRepositories+Firebase.swift
// Fabriques des dépôts selon le backend choisi au lancement (B-013).
//
// Brancher un dépôt Firestore (B-017 à B-019) :
//   1. écrire `FirestoreXRepository` dans `Core/Repositories/Firebase/`, conforme au protocole de
//      `RepositoryProtocols.swift`, protégé par `#if canImport(FirebaseFirestore)`, qui RECOIT son Firestore
//      (et son Auth s'il en a besoin) : `init(firestore: Firestore, auth: Auth)`. L'app passe
//      `Firestore.firestore()` / `Auth.auth()` (déjà pointés au bon endroit par `FirebaseSetup.configure()`),
//      les tests passent ceux d'une `FirebaseEmulatorSession` (deux comptes indépendants possibles) ;
//   2. remplacer UNE ligne de `firebase()` ci-dessous (`fallback.offers` → `FirestoreOfferRepository()`) ;
//      tout le code Firebase étant sous `#if canImport(...)`, garder le fake dans la branche `#else`.
//   3. ouvrir la collection dans `firestore.rules` et ajouter des tests d'intégration marqués
//      `.firestoreEmulator` (voir `AMC-MobileAppTests/Support/FirebaseEmulatorTestSupport.swift`).
// Le même dépôt sert pour l'émulateur et le projet de démo : `FirebaseSetup` a déjà pointé Firestore au bon endroit.

import Foundation

extension AppRepositories {
    /// Dépôts Firebase. Les dépôts pas encore écrits en Firestore retombent sur les fakes.
    nonisolated static func firebase() -> AppRepositories {
        let fallback = AppRepositories.fake()
        return AppRepositories(
            users: fallback.users,               // B-017 : FirestoreUserRepository() — users, households
            groups: fallback.groups,             // B-018 : FirestoreGroupRepository() — groups, members
            vendors: fallback.vendors,           // B-017 : FirestoreVendorRepository() — vendors, products
            offers: fallback.offers,             // B-017 : FirestoreOfferRepository() — offers
            groupOrders: fallback.groupOrders,   // B-019 : FirestoreGroupOrderRepository() — groupOrders, shares
            pickupPoints: fallback.pickupPoints  // B-018 : FirestorePickupPointRepository() — pickupPoints
        )
    }

    /// Dépôts pour le mode choisi au lancement (`FirebaseSetup.configure()`).
    nonisolated static func live(mode: BackendMode) -> AppRepositories {
        switch mode {
        case .fake: .fake()
        case .emulator, .demoProject: .firebase()
        }
    }
}
