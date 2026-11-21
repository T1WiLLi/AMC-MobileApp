# Firebase — Grenier (AMC-MobileApp)

Backend sans serveur : **Firebase Authentication (Google Sign-In)** + **Cloud Firestore**. Storage viendra avec les photos.

| Élément | Valeur |
|---|---|
| Projet Firebase | `amc-2026-8ab03` (`.firebaserc`) |
| App iOS enregistrée | « AMC iOS », bundle ID **`ca.amc2026.mobileapp`** (tests : `ca.amc2026.mobileapp.tests`) |
| Firestore | Standard, base `(default)`, `northamerica-northeast1` (Montréal) |
| Auth | fournisseur Google activé |
| Règles | `firestore.rules` et `storage.rules` : **tout refusé par défaut** (voir plus bas) |

## 1. Récupérer la vraie config (B-012)

`AMC-MobileApp/GoogleService-Info.plist` est **ignoré par git** (repo public). Le modèle commité est `Config/GoogleService-Info.example.plist`. Deux façons de l'obtenir sur un Mac qui build :

### a) Avec le `.env` de l'équipe (le plus rapide, sans compte Firebase)

Le `.env` (racine du repo, **ignoré par git**) contient les valeurs de la config iOS. Les clés attendues sont dans `.env.example` (commité, sans valeurs). Récupère le `.env` auprès d'un coéquipier en message direct (jamais dans une issue, une PR ou le board), pose-le à la racine du repo, puis :

```bash
scripts/firebase/generate-plist.sh
```

Le script lit le `.env` sans l'exécuter, vérifie qu'il ne manque rien, écrit `AMC-MobileApp/GoogleService-Info.plist`, le valide avec `plutil`, et prévient si `REVERSED_CLIENT_ID` ne correspond pas au schéma d'URL de `Config/AMC-MobileApp-Info.plist`. Dans un worktree : `scripts/firebase/generate-plist.sh /chemin/vers/le/.env`.

### b) Avec la CLI Firebase (il faut l'accès au projet : demander à zachary)

```bash
npx -y firebase-tools@latest login
npx -y firebase-tools@latest apps:sdkconfig IOS 1:959550736484:ios:e6d682a7e2c2b4ebae3771 --project amc-2026-8ab03 -o AMC-MobileApp/GoogleService-Info.plist
```

Pour remplir un `.env` à partir de ce plist : `FIREBASE_API_KEY` = `API_KEY`, `FIREBASE_GCM_SENDER_ID` = `GCM_SENDER_ID`, `FIREBASE_GOOGLE_APP_ID` = `GOOGLE_APP_ID`, `FIREBASE_BUNDLE_ID` = `BUNDLE_ID`, `FIREBASE_CLIENT_ID` = `CLIENT_ID`, `FIREBASE_REVERSED_CLIENT_ID` = `REVERSED_CLIENT_ID`, `FIREBASE_STORAGE_BUCKET` = `STORAGE_BUCKET`, `FIREBASE_PROJECT_ID` = `PROJECT_ID`, et `FIREBASE_IOS_APP_ID` = l'ID d'app ci-dessus.

Le dossier `AMC-MobileApp/` est synchronisé par Xcode : le plist est inclus dans la cible automatiquement. Au lancement, la console Xcode n'affiche plus « GoogleService-Info.plist absent : services fake ».

**Sans ce fichier, l'app ne plante pas** : `FirebaseSetup.configure()` détecte son absence et l'app tourne en mode `fake` (`FakeAuthService`, `AppRepositories.fake()`), utile pour la CI et les previews.

**Ne jamais committer `.env` ni le plist.** Vérifier : `git check-ignore -v .env AMC-MobileApp/GoogleService-Info.plist` doit lister les deux.

### MCP Firebase (agents Claude Code)

Le serveur MCP officiel vient de firebase-tools. Installation, une fois par Mac, à la racine du repo :

```bash
claude mcp add --scope local firebase -- npx -y firebase-tools@latest mcp --dir "$(pwd)"
```

Il réutilise la session de `firebase login`. `claude mcp get firebase` doit afficher « Connected ».

## 2. Lier le SDK (B-011, sur un Mac, une seule fois)

Ça modifie `project.pbxproj` : une seule personne, annoncé sur le board. Utilise le skill Firebase `xcode-project-setup` (il ajoute aussi `-ObjC` à `OTHER_LDFLAGS`) :

```bash
swift run --package-path <skill xcode-project-setup>/scripts/xcode_spm_setup xcode_spm_setup \
  AMC-MobileApp.xcodeproj https://github.com/firebase/firebase-ios-sdk 13.2.0 \
  FirebaseCore FirebaseAuth FirebaseFirestore FirebaseStorage

swift run --package-path <skill xcode-project-setup>/scripts/xcode_spm_setup xcode_spm_setup \
  AMC-MobileApp.xcodeproj https://github.com/google/GoogleSignIn-iOS 10.1.0 \
  GoogleSignIn
```

Vérifie la dernière version de chaque paquet avant (releases GitHub). Sans le skill : Xcode › File › Add Package Dependencies…, mêmes produits, puis `-ObjC` dans Other Linker Flags.
**Ne jamais ajouter `FirebaseFirestoreSwift`** (fusionné dans `FirebaseFirestore` depuis la v11).

Tout le code Firebase est protégé par `#if canImport(...)` : le build reste vert avant cette étape, et Firebase s'active tout seul après.

## 3. Ce qui est déjà branché

