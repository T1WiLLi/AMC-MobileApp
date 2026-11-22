// AppRepositories+Firebase.swift
// Fabriques des dépôts selon le backend choisi au lancement (B-013).
//
// Brancher un dépôt Firestore (B-017 à B-019) :
//   1. écrire `FirestoreXRepository` dans `Core/Repositories/Firebase/`, conforme au protocole de
//      `RepositoryProtocols.swift`, protégé par `#if canImport(FirebaseFirestore)`, qui RECOIT son Firestore
//      (et son Auth s'il en a besoin) : `init(firestore: Firestore, auth: Auth)`. L'app passe
//      `Firestore.firestore()` / `Auth.auth()` (déjà pointés au bon endroit par `FirebaseSetup.configure()`),
//      les tests passent ceux d'une `FirebaseEmulatorSession` (deux comptes indépendants possibles) ;
//   2. l'ajouter dans `firebase()` ci-dessous (tous les dépôts y sont en Firestore depuis T-127 ; la branche
//      `#else` et l'app non configurée renvoient `.empty()`, jamais `FakeData`) ;
//   3. ouvrir la collection dans `firestore.rules` et ajouter des tests d'intégration marqués
//      `.firestoreEmulator` (voir `AMC-MobileAppTests/Support/FirebaseEmulatorTestSupport.swift`).
// Le même dépôt sert pour l'émulateur et le projet de démo : `FirebaseSetup` a déjà pointé Firestore au bon endroit.

import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif

extension AppRepositories {
    /// Dépôts Firebase : tous en Firestore (S-03, T-127, plus aucune donnée fake quand Firebase est configuré).
    /// Sans FirebaseApp par défaut (tests, configuration ratée), `Firestore.firestore()` planterait : on renvoie
    /// des dépôts VIDES (`.empty()`), jamais les personas de `FakeData`.
    nonisolated static func firebase() -> AppRepositories {
        #if canImport(FirebaseFirestore) && canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { return .empty() }
        var repositories = AppRepositories(
            users: FirestoreUserRepository(),                 // B-017 — users, households
            groups: FirestoreGroupRepository(),               // B-017 — groups, members
            vendors: FirestoreVendorRepository(),             // B-018 — vendors, products
            offers: FirestoreOfferRepository(),               // B-018 — offers
            groupOrders: FirestoreGroupOrderRepository(),     // B-019 — groupOrders, shares
            pickupPoints: FirestorePickupPointRepository(),   // B-018 — pickupPoints
            images: FirestoreImageStore()                     // T-122 — users|groups/{id}/media/{nom} (octets JPEG)
        )
        repositories.wishes = FirestoreGroupWishRepository()        // S-07 — groups/{id}/wishes
        repositories.supplies = FirestoreVendorSupplyRepository()   // S-08 — vendors/{id}/supplies
        repositories.deliveries = FirestoreVolunteerDeliveryRepository()  // RQ-069 — groupOrders/{id}/deliveries
        repositories.organizations = FirestoreOrganizationRepository() // T-116 — organizations, groups/{id}/solidarity
        repositories.boroughStats = FirestoreBoroughStatsRepository() // RQ-093 — boroughStats
        repositories.reviews = FirestoreVendorReviewRepository()     // T-157 — vendorReviews (+ ventes livrées)
        return repositories
        #else
        return .empty()
        #endif
    }

    /// Dépôts pour le mode choisi au lancement (`FirebaseSetup.configure()`), derrière le cache mémoire (T-112) :
    /// les écrans relus souvent ne refont pas la requête, et les snapshots temps réel tiennent le cache à jour.
    nonisolated static func live(mode: BackendMode, cache: RepositoryCache = RepositoryCache()) -> AppRepositories {
        let repositories: AppRepositories = switch mode {
        case .fake: .fake(data: .demo)
        case .emulator, .demoProject: .firebase()
        }
        return repositories.cached(by: cache)
    }
}
