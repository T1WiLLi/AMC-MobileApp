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
- `Core/Repositories/Firebase/AppRepositories+Firebase.swift` : `AppRepositories.live(mode:)` et `AppRepositories.firebase()` (les dépôts Firestore B-017 à B-019 s'y branchent, une ligne chacun ; ils reçoivent leur `Firestore`/`Auth` par `init`).
- `Core/Auth/FirebaseEmulatorSession.swift` (Debug) : app Firebase nommée sur l'émulateur, pour avoir plusieurs comptes connectés en même temps dans les tests.
- `Core/Auth/AuthService.swift` : protocole `AuthService`, `AuthError` (messages en français), `FakeAuthService` (latence simulée, erreur activable).
- `Core/Auth/FirebaseAuthService.swift` : Google Sign-In → `GoogleAuthProvider.credential` → `Auth.auth().signIn(with:)`, écoute de session, déconnexion.
- `Features/Onboarding/` : `SessionViewModel`, `SignInScreen` (bouton « Continuer avec Google »), `SessionGate` (connexion puis `RootView`), compte et déconnexion dans `ProfileScreen`.
- `Config/AMC-MobileApp-Info.plist` : schéma d'URL de retour Google (= `REVERSED_CLIENT_ID`), fusionné avec l'Info.plist généré (`INFOPLIST_FILE`). Ce n'est pas un secret.
- Se connecter avec Apple (RQ-012, T-074) : `Core/Auth/AppleSignIn.swift` (nonce, SHA-256, erreurs), `SessionViewModel.prepareAppleSignIn` / `completeAppleSignIn`, `FirebaseAuthService.signInWithApple` (`OAuthProvider.appleCredential`, fournisseur `apple.com`). Bouton `SignInWithAppleButton` au-dessus de Google dans `SignInScreen`.
  - **Flag** : clé `GRNSignInWithAppleEnabled` de `Config/AMC-MobileApp-Info.plist` (`true` par défaut). Absente ou `false` → bouton caché.
  - **Entitlement** : `Config/AMC-MobileApp.entitlements` (`com.apple.developer.applesignin`), branché par `CODE_SIGN_ENTITLEMENTS` dans la cible app.
  - **Non vérifié, à faire par la personne qui signe** : (1) l'App ID `ca.amc2026.mobileapp` doit avoir la capability *Sign in with Apple* (Apple Developer › Identifiers ; Xcode l'ajoute avec la signature automatique). Un compte gratuit (« Personal Team ») ne la propose pas : la build sur iPhone échoue alors au provisioning. Dans ce cas, retirer `CODE_SIGN_ENTITLEMENTS` en local (pas en commit) et passer le flag à `false`. (2) Console Firebase › Authentication › Sign-in method : activer **Apple** (pour une app iOS native, aucun Services ID ni clé n'est nécessaire). Sinon l'app affiche « La connexion avec Apple n'est pas encore activée ».
  - Simulateur : il faut être connecté à un compte Apple dans Réglages du simulateur ; une build sans signature (`CODE_SIGNING_ALLOWED=NO`) n'a pas l'entitlement et Apple répond par une erreur.
- Ordre d'initialisation : `FirebaseSetup` est appelé au début de `AMCMobileApp.init()`, et `SessionViewModel` est créé juste après. Ne créez jamais un objet qui appelle `Auth.auth()` ou `Firestore.firestore()` dans un initialiseur de propriété du `App` (crash « Default FirebaseApp is not configured »). Dans un dépôt, utilisez `lazy var db = Firestore.firestore()`.

## 4. Émulateurs (B-014, B-013)

Pour développer sans toucher aux vraies données. Il faut Node et Java (`java -version`).

```bash
npx -y firebase-tools@latest emulators:start --only auth,firestore,storage --project demo-grenier
```

Projet local **`demo-grenier`** (accepté par zachary) : le préfixe `demo-` garantit qu'aucune ressource réelle n'est touchée, et aucun login n'est nécessaire. `--project demo-grenier` est obligatoire (sinon `.firebaserc` impose `amc-2026-8ab03`, qui ne correspondrait pas à l'app).

Ports (`firebase.json`) : Auth 9099, Firestore 8080, Storage 9199, interface http://localhost:4000. Les règles `firestore.rules` et `storage.rules` sont chargées par l'émulateur.

### Lancer l'app sur l'émulateur

Le backend est choisi au lancement (`BackendMode`) et écrit dans le log (`Backend : …`, catégorie `Backend`) :

