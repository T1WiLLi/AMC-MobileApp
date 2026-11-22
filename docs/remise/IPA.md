# IPA de LeGrenier : état et marche à suivre

> L'IPA ne se commite jamais dans le dépôt, ni l'archive, ni `GoogleService-Info.plist`.
> Procédure complète : [`docs/ipa-build.md`](../ipa-build.md). Pipeline : [`scripts/release/build-ipa.sh`](../../scripts/release/build-ipa.sh).

## Version publiée

**Release GitHub [v1.0-334](https://github.com/T1WiLLi/AMC-MobileApp/releases/tag/v1.0-334)** : `LeGrenier-v1.0-334.ipa` et son SHA-256.

| | |
|---|---|
| Version | 1.0 (build 334), commit `6e694ee` plus les correctifs de compilation Release de #332 |
| Bundle | `ca.cegepsorel.legrenier` (widget : `ca.cegepsorel.legrenier.widgets`) |
| Équipe Apple | équipe du Cégep (`6A6TQRFTWB`) |
| Profil | ad hoc, 35 appareils enregistrés, valable jusqu'au 20 avril 2027 |
| iOS | 26 ou plus |

### Limites

- **Seuls les iPhones du profil ad hoc peuvent installer l'IPA.** Un appareil absent du profil refuse l'installation : il faut enregistrer son UDID dans l'équipe, puis refaire l'IPA.
- **Le widget suit la langue de l'appareil**, pas celle choisie dans l'app : la build est signée sans App Group (`--no-app-group`), parce que l'équipe du Cégep n'a pas le groupe `group.ca.cegepsorel.legrenier`. L'app elle-même et la Live Activity ne changent pas.

### ⚠️ v1.0-334 est en retard sur `main` : à refaire avant la remise

Elle a été produite avant ces PR :

| PR | Pourquoi c'est important pour la démo |
|---|---|
| #329 commission ramenée à 1 % | **Bloquant** : les règles Firestore attendent 1 %, alors que la v1.0-334 écrit 6 %. Toute clôture de commande échoue avec cette IPA. |
| #336 compte d'organisme droit à son portail | Sinon `organisme@` passe par le choix du portail et garde la bascule. |
| #338 plus de « Simulation » ni de « démo » dans l'UI | Sinon le bandeau « Simulation » et « Apple Pay (démo) » apparaissent. |
| #333, #335, #337, #340, #341, #342 | Noms des familles, vraies photos, cartes de l'Accueil allégées, filtre des lots ouverts du vendeur, « Confirmer la commande » côté vendeur, bulles regroupées sur la carte de la demande. |

Refaire l'IPA depuis `main` (procédure ci-dessous) **avant de fermer les outils de développement**, puis la réinstaller sur les iPhones de démo. Si d'autres PR importantes sont mergées entre-temps, recommencer.

## Refaire l'IPA

Sur le Mac qui a le compte de l'équipe du Cégep dans Xcode › Settings › Accounts, Xcode 26 ou plus récent.

1. Se placer sur `main` à jour :

   ```bash
   git fetch origin && git switch main && git pull --ff-only
   ```

2. Récupérer le `GoogleService-Info.plist` de l'app Firebase qui correspond au bundle `ca.cegepsorel.legrenier`, **hors du dépôt** :

   ```bash
   npx firebase-tools@15.37.0 apps:sdkconfig IOS 1:959550736484:ios:0967b7aeb8690517ae3771 \
     --project amc-2026-8ab03 > ../firebase-cegep/GoogleService-Info.plist
   ```

3. Lancer le pipeline (archive Release, export ad hoc, vérifications, release GitHub `v1.0-<build>` avec l'IPA et son SHA-256) :

   ```bash
   scripts/release/build-ipa.sh --team 6A6TQRFTWB --bundle-id ca.cegepsorel.legrenier \
     --firebase-plist ../firebase-cegep/GoogleService-Info.plist --no-app-group --release
   ```

   Le numéro de build est le nombre de commits de `main` : la nouvelle release aura un numéro plus grand que 334. Tout ce qui est produit va dans `build/release/` (ignoré par git).

4. Installer la nouvelle IPA sur chaque iPhone de démo (Apple Configurator, ou Finder avec l'iPhone branché), la lancer une fois, et vérifier qu'une commande se ferme bien avec le compte de Jean.

## Historique

- 2026-11-21 : première tentative d'archive sans équipe de développement, échec de signature.
- 2026-11-22 : pipeline `build-ipa.sh` (#325), Xcode 26 ou plus (#330), option `--no-app-group` (#331), build Release qui compile (#332), puis release v1.0-334 avec l'équipe du Cégep.
