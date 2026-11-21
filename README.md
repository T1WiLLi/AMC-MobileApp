# Grenier (AMC-MobileApp)

Grenier permet aux familles d'un quartier de Montréal de se regrouper pour acheter les produits de base en gros, directement aux producteurs. App iOS 26 en SwiftUI (MVVM, Swift 6), backend Firebase sans serveur.

Vision, exigences et backlog : le doc de coordination des agents (onglets Projet, Requis, Backlog). Règles des agents : `AGENTS.md` et `.claude/skills/`.

## Structure

```
AMC-MobileApp/
├── App/                  Point d'entrée (@main) et RootView
├── Core/                 Code partagé par toutes les fonctionnalités
│   ├── Models/           Types Codable et Sendable du modèle Firestore
│   ├── Repositories/     Protocoles de dépôt + implémentations Firebase et fake
│   ├── Design/           Couleurs, typo, composants réutilisables (Components/)
│   └── Errors/           AppError, LoadState, vues d'état
├── Features/             Une fonctionnalité = un dossier (Views + ViewModels)
│   ├── Onboarding/       Accueil, connexion, choix du profil
│   ├── Groups/           Groupes de quartier
│   ├── Offers/           Lots et commande de sa part
│   ├── Orders/           Panier, commandes, paiement simulé
│   ├── Pickup/           Points de cueillette, QR, checklist de l'hôte
│   ├── Vendor/           Portail Vendeur
│   ├── Solidarity/       Paniers suspendus, organismes
│   └── Impact/           Économies et impact sur Montréal
└── Assets.xcassets
AMC-MobileAppTests/       Tests Swift Testing
```

Règles :

- Une vue ne contient aucune logique métier ; elle lit un ViewModel `@Observable` (`@MainActor` par défaut).
- Les ViewModels dépendent des protocoles de `Core/Repositories`, jamais de Firebase directement.
- Le projet utilise des dossiers synchronisés (Xcode 16+) : un nouveau fichier dans `AMC-MobileApp/` est inclus automatiquement, sans toucher au `project.pbxproj`.
- Les fichiers `*Folder.swift` (un commentaire seulement) gardent les dossiers vides dans git ; supprimez-le quand vous ajoutez le premier vrai fichier. Pas de `.gitkeep` : Xcode les copierait dans l'app et le build échouerait.

## Build et tests

Chaque pull request vers `main` lance le workflow GitHub Actions **iOS CI**. Le runner `macos-26` vérifie qu’il utilise Xcode 26, compile le projet et exécute les tests sur un seul iPhone 17 avec le runtime iOS disponible le plus récent. Un échec de compilation ou de test fait échouer le check **Build and test (iOS)**. Le workflow fonctionne sans signature ni secret à configurer.

Pour reproduire les vérifications localement avec Xcode 26, utilisez un simulateur iOS 26 installé. `xcrun simctl list devices available` liste les simulateurs disponibles. Adaptez `destination` au besoin.

```bash
destination='platform=iOS Simulator,name=iPhone 17,OS=latest'
xcodebuild -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
  -destination "$destination" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
  -destination "$destination" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```