| Mode | Quand |
|---|---|
| `fake` | SDK non lié, tests unitaires (app hôte XCTest), `GoogleService-Info.plist` absent sans argument émulateur (CI, previews, repo fraîchement cloné), ou argument `-useFakeData` / `-useFakeBackend YES` |
| `emulator` | argument `-useEmulator` / `-useFirebaseEmulator YES` (le plist n'est pas nécessaire) |
| `demoProject` | sinon, dès que le plist est là, **en Debug comme en Release** (T-127 : plus aucune donnée fake ; seuls les arguments explicites ci-dessus l'évitent) |

- **Xcode** : le schéma partagé `AMC-MobileApp` contient déjà les deux arguments, décochés. Product › Scheme › Edit Scheme… › Run › Arguments, cocher `-useFirebaseEmulator YES` (ou `-useFakeBackend YES`). Les tests n'utilisent pas ces arguments.
- **Ligne de commande** : `xcrun simctl launch booted ca.amc2026.mobileapp -useFirebaseEmulator YES`.
- Variables d'environnement équivalentes (pratique dans un schéma perso) : `USE_FIREBASE_EMULATOR=1`, `USE_FAKE_BACKEND=1`. Un argument présent l'emporte sur la variable.
- Hôte : `127.0.0.1` (marche sur le simulateur). Sur un iPhone réel : `-firebaseEmulatorHost <IP du Mac>` (ou `FIREBASE_EMULATOR_HOST`), et `"host": "0.0.0.0"` pour chaque émulateur dans un `firebase.json` local.
- Projet : toujours `demo-grenier` en mode émulateur. Si le plist est là, ses autres valeurs sont gardées (Google Sign-In reste utilisable, l'émulateur Auth accepte le jeton Google) ; sinon des valeurs factices sont utilisées.
- `FirebaseSetup.configureIfAvailable()` existe toujours (renvoie true si Firebase est actif) ; il appelle `configure()`.
- `FirebaseSetup.configure()` applique les réglages d'émulateur juste après `FirebaseApp.configure()` et avant tout `Auth.auth()`, `Firestore.firestore()` ou `Storage.storage()` : ne créez jamais ces objets avant (crash). En mode émulateur, le cache Firestore est en mémoire (pas de mélange avec le cache du projet de démo).

### Tests d'intégration sur l'émulateur

`AMC-MobileAppTests/Support/FirebaseEmulatorTestSupport.swift` (`@MainActor enum FirebaseEmulatorTestSupport`) :

- trait `.firestoreEmulator` : le test ou la suite ne tourne que si l'émulateur Firestore répond sur `127.0.0.1:8080` ; sinon il est sauté (CI, Mac sans émulateur) ;
- `clearFirestore()` vide la base entre deux tests (`DELETE http://127.0.0.1:8080/emulator/v1/projects/demo-grenier/databases/(default)/documents`), `clearAuth()` supprime les comptes ;
- `session("vendor")`, `session("family")` : deux `FirebaseEmulatorSession` indépendantes (apps Firebase nommées du projet `demo-grenier`), chacune avec son `auth`, son `firestore`, `projectID` et `host` ; à injecter dans les dépôts Firestore ;
- gardes : `session` refuse tout projet sans préfixe `demo-` ou hôte non local (`FirebaseSetup.isEmulatorTarget`), `send(method:to:json:)` refuse toute URL hors émulateur ; `send` utilise `Bearer owner` (contourne les règles, pour préparer des données).

```swift
@MainActor @Suite(.serialized, .firestoreEmulator)
struct FirestoreOfferRepositoryTests {
    @Test func saveThenRead() async throws {
        try await FirebaseEmulatorTestSupport.clearFirestore()
        let vendor = try FirebaseEmulatorTestSupport.session("vendor")
        let repo = FirestoreOfferRepository(firestore: vendor.firestore, auth: vendor.auth)
        // …
    }
}
```

Lancer les émulateurs (`--project demo-grenier`), puis les tests comme d'habitude (`xcodebuild test … -parallel-testing-enabled NO`) : les suites `.firestoreEmulator` passent de « skipped » à exécutées.

## 5. Règles de sécurité

`firestore.rules` et `storage.rules` ouvrent le minimum pour que l'app lise et écrive en vrai :

| Chemin | Lecture | Écriture |
|---|---|---|
| `groups`, `vendors`, `products`, `offers`, `groupOrders`, `pickupPoints` | tout utilisateur connecté | `products`/`offers` : le vendeur propriétaire ; `vendors` : sa vitrine ; `pickupPoints` : l'hôte (créneaux, capacité) ; `groups`, `groupOrders` : personne (seed) |
| `users/{uid}` | le propriétaire | le propriétaire, **sans jamais poser `vendorId`** (rattachement vendeur = seed ou admin) |
| `households/{id}` et `households/{id}/private/profile` | les membres (`userIds`) | les membres |
| `groups/{id}/members/{householdId}` | connectés | le ménage s'ajoute (`role: member`) ou se retire |
| `groupOrders/{id}/shares/{householdId}` | membres du groupe (ménage vérifié dans `households.userIds`), vendeur du lot | le ménage, commande `open`/`reached` avant la date limite, avec la commande recalculée dans la même transaction : quantité et panier suspendu (≤ 200 $) ; à la clôture, coordonnateur ou vendeur : prix = quantité × palier figé, subvention ≤ prix et seulement pour un ménage subventionné, QR de la commande ; `isPaid`, `isPickedUp` hors de portée du client |
| Storage `vendors/{vendorId}/…`, `users/{uid}/…` | connectés | le vendeur rattaché / le propriétaire ; images de moins de 5 Mo |

Tout le reste est refusé. Chaque collection a un validateur de forme (champs permis, types, tailles).

Attaques couvertes par `scripts/rules-tests/firestore.attacks.test.ts` (T-093) : palier, compteurs et statut d'une commande recalculés et vérifiés, paliers d'un lot triés et valides, date limite jamais reculée dans le passé, lot publié non supprimable, `users.householdId` vérifié dans le ménage. Limites connues :

- la clôture lit le profil privé de chaque ménage subventionné : au plus ~16 ménages subventionnés par commande (limite de 20 documents lus par transaction) ; le nombre total de ménages n'est pas limité (testé jusqu'à 60) ;
- le total des subventions n'est pas borné par le fonds (le fonds n'est pas stocké dans Firestore), et `subsidyCents` est lisible par tous les membres du groupe (TODO E10) ;
- un code d'organisme bien formé suffit pour se déclarer subventionné (pas encore de liste de codes émis).

Tests (émulateur sur des ports à part, pour ne pas gêner les émulateurs des autres agents) :

```bash
npm --prefix scripts/rules-tests ci
npm --prefix scripts/rules-tests run test:emulators
```

Déployer **seulement si les tests passent** :

```bash
npx -y firebase-tools@latest deploy --only firestore:rules --project amc-2026-8ab03
```

Storage n'est pas encore initialisé sur le projet (aucune règle déployée) : l'activer dans la console (Storage › Commencer) puis `deploy --only storage`.

## 6. Données de démo dans Firestore

`scripts/seed/seedFirestore.ts` écrit les fixtures de `scripts/seed/fixtures/` (vendeurs, produits, lots, personas, groupes et membres, points de cueillette, ménages et leur profil privé, commandes groupées et parts) à des ids stables. **Il ne supprime rien** (contrairement à `seedDemo.ts`, qui vide l'émulateur et ses comptes Auth) : on peut le relancer, la démo revient à son état initial. Les échéances et créneaux partent du jour du seed (heure de Montréal).

```bash
npm --prefix scripts/seed ci
npm --prefix scripts/seed run seed:firestore -- --dry-run                      # compte les documents
npm --prefix scripts/seed run seed:firestore                                   # émulateur 127.0.0.1:8080, projet amc-2026-8ab03
npm --prefix scripts/seed run seed:firestore -- --target cloud --yes           # VRAI projet, session de firebase login
```

Sur le vrai projet, le script prend le jeton de `firebase login` (pas de clé de service).

Il crée aussi (ou remet à jour) un compte Auth courriel par utilisateur de `users.json`, avec uid = id du document (B-029), sans toucher aux autres comptes. Pour jouer le parcours, connectez-vous dans l'app avec `amina@demo.grenier.local` (famille), `ferme-lafleur@demo.grenier.local` (vendeur) ou `jean@demo.grenier.local` (hôte). Le mot de passe commun vient de `GRENIER_DEMO_PASSWORD` ; sans cette variable, le script en génère un, l'applique à tous les comptes de démo et l'affiche une seule fois. Il n'est jamais versionné : gardez-le dans un gestionnaire de mots de passe. Le fournisseur « Adresse e-mail/Mot de passe » doit être activé dans la console Firebase.

```bash
GRENIER_DEMO_PASSWORD='…' npm --prefix scripts/seed run seed:firestore -- --target cloud --yes
```

## 7. Recommandations avant la démo publique

- Restreindre la clé d'API iOS (Google Cloud Console › Identifiants) aux API Firebase utilisées et à l'app `ca.amc2026.mobileapp` : aujourd'hui elle répond sans restriction.
- Activer App Check (App Attest) ; ne jamais committer de jeton de debug.
- `groups.inviteCode` est lisible par tout utilisateur connecté : le déplacer dans une sous-collection privée avant d'avoir de vrais groupes privés.
- Les lots en brouillon (`status: draft`) sont lisibles par les connectés : filtrer côté app.
- Activer la protection contre la suppression de la base `(default)`.
