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
#if canImport(FirebaseCore)
import FirebaseCore
#endif

extension AppRepositories {
    /// Dépôts Firebase. Les dépôts pas encore écrits en Firestore retombent sur les fakes.
    nonisolated static func firebase() -> AppRepositories {
        let fallback = AppRepositories.fake()
        #if canImport(FirebaseFirestore) && canImport(FirebaseCore)
        // Sans FirebaseApp par défaut (tests, configuration ratée), `Firestore.firestore()` plante : fakes.
        let isConfigured = FirebaseApp.app() != nil
        let firestoreUsers: (any UserRepository)? = isConfigured ? FirestoreUserRepository() : nil
        let firestoreGroups: (any GroupRepository)? = isConfigured ? FirestoreGroupRepository() : nil
        let firestoreVendors: (any VendorRepository)? = isConfigured ? FirestoreVendorRepository() : nil
        let firestoreOffers: (any OfferRepository)? = isConfigured ? FirestoreOfferRepository() : nil
        let firestorePickupPoints: (any PickupPointRepository)? = isConfigured ? FirestorePickupPointRepository() : nil
        let firestoreImages: (any ImageStore)? = isConfigured ? FirestoreImageStore() : nil
        #else
        let firestoreUsers: (any UserRepository)? = nil
        let firestoreGroups: (any GroupRepository)? = nil
        let firestoreVendors: (any VendorRepository)? = nil
        let firestoreOffers: (any OfferRepository)? = nil
        let firestorePickupPoints: (any PickupPointRepository)? = nil
        let firestoreImages: (any ImageStore)? = nil
        #endif
        return AppRepositories(
            users: firestoreUsers ?? fallback.users,              // B-017 — users, households
            groups: firestoreGroups ?? fallback.groups,           // B-017 — groups, members
            vendors: firestoreVendors ?? fallback.vendors,        // B-018 — vendors, products
            offers: firestoreOffers ?? fallback.offers,           // B-018 — offers
            groupOrders: fallback.groupOrders,   // B-019 : FirestoreGroupOrderRepository() — groupOrders, shares
            pickupPoints: firestorePickupPoints ?? fallback.pickupPoints,  // B-018 — pickupPoints
            images: firestoreImages ?? fallback.images            // T-122 — users|groups/{id}/media/{nom} (base64)
        )
    }

    /// Dépôts pour le mode choisi au lancement (`FirebaseSetup.configure()`), derrière le cache mémoire (T-112) :
    /// les écrans relus souvent ne refont pas la requête, et les snapshots temps réel tiennent le cache à jour.
    nonisolated static func live(mode: BackendMode, cache: RepositoryCache = RepositoryCache()) -> AppRepositories {
        let repositories: AppRepositories = switch mode {
        case .fake: .fake()
        case .emulator, .demoProject: .firebase()
        }
        return repositories.cached(by: cache)
    }
}
