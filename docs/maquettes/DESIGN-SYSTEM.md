# Design system Grenier

Source de vérité pour l'UI de Grenier (iOS 26, SwiftUI, Liquid Glass). Image de référence : [`00-design-system.png`](00-design-system.png). Règles générales iOS 26 : skill `.claude/skills/ios26-design`.

Agents : lisez ce fichier avant de créer ou modifier une vue, une couleur ou un composant. Un changement de token ou de composant passe par une PR qui modifie ce fichier et s'annonce dans le Journal du board.

## Couleurs

Toutes dans l'asset catalog (`Assets.xcassets`), avec une variante claire et une sombre. Dans le code : `Color("Nom")` (ou une extension `Color.grenier`, etc.), jamais de hex dans les vues.

| Nom d'asset | Clair | Sombre | Usage |
| --- | --- | --- | --- |
| `Fond` | `#FBF7F0` | `#14110E` | Fond des écrans |
| `Surface` | `#FFFFFF` | `#211D19` | Cartes, listes, champs |
| `Texte` | `#1C1712` | `#F5EFE6` | Texte principal (ou `.primary`) |
| `TexteSecondaire` | `#6B5F53` | `#B8AC9F` | Sous-titres, légendes (ou `.secondary`) |
| `AccentColor` (Grenier) | `#B4521A` | `#F08A4B` | Actions, paliers, onglet actif, `.tint` |
| `Economie` | `#1F7A4A` | `#4CC488` | Argent économisé seulement, jamais une action |
| `Solidarite` | `#6B4FB3` | `#A992F0` | Panier suspendu, aide anonyme |
| `Separateur` | `#E8DFD3` | `#3A332D` | Séparateurs, bordures fines |
| `Piste` | `#EFE6DA` | `#3A332D` | Fond vide des barres de palier |

Contraste : texte blanc sur Grenier, Economie et Solidarite en clair (5:1 ou plus). En sombre, texte `#1C1712` sur ces couleurs.

Teintes légères : couleur à 12 % d'opacité pour les fonds de badge et les carrés d'icône (`Color.economie.opacity(0.12)`).

## Typographie

