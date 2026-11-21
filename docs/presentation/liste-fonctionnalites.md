# Liste des fonctionnalités — `[NOM_APP]` (livrable obligatoire)

> À remettre aux organisateurs avec le deck. Mettre à jour le statut **dimanche matin** selon l'état réel du build.
> Statut : **Implémentée** (fonctionne en démo) · **Partielle** (présente mais incomplète — préciser ce qui manque).
> Honnêteté : ne lister comme « Implémentée » que ce qu'un juge peut tester dans l'app.

**Équipe :** `[NOMS]` · **Sphère de Montréal :** `[SPHÈRE]` · **Plateforme :** iOS 26 natif (SwiftUI)

## Fonctionnalités propres à l'idée

| # | Fonctionnalité | Description | Statut | Critère de la grille servi |
|---|---|---|---|---|
| F-01 | `[FEATURE_1]` | `[Ce que fait l'utilisateur et ce qu'il obtient]` | `[Implémentée / Partielle]` | Exactitude, Adéquation au thème |
| F-02 | `[FEATURE_2]` | `[…]` | `[Implémentée / Partielle]` | Originalité, Exactitude |
| F-03 | `[FEATURE_3]` | `[…]` | `[Implémentée / Partielle]` | Facilité d'utilisation, Mission |
| F-04 | `[FEATURE_4]` | `[…]` | `[Implémentée / Partielle]` | `[…]` |
| F-05 | `[INTACT] — Défi Intact` | `[Intégration du défi, annoncé sur place]` | `[Implémentée / Partielle]` | Bonus Intact : pertinence, qualité d'intégration |

## Fonctionnalités transversales

| # | Fonctionnalité | Description | Statut | Critère de la grille servi |
|---|---|---|---|---|
| T-01 | Connexion Google | Connexion en un tap via Google Sign-In et Firebase Auth ; session persistante, déconnexion. | `[Implémentée / Partielle]` | Facilité d'utilisation, Exactitude |
| T-02 | Synchronisation Firestore | Données stockées dans Cloud Firestore, mises à jour en temps réel entre appareils ; cache hors ligne. | `[Implémentée / Partielle]` | Réactivité, Exactitude |
| T-03 | Interface iOS 26 Liquid Glass | Barres, onglets et contrôles en Liquid Glass natif ; animations SwiftUI ; charte cohérente sur tous les écrans. | `[Implémentée / Partielle]` | Esthétique, Cohérence du design, Fluidité |
| T-04 | Accessibilité | Libellés VoiceOver sur les éléments interactifs, Dynamic Type sans troncature, contraste suffisant. | `[Implémentée / Partielle]` | Accessibilité |
| T-05 | États d'erreur et vides | Messages clairs en cas d'échec réseau ou d'authentification, états vides illustrés, indicateurs de chargement, aucun crash. | `[Implémentée / Partielle]` | Gestion des erreurs, Facilité d'utilisation |
| T-06 | Mode sombre | Toutes les vues s'adaptent au mode clair et sombre du système. | `[Implémentée / Partielle]` | Esthétique, Accessibilité |
| T-07 | Architecture MVVM | Vues SwiftUI découplées des ViewModels et des services (Firebase isolé derrière des services). | `[Implémentée / Partielle]` | Exactitude, Fluidité |

## Limites connues / prochaines étapes

- `[Ce qui est simulé ou incomplet, en une ligne chacun]`
- `[Prochaine fonctionnalité prévue après le hackathon]`
