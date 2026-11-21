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

`AMC-MobileApp/GoogleService-Info.plist` est **ignoré par git** (repo public). Le modèle commité est `Config/GoogleService-Info.example.plist`. Sur chaque Mac qui build :

```bash
npx -y firebase-tools@latest login
npx -y firebase-tools@latest apps:sdkconfig IOS 1:959550736484:ios:e6d682a7e2c2b4ebae3771 --project amc-2026-8ab03 -o AMC-MobileApp/GoogleService-Info.plist
```

Il faut avoir accès au projet Firebase (demander à zachary). Le dossier `AMC-MobileApp/` est synchronisé par Xcode : le fichier est inclus dans la cible automatiquement.

**Sans ce fichier, l'app ne plante pas** : `FirebaseSetup.configureIfAvailable()` détecte son absence et l'app tourne sur `FakeAuthService` (utile pour la CI et les previews).

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

- `Core/Auth/FirebaseSetup.swift` : `FirebaseApp.configure()` au lancement (si le plist est là), choix Firebase ou fake.
- `Core/Auth/AuthService.swift` : protocole `AuthService`, `AuthError` (messages en français), `FakeAuthService` (latence simulée, erreur activable).
- `Core/Auth/FirebaseAuthService.swift` : Google Sign-In → `GoogleAuthProvider.credential` → `Auth.auth().signIn(with:)`, écoute de session, déconnexion.
- `Features/Onboarding/` : `SessionViewModel`, `SignInScreen` (bouton « Continuer avec Google »), `SessionGate` (connexion puis `RootView`), compte et déconnexion dans `ProfileScreen`.
- `Config/AMC-MobileApp-Info.plist` : schéma d'URL de retour Google (= `REVERSED_CLIENT_ID`), fusionné avec l'Info.plist généré (`INFOPLIST_FILE`). Ce n'est pas un secret.
- Ordre d'initialisation : `FirebaseSetup` est appelé au début de `AMCMobileApp.init()`, et `SessionViewModel` est créé juste après. Ne créez jamais un objet qui appelle `Auth.auth()` ou `Firestore.firestore()` dans un initialiseur de propriété du `App` (crash « Default FirebaseApp is not configured »). Dans un dépôt, utilisez `lazy var db = Firestore.firestore()`.

## 4. Émulateurs (B-014)

Pour développer sans toucher aux vraies données :

```bash
npx -y firebase-tools@latest emulators:start --only auth,firestore,storage
```

Ports : Auth 9099, Firestore 8080, Storage 9199, interface http://localhost:4000. Le branchement de l'app sur l'émulateur (réglage ou flag) est l'item **B-013**.

## 5. Règles de sécurité

- `firestore.rules` : tout est refusé, sauf ce qu'une règle ouvre explicitement. Les dépôts Firebase (B-017 à B-019) ouvrent chacun leurs collections avec un validateur `isValidX()` appelé en create **et** en update, en suivant le skill Firebase `firestore-rules-creation`. Jamais de lecture d'un document avec de la PII par quelqu'un d'autre que son propriétaire.
- Déployer : `npx -y firebase-tools@latest deploy --only firestore --project amc-2026-8ab03`.
- Avant la démo : restreindre la clé d'API à l'app iOS dans Google Cloud Console, et envisager App Check. Ne jamais committer de jeton de debug App Check.
