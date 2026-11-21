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

```bash
xcodebuild test -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
