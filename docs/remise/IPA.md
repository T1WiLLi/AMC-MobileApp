# IPA de LeGrenier : état et marche à suivre

> L'IPA ne se commite jamais dans le repo, ni l'archive, ni `GoogleService-Info.plist`.
> Procédure complète et plan B : [`docs/ipa-build.md`](../ipa-build.md).

## Ce qui a été tenté (2026-11-21, agent claude-samuel)

Depuis la racine du repo, sur `main` (5c36975), Xcode 27.2 (27B52) :

```bash
xcodebuild archive \
  -project AMC-MobileApp.xcodeproj \
  -scheme AMC-MobileApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/AMC-MobileApp.xcarchive
```

Résultat : **échec (code 65), à cause de la signature** :

```
error: Signing for "AMC-MobileApp" requires a development team. Select a development team in the Signing & Capabilities editor.
error: Signing for "GrenierWidgetsExtension" requires a development team. Select a development team in the Signing & Capabilities editor.
** ARCHIVE FAILED **
```

L'export (`xcodebuild -exportArchive`) n'a donc pas été lancé. L'agent n'a volontairement modifié
aucun réglage de signature et n'a utilisé aucun identifiant.

## Ce qui manque

| Manque | Constat |
|---|---|
| Équipe de développement | `DEVELOPMENT_TEAM` absent du projet (signature automatique, bundle `ca.amc2026.mobileapp` et `ca.amc2026.mobileapp.widgets`). |
| Certificat de signature | `security find-identity -v -p codesigning` : 0 identité valide sur ce Mac. |
| Profil de provisionnement | Aucun profil installé. |

Les deux cibles à signer : **AMC-MobileApp** (l'app) et **GrenierWidgetsExtension** (le widget).

## À faire par samuel dans Xcode (≈ 10 min)

1. **Xcode › Settings › Accounts** : ajoute ton identifiant Apple (compte développeur payant recommandé ;
   un compte gratuit donne un IPA qui expire après 7 jours et ne s'installe que sur tes appareils).
2. Ouvre `AMC-MobileApp.xcodeproj`, cible **AMC-MobileApp** › **Signing & Capabilities** :
   coche *Automatically manage signing*, choisis ton **Team**.
   Refais la même chose pour la cible **GrenierWidgetsExtension**.
   Si Xcode dit que le bundle ID est déjà pris, change le préfixe (ex. `ca.amc2026.<toi>.mobileapp`)
   sur les deux cibles, en gardant le suffixe `.widgets` pour le widget.
3. Vérifie que `AMC-MobileApp/GoogleService-Info.plist` est bien présent (il est ignoré par Git).
4. Destination en haut : **Any iOS Device (arm64)**.
5. **Product › Archive**. L'Organizer s'ouvre à la fin.
6. **Distribute App › Custom › Debugging** (ou *Release Testing* avec un compte payant) › Next ›
   signature automatique › **Export**. Le dossier exporté contient `AMC-MobileApp.ipa`.
7. Dépose l'IPA à l'endroit demandé par l'AMC (pas dans le repo).

En ligne de commande, une fois le Team choisi dans Xcode :

```bash
xcodebuild archive -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/AMC-MobileApp.xcarchive -allowProvisioningUpdates
```

```bash
cp docs/ExportOptions.example.plist build/ExportOptions.plist
```

Remplace `TEAM_ID_ICI` dans `build/ExportOptions.plist` par ton Team ID, puis :

```bash
xcodebuild -exportArchive -archivePath build/AMC-MobileApp.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/ipa -allowProvisioningUpdates
```

`build/` est hors du suivi Git : ne l'ajoute pas au commit.
