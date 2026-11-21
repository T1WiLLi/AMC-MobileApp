---
name: ios26-design
description: Règles de design et d'implémentation SwiftUI pour AMC-MobileApp — tout en iOS 26 natif (Liquid Glass) avec des données fake, et ça doit être beau. À utiliser avant de créer ou modifier une vue, un composant, une navigation, une couleur, une animation, ou des données mock.
---

# iOS 26, données fake, et ça doit être beau

L'app cible **iOS 26.0 uniquement** (Swift 6, SwiftUI). Aucun `if #available` pour des versions plus anciennes.
Tout tourne sur des **données fake** : pas de backend, pas de réseau. L'objectif est une app qui a l'air d'une vraie app Apple de 2026.

Si le skill `apple-design` est disponible dans ton environnement, lis-le aussi : il complète celui-ci (HIG, finition visuelle).

## Liquid Glass d'abord

Le système applique Liquid Glass automatiquement aux barres et contrôles natifs : **utilise les composants natifs** avant d'en dessiner des custom.

- Navigation : `NavigationStack` / `NavigationSplitView`, `TabView` avec la nouvelle API `Tab(...)`.
  - Onglet recherche : `Tab(role: .search)` + `.searchable`.
  - `.tabBarMinimizeBehavior(.onScrollDown)` sur les listes longues.
  - `.tabViewBottomAccessory { … }` pour un mini-player / action persistante.
- Toolbars : `.toolbar { ToolbarItem … }`, `ToolbarSpacer` pour grouper ; laisse le système dessiner le verre, ne mets pas de fond opaque.
- Boutons : `.buttonStyle(.glass)` (secondaire) et `.buttonStyle(.glassProminent)` (action principale, une seule par écran).
- Surfaces custom en verre : `.glassEffect()`, `.glassEffect(.regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 24))`.
  - Plusieurs éléments en verre proches → les mettre dans un `GlassEffectContainer(spacing:)` et utiliser `.glassEffectID(_:in:)` + `@Namespace` pour les morphings.
  - Le verre est pour la **couche de contrôle** (boutons flottants, barres, badges), pas pour le contenu : pas de verre sur verre, pas de cartes de liste entièrement en verre.
- Contenu sous les barres : `.backgroundExtensionEffect()` sur les images héros, `.scrollEdgeEffectStyle(.soft, for: .top)`.
- Sheets : `.presentationDetents([.medium, .large])` ; les sheets iOS 26 sont en verre par défaut, ne leur force pas un fond.
- Coins concentriques : `.rect(corner: .containerConcentric)` / `ConcentricRectangle` pour épouser l'appareil et le conteneur.

## Rendu « beau » — checklist avant chaque PR UI

- **Typo système** : styles dynamiques (`.largeTitle`, `.headline`, `.subheadline`, `.caption`), `.fontDesign(.rounded)` si cohérent avec le reste ; jamais de tailles en dur.
- **Couleurs sémantiques** : `.primary`, `.secondary`, `.tint`, `Color.accentColor`, matériaux. Palette dans l'asset catalog, pas de hex en dur dans les vues. Clair **et** sombre impeccables.
- **SF Symbols** partout, avec `.symbolRenderingMode(.hierarchical)` ou `.palette`, et des `symbolEffect` (`.bounce`, `.replace`) sur les changements d'état.
- **Espacements** : multiples de 4/8, marges système (`.padding()`, `.contentMargins`), alignements nets.
- **Animations** : `withAnimation(.smooth)` / `.spring`, transitions `.matchedGeometryEffect` ou `.navigationTransition(.zoom(sourceID:in:))` entre liste et détail. Retour haptique : `.sensoryFeedback`.
- **États** : chargement (`ProgressView` ou `redacted(reason: .placeholder)`), vide (`ContentUnavailableView`), erreur — tous soignés.
- **Accessibilité** : Dynamic Type jusqu'à AX5 sans troncature cassante, labels VoiceOver, contraste suffisant, cibles ≥ 44 pt, respect de Reduce Motion / Reduce Transparency.
- **Previews** : chaque vue a un `#Preview` avec données fake (et une variante sombre si l'écran est important).
- Vérifie visuellement dans le simulateur (capture d'écran) avant d'ouvrir la PR, et joins la capture à la PR.

## Données fake

- Chaque source de données = un **protocole** de service + une implémentation fake (modèle existant : `ItemService` / `InMemoryItemService` dans `AMC-MobileApp/Services/ItemService.swift`).
- Données fake **réalistes et riches** (vrais noms, dates, montants, images SF Symbols ou assets), en français, assez nombreuses pour remplir les écrans et tester le scroll.
- Simule la latence (`try await Task.sleep(for: .milliseconds(300…800))`) pour que les états de chargement existent vraiment ; prévois un mode erreur activable pour les previews.
- Fixtures partagées dans `AMC-MobileApp/Services/Fake/` (ou `Models/` + extension `static let samples`) : annonce dans le journal du board tout nouveau jeu de données pour que les autres le réutilisent.
- Les ViewModels dépendent du protocole, jamais de l'implémentation fake : un vrai backend pourra se brancher plus tard sans toucher aux vues.

## Architecture

- MVVM : `Views/` (SwiftUI, aucune logique métier), `ViewModels/` (`@Observable`, `@MainActor`), `Models/` (structs `Sendable`, `Identifiable`, `Hashable`), `Services/`.
- Composants réutilisables dans `Views/Components/` — vérifie qu'il n'existe pas déjà (et regarde le journal du board) avant d'en créer un.
- Concurrence stricte Swift 6 : pas de warnings tolérés.