- `Core/Auth/BackendMode.swift` : choix du backend (`fake`, `emulator`, `demoProject`) à partir des arguments de lancement (B-013, voir §4).
- `Core/Auth/FirebaseSetup.swift` : `configure()` au lancement — choisit le mode, appelle `FirebaseApp.configure()` et branche les émulateurs ; `makeAuthService(mode:)`.
- `Core/Repositories/AppRepositories+Live.swift` : `AppRepositories.live(mode:)` et `AppRepositories.firebase()` (les dépôts Firestore B-017 à B-019 s'y branchent, une ligne chacun).
- `Core/Auth/AuthService.swift` : protocole `AuthService`, `AuthError` (messages en français), `FakeAuthService` (latence simulée, erreur activable).
- `Core/Auth/FirebaseAuthService.swift` : Google Sign-In → `GoogleAuthProvider.credential` → `Auth.auth().signIn(with:)`, écoute de session, déconnexion.
- `Features/Onboarding/` : `SessionViewModel`, `SignInScreen` (bouton « Continuer avec Google »), `SessionGate` (connexion puis `RootView`), compte et déconnexion dans `ProfileScreen`.
- `Config/AMC-MobileApp-Info.plist` : schéma d'URL de retour Google (= `REVERSED_CLIENT_ID`), fusionné avec l'Info.plist généré (`INFOPLIST_FILE`). Ce n'est pas un secret.
- Ordre d'initialisation : `FirebaseSetup` est appelé au début de `AMCMobileApp.init()`, et `SessionViewModel` est créé juste après. Ne créez jamais un objet qui appelle `Auth.auth()` ou `Firestore.firestore()` dans un initialiseur de propriété du `App` (crash « Default FirebaseApp is not configured »). Dans un dépôt, utilisez `lazy var db = Firestore.firestore()`.

## 4. Émulateurs (B-014, B-013)

Pour développer sans toucher aux vraies données. Il faut Node et Java (`java -version`).

```bash
npx -y firebase-tools@latest emulators:start --only auth,firestore,storage
```

Ports (`firebase.json`) : Auth 9099, Firestore 8080, Storage 9199, interface http://localhost:4000. Les règles `firestore.rules` et `storage.rules` sont chargées par l'émulateur.

### Lancer l'app sur l'émulateur

Le backend est choisi au lancement (`BackendMode`) et écrit dans le log (`Backend : …`, catégorie `Backend`) :

| Mode | Quand |
|---|---|
| `fake` | `GoogleService-Info.plist` absent (CI, previews, repo fraîchement cloné), ou argument `-useFakeBackend YES` |
| `emulator` | argument `-useFirebaseEmulator YES` (Debug seulement) |
| `demoProject` | sinon ; **toujours en Release** (les arguments sont ignorés) |

- **Xcode** : le schéma partagé `AMC-MobileApp` contient déjà les deux arguments, décochés. Product › Scheme › Edit Scheme… › Run › Arguments, cocher `-useFirebaseEmulator YES` (ou `-useFakeBackend YES`). Les tests n'utilisent pas ces arguments.
- **Ligne de commande** : `xcrun simctl launch booted ca.amc2026.mobileapp -useFirebaseEmulator YES`.
- Variables d'environnement équivalentes (pratique dans un schéma perso) : `USE_FIREBASE_EMULATOR=1`, `USE_FAKE_BACKEND=1`. Un argument présent l'emporte sur la variable.
- Hôte : `127.0.0.1` (marche sur le simulateur). Sur un iPhone réel : `-firebaseEmulatorHost <IP du Mac>` (ou `FIREBASE_EMULATOR_HOST`), et `"host": "0.0.0.0"` pour chaque émulateur dans un `firebase.json` local.
- Le plist doit être présent (sinon c'est `fake`) ; l'émulateur utilise son `PROJECT_ID` (`amc-2026-8ab03`).
- `FirebaseSetup.configure()` applique les réglages d'émulateur juste après `FirebaseApp.configure()` et avant tout `Auth.auth()`, `Firestore.firestore()` ou `Storage.storage()` : ne créez jamais ces objets avant (crash). En mode émulateur, le cache Firestore est en mémoire (pas de mélange avec le cache du projet de démo).

### Tests d'intégration sur l'émulateur

`AMC-MobileAppTests/Support/FirebaseEmulator.swift` :

- trait `.firestoreEmulator` : le test ou la suite ne tourne que si l'émulateur Firestore répond sur `127.0.0.1:8080` ; sinon il est sauté (CI, Mac sans émulateur) ;
- `FirebaseEmulator.clearFirestore()` vide la base entre deux tests (`DELETE …/emulator/v1/projects/amc-2026-8ab03/databases/(default)/documents`), `clearAuth()` supprime les comptes ;
- `FirebaseEmulator.send(method:to:json:)` fait une requête REST en `Bearer owner` (contourne les règles, pour préparer des données).

```swift
@Suite(.serialized, .firestoreEmulator)
struct FirestoreOfferRepositoryTests {
    @Test func saveThenRead() async throws {
        try await FirebaseEmulator.clearFirestore()
        // …
    }
}
```

Lancer les émulateurs, puis les tests comme d'habitude (`xcodebuild test … -parallel-testing-enabled NO`) : les suites `.firestoreEmulator` passent de « skipped » à exécutées.

## 5. Règles de sécurité

- `firestore.rules` : tout est refusé, sauf ce qu'une règle ouvre explicitement. Les dépôts Firebase (B-017 à B-019) ouvrent chacun leurs collections avec un validateur `isValidX()` appelé en create **et** en update, en suivant le skill Firebase `firestore-rules-creation`. Jamais de lecture d'un document avec de la PII par quelqu'un d'autre que son propriétaire.
- Déployer : `npx -y firebase-tools@latest deploy --only firestore --project amc-2026-8ab03`.
- Avant la démo : restreindre la clé d'API à l'app iOS dans Google Cloud Console, et envisager App Check. Ne jamais committer de jeton de debug App Check.
