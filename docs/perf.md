# Mesures de performance (S-11, étape 1)

On mesure avant d'optimiser. L'app émet des signposts (`os_signpost`) et une ligne de journal avec la durée
en ms pour chaque mesure, sous :

- sous-système : `ca.amc2026.mobileapp` (le bundle id) ;
- catégorie : `Perf`.

Façade : `AMC-MobileApp/Core/Diagnostics/PerfSignposts.swift` (`measure`, `begin`/`end`, `markFirstScreen`).
Active en Debug, en Release avec l'argument de lancement `-PerfSignposts`, et dès qu'Instruments enregistre.
Sinon elle ne fait rien (le bloc est juste appelé).

## Ce qui est mesuré

| Nom du signpost | Où | Ce que ça couvre |
| --- | --- | --- |
| `launch.backendSetup` | `App/AMCMobileApp.swift` (`init`) | `FirebaseSetup.configure()` : choix du backend, `FirebaseApp.configure`, émulateurs |
| `firebase.connect` | `Core/Auth/FirebaseSetup.swift` | Branchement Auth, Firestore et Storage sur l'émulateur (mode émulateur seulement) |
| `launch.firstScreen` | `App/AMCMobileApp.swift` (`onAppear` de `SessionGate`) | Événement ; le journal donne le temps depuis le lancement du processus (avant `main`) |
| `auth.sessionRestore` | `Core/Auth/FirebaseAuthService.swift` | De l'abonnement à l'état Auth jusqu'au premier callback (session restaurée ou absente) |
| `firestore.activeOffers` | `FirestoreOfferRepository.activeOffers(inZone:)` | Fil des lots actifs par zone |
| `firestore.groupOrdersOfGroup` | `FirestoreGroupOrderRepository.groupOrders(ofGroup:)` | Commandes d'un groupe |
| `firestore.productsOfVendor` | `FirestoreVendorRepository.products(ofVendor:)` | Produits d'un vendeur |
| `firestore.observeGroupOrder.firstSnapshot` | `FirestoreGroupOrderRepository.observeGroupOrder(id:)` | De l'écoute au premier snapshot |

Pas encore mesuré : les groupes du ménage (`groups(ofHousehold:)`), faute de dépôt Firestore des groupes sur `main`.
À ajouter avec une ligne `PerfSignposts.measure("firestore.groupsOfHousehold") { … }` quand il arrivera.

## Relever les mesures

### Sans Instruments (journal)

Simulateur démarré, app lancée depuis Xcode ou `simctl` :

```bash
xcrun simctl spawn booted log stream --level info \
  --predicate 'subsystem == "ca.amc2026.mobileapp" AND category == "Perf"'
```

Chaque ligne ressemble à `firestore.activeOffers : 412.3 ms`. Sur un appareil, même prédicat dans Console.app
(activer « Inclure les messages Info »).

Démarrage à froid : quitter l'app (`xcrun simctl terminate booted ca.amc2026.mobileapp`), puis la relancer
(`xcrun simctl launch booted ca.amc2026.mobileapp`). Pour un démarrage sans cache Firestore, supprimer et
réinstaller l'app avant.

### Avec Instruments

Product > Profile (⌘I), modèle « App Launch » ou « Time Profiler », ajouter l'instrument « os_signpost »
(ou « Points of Interest »), filtrer sur le sous-système ci-dessus. Les intervalles s'affichent par nom.

En Release, ajouter `-PerfSignposts` aux arguments de lancement du schéma si on veut aussi le journal.

## Résultats

Cibles : accueil affiché en **< 1 s avec cache**, **< 2,5 s sans cache**.

Faire 3 démarrages par ligne et noter la médiane. Indiquer l'appareil, le mode (fake, émulateur, démo) et le réseau.

| Mesure | Cible | Sans cache (ms) | Avec cache (ms) | Appareil / mode / réseau | Date |
| --- | --- | --- | --- | --- | --- |
| `launch.backendSetup` | | | | | |
| `firebase.connect` | | | | | |
| `launch.firstScreen` | < 1 s (cache), < 2,5 s | | | | |
| `auth.sessionRestore` | | | | | |
| `firestore.activeOffers` | | | | | |
| `firestore.groupOrdersOfGroup` | | | | | |
| `firestore.productsOfVendor` | | | | | |
| `firestore.observeGroupOrder.firstSnapshot` | | | | | |
| Accueil affiché (premier écran + fil des lots) | < 1 s (cache), < 2,5 s | | | | |

Repère en mode fake (iPhone 17 simulateur, sans Firebase) : voir la PR T-111.