Styles dynamiques uniquement (Dynamic Type jusqu'à AX5), jamais de taille en dur.

| Style SwiftUI | Exemple | Usage |
| --- | --- | --- |
| `.largeTitle.bold()` | Bonjour Amina | Titre d'écran |
| `.title2.bold()` | Riz basmati, 200 kg | Titre de fiche |
| `.headline` | Parc-Ex Ouest | Nom dans une carte |
| `.body` | Ta part est réservée jusqu'à jeudi. | Texte courant |
| `.subheadline` + `.foregroundStyle(.secondary)` | Ferme Lafleur · Mirabel | Sous-titre, méta |
| `.caption` + `.secondary` | 1–10 · 3,20 $ | Libellés de paliers |
| `.title.bold()` + `.fontDesign(.rounded)` | 2,60 $/kg | Tous les montants et prix |

Montants : format québécois, `2,60 $`, espace insécable avant `$`, `.monospacedDigit()` quand ils changent.

## Icônes (SF Symbols)

`.symbolRenderingMode(.hierarchical)` par défaut.

| Sens | Symbole |
| --- | --- |
| Accueil | `house.fill` |
| Groupes | `person.3.fill` |
| Lots | `shippingbox.fill` |
| Cueillette / QR | `qrcode` |
| Carte | `map.fill` |
| Prix qui baisse | `chart.line.downtrend.xyaxis` |
| Solidarité | `heart.fill` (teinte Solidarite) |
| Impact | `leaf.fill` |
| Palier débloqué | `checkmark.seal.fill` |

## Espacements et formes

- Grille de 4 / 8 pt ; marges d'écran 16 pt ; écart entre cartes 12 pt.
- Cartes : `Surface`, coins 24 (`.rect(cornerRadius: 24)`), pas d'ombre forte (au plus `radius 8, y 2, opacité 0.06`).
- Carrés d'icône : 52 pt, coins 14, teinte légère.
- Cibles tactiles : 44 pt minimum.

## Composants (`AMC-MobileApp/Core/Design/Components/`)

### `TierProgressBar`
Montre les paliers d'un lot et où en est le groupe.
- 3 segments arrondis, hauteur 10, écart 4 ; remplis en `AccentColor`, vides en `Piste`.
- Sous chaque segment, en `.caption` : « 1–10 · 3,20 $ », « 11–25 · 2,60 $ », « 26+ · 2,10 $ » ; palier courant en gras.
- Phrase d'incitation en `AccentColor`, `.subheadline.weight(.semibold)` : « Encore 1 famille pour débloquer −19 % ».
- Variante `compact` : hauteur 6, sans libellés, pour `OfferCard`.
- Entrées : `tiers: [Tier]` (min, max, prix), `current: Int` (familles), `compact: Bool`.

### `PriceTag`
- Prix courant en `.title.bold()` rounded + unité `/kg` en `.subheadline`.
- Prix épicerie barré (`.strikethrough()`), `.subheadline`, `.secondary` : « épicerie 4,10 $ ».
- `.contentTransition(.numericText())` quand le palier change.

### `SavingsBadge`
- Pilule (capsule), padding 6 × 10.
- `filled` : fond `Economie`, texte blanc — « −37 % vs épicerie ».
- `tinted` : fond `Economie` à 12 %, texte `Economie` — « 48 $ économisés ».

### `OfferCard`
Un lot dans un fil.
- Carte `Surface`, coins 24, padding 16.
- Ligne 1 : carré d'icône 52 pt (produit) + nom en `.headline` + « Ferme Lafleur · ferme jeudi » en `.subheadline` secondaire + `SavingsBadge` à droite.
- `TierProgressBar(compact: true)`.
- Pied : « 24 familles · 156 kg sur 200 » secondaire à gauche, `PriceTag` à droite.

### `GroupCard`
Un groupe de quartier.
- Carte `Surface`, coins 24, padding 16.
- Pile de 3 avatars à initiales (32 pt, chevauchement −10 pt, dernier « +21 »).
- Nom en `.headline` + « 24 familles · cueillette rue Ogilvy · 450 m ».
- Bouton « Rejoindre » en `.buttonStyle(.glassProminent)`.

## Règles Liquid Glass

- Le verre seulement sur la couche de contrôle : `TabView`, toolbars, boutons flottants, `tabViewBottomAccessory` (mini-barre de commande). Cartes et listes restent opaques (`Surface`). Pas de verre sur verre.
- Une seule action principale par écran : `.buttonStyle(.glassProminent)` teinté `AccentColor`. Le reste en `.buttonStyle(.glass)`.
- Barre du bas d'une fiche (F3, F4) : `safeAreaInset(edge: .bottom)` avec le bouton principal, pas de fond opaque.
- Quand un palier tombe : `.sensoryFeedback(.success, trigger:)`, `.symbolEffect(.bounce)` sur `checkmark.seal.fill`, prix en `.contentTransition(.numericText())`, `withAnimation(.smooth)`.
- Respecter Reduce Motion et Reduce Transparency.

## Navigation (portail Familles)

`TabView` avec l'API `Tab(...)` :

| Onglet | Symbole | Écran racine |
| --- | --- | --- |
| Accueil | `house.fill` | F1 |
| Groupes | `person.3.fill` | liste et carte des groupes, puis F2 |
| Cueillette | `qrcode` | F5 |
| Impact | `leaf.fill` | F6 |
| Recherche | `Tab(role: .search)` | recherche de lots |

Les fiches de lot (F3, F4) sont poussées dans le `NavigationStack` ; la barre d'onglets se masque (`.toolbarVisibility(.hidden, for: .tabBar)`) pour laisser la place au bouton principal.

## Données de démo

À garder cohérentes avec l'onglet Projet du board et les fixtures fake :

- Famille : Amina, Parc-Extension, groupe « Parc-Ex Ouest » (24 familles), hôte Fatima, cueillette 7420 rue Ogilvy, jeudi 17 h – 18 h 30, à 450 m.
- Lot vedette : riz basmati 200 kg, Ferme Lafleur (Mirabel). Paliers 1–10 familles 3,20 $/kg, 11–25 2,60 $/kg, 26+ 2,10 $/kg. Épicerie 4,10 $/kg. Part d'Amina : 10 kg.
- Autres lots : pommes Cortland (Verger Bilodeau, Saint-Joseph-du-Lac), lentilles corail (Coop Agrinord), huile de canola (Moulin Côté).
- Impact : Amina 48 $ économisés ; quartier 3 900 $ ; 12 paniers suspendus offerts.

## Écrans

Détail par écran (portail Familles, parcours de démo d'Amina) :

- **F1 Accueil** : titre « Bonjour Amina » + avatar ; carte Economie « 48 $ économisés ce mois-ci » ; « Ta commande en cours » = OfferCard du riz (TierProgressBar compacte, « Encore 1 famille pour −19 % ») ; « Nouveaux lots près de toi » en liste groupée. Onglet Accueil.
- **F2 Groupe** : carte (MapKit) en haut avec la zone du groupe et le point de cueillette ; boutons verre retour / partager ; nom, avatars, « 24 familles » ; lieu et horaire de cueillette ; lots ouverts ; bouton principal « Rejoindre le groupe ». Onglet Groupes.
- **F3 Lot** : image produit en haut ; vendeur, nom, date de fermeture ; PriceTag 2,60 $/kg + épicerie barrée + SavingsBadge ; TierProgressBar complète + incitation ; choix de part (Picker segmenté 5 / 10 / 20 kg) ; barre du bas : total 26,00 $ + « Réserver 10 kg ». Pas de barre d'onglets.
- **F4 Palier franchi** : `checkmark.seal.fill` en grand (bounce + haptique succès), « Palier débloqué ! », prix 2,60 → 2,10 $ (numericText), barre pleine, ta part 10 kg · 21,00 $, « 20 $ vs épicerie » ; bouton « Voir ma cueillette ».
- **F5 Cueillette** : aperçu Live Activity « Cueillette dans 25 min » ; QR de la commande « Montre ce code à Fatima » ; articles ; boutons verre « Itinéraire » et « Autre créneau ». Onglet Cueillette.
- **F6 Impact** : tes économies par mois (Swift Charts, novembre en Economie) ; grille du quartier 3 900 $, 12 paniers suspendus, 1,2 t, −41 km ; carte Solidarite « Offrir un panier suspendu ». Onglet Impact.


- **V1 Tableau de bord vendeur** (Ferme Lafleur) : « Espace vendeur » + nom + bouton verre notifications ; 2 tuiles (ventes de la semaine 1 842 $ « +18 % en 7 jours », 61 familles servies) ; bandeau Grenier « Palier 3 atteint à Parc-Ex Ouest » ; lots ouverts (OfferCard côté vendeur, badge « Palier 3 ») ; bouton flottant `.glassProminent` « Créer un lot ». Onglet Tableau.
- **V2 Éditeur de paliers** (« Nouveau lot », poussé) : formulaire groupé produit / quantité / prix épicerie ; liste des paliers (rang, plage de familles, % vs épicerie en Economie, prix éditable) + « Ajouter un palier » ; graphique en escalier prix selon les familles (Swift Charts, `.interpolationMethod(.stepEnd)`) + revenu estimé ; barre du bas « Publier le lot ».
- **V3 Carte de la demande** : carte MapKit des quartiers avec bulles proportionnelles au nombre de familles (Parc-Ex Ouest en Grenier plein) ; recherche produit + filtres en verre ; feuille du bas (`.presentationDetents`) avec le quartier choisi, produits voulus en kg, badge « Forte demande » et « Proposer un lot ici ». Onglet Demande.

Navigation Vendeur : `TabView` Tableau (`house.fill`) / Lots (`shippingbox.fill`) / Demande (`map.fill`) / Revenus (`dollarsign.circle.fill`) + `Tab(role: .search)`.

| Écran | Fichier image | État |
| --- | --- | --- |
| Design system | `00-design-system.png` | prêt |
| F1 Accueil d'Amina | `F1-accueil.png` | prêt |
| F2 Groupe Parc-Ex Ouest | `F2-groupe.png` | prêt |
| F3 Lot de riz et choix de part | `F3-lot.png` | prêt |
| F4 Palier franchi | `F4-palier.png` | prêt |
| F5 Cueillette et QR | `F5-cueillette.png` | prêt |
| F6 Impact sur Montréal | `F6-impact.png` | prêt |
| V1 Tableau de bord vendeur | `V1-tableau.png` | prêt |
| V2 Éditeur de paliers | `V2-paliers.png` | prêt |
| V3 Carte de la demande | `V3-demande.png` | prêt |
