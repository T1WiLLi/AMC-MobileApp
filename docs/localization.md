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
- Reste à faire : `FrenchPlural` et quelques littéraux non localisés (ex. `OrganizationPortalModel`) restent en français en anglais.
