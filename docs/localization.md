# Localisation (fr / en)

- Langue source : **français** (`developmentRegion = fr`). La clé du String Catalog est le texte français.
- Anglais : `AMC-MobileApp/Localizable.xcstrings` (et un catalogue par cible, ex. `GrenierWidgets/`).

## Règle pour tout nouveau texte

- `Text("…")`, `Label`, `Button`, `navigationTitle`, `accessibilityLabel` avec un littéral : déjà localisés (`LocalizedStringKey`).
- Tout texte construit comme `String` (erreurs `AppError`, messages de validation, VoiceOver, notifications, statuts, ternaires `cond ? "a" : "b"`, paramètres `title: String` de nos composants) : **`String(localized: "…")`**.
- Ne pas localiser : identifiants, noms de symboles SF, clés Firestore, données fake ou d'aperçu, noms propres (Grenier, quartiers).
- Après un ajout : `xcodebuild -exportLocalizations -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp -localizationPath <dir> -exportLanguage en -derivedDataPath <dir>/dd -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` met à jour le catalogue (extraction), puis ajouter la traduction anglaise.
- Pluriels : pour une clé avec un seul `%lld`, donner des variations `one` / `other` en anglais (le français garde sa règle : 0 et 1 au singulier).

## Glossaire fr → en (Canadian English)

| Français | English |
|---|---|
| Grenier | Grenier (nom de marque, jamais traduit) |
| panier suspendu | suspended basket |
| palier | tier |
| lot | bundle |
| part | share |
| groupe (de quartier) | (neighbourhood) group |
| ménage | household |
| cueillette / point de cueillette | pickup / pickup point |
| hôte | host |
| créneau | time slot |
| producteur / vendeur | producer / vendor |
| fonds de solidarité | solidarity fund |
| date limite | deadline |
| courriel | email |

## Langue choisie dans l'app (T-171)

- Profil › Préférences › « Langue de l'app » : Langue de l'appareil (défaut, repli français), Français ou English. Clé `grenier.appLanguage`, logique dans `Core/Localization/AppLanguage.swift`.
- Le changement s'applique **sans relancer** : `\.locale` posé à la racine (les `Text("…")` suivent), `String(localized:)` du module passe par une surcharge qui résout dans la langue choisie, et la racine est recréée (`.id`). Le choix est aussi écrit dans `AppleLanguages` pour les éléments système au prochain lancement.
- Formats (montants, dates, nombres) : `AppLanguage.formattingLocale` (`fr_CA` ou `en_CA`), jamais `Locale(identifier: "fr_CA")` en dur pour un texte affiché.
- Les tests tournent en français (`language = "fr"`, `region = "CA"` dans le TestAction du schéma).
- Pluriels : `FrenchPlural.count/word` passe par le catalogue pour les mots courants (clés `%lld famille`, `%lld part`…, variations `one` / `other` en français et en anglais, ajoutées à la main avec `extractionState: manual`). Un mot ajouté = une entrée dans la liste `knownNouns` + une clé `%lld <mot>` au catalogue. Pour une phrase avec un seul nombre, préférer une clé `%lld` avec variations de pluriel.
- Heures : `AppLanguage.clockText` (« 17 h » / « 5 PM »). Parts affichées : `Offer.displayShareUnit` (« bag of 5 kg ») ; `shareUnit` reste le français stable (données, tests).
- Un `cond ? String(localized: "a") : "b"` rend « b » **non localisé** (le ternaire devient un `String`) : envelopper les deux branches.
- Feuilles ouvertes pendant le changement : la racine est recréée, la feuille perd son parent ; `appThemed()` repose `\.locale` à la racine de la feuille.
- Widget / Live Activity : catalogue propre `GrenierWidgets/Localizable.xcstrings` (mêmes clés que les textes de `Shared/`), langue de l'appareil (pas d'App Group pour partager le choix de l'app).
- Avant chaque PR : `xcodebuild -exportLocalizations …` (voir plus haut) puis traduire les clés sans `en` ; `python3`-check : aucune clé sans traduction anglaise.

## Pièges repérés au balayage visuel (fr/en)

- Un composant dont le paramètre est un `String` rendu par `Text(param)` / `Label(param, …)` affiche son texte tel quel : lui passer `String(localized: "…")`, jamais un littéral. Un composant qui fait `Text(LocalizedStringKey(param))` cherche la clé au **runtime** : Xcode ne l'extrait pas, il faut ajouter la clé à la main au catalogue (`extractionState: manual`).
- Unités de vente : `Product.unit` et `Offer.shareUnit` sont le texte stocké (français). Pour l'affichage, `Product.displayUnit` et `Offer.displayShareUnit` (« bag of 5 kg »).
- Saisie de prix : `AppLanguage.decimalSeparator` (virgule en français, point en anglais), jamais « , » en dur.
- `.formatted(...)` (dates relatives, listes, nombres) sans `.locale(AppLanguage.formattingLocale)` suit la langue de l'appareil, pas celle de l'app.
- `InfoPlist.xcstrings` : chaque phrase d'autorisation (caméra, position, Face ID) doit avoir son `en`.
- Pourcentage : en anglais « 19% » (sans espace), en français « 19 % » ; la traduction anglaise de la clé enlève l'espace.
- Tester le changement de langue avec l'interface (Profil › Préférences), pas en réécrivant les préférences du simulateur : `cfprefsd` garde l'ancienne valeur et l'app affiche un mélange.
