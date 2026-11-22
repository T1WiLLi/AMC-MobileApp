---
name: qa
description: Flow de QA de LeGrenier (AMC-MobileApp) à lancer par n'importe quel agent pour vérifier la qualité de l'app — QA du code (build, tests unitaires complets, règles Firestore, warnings, revue du diff) et QA visuelle sur le simulateur (captures clair/sombre, grand texte, petit écran, parcours de démo), avec un rapport OK/KO. À utiliser avant d'ouvrir ou de merger une PR qui touche l'app, après une série de merges sur main, avant une démo, ou quand un humain demande « fais une QA ».
---

# QA : code et visuel

But : rien n'arrive sur `main`, ni devant le jury, sans avoir été compilé, testé **et regardé**.
La CI ne compile pas l'app (voir `git-workflow`) : la QA locale est la seule barrière. Le soir du 2026-11-21, main a été cassé deux fois par des merges que personne n'avait compilés, et 14 tests sont passés au rouge après un changement de données fake.

Trois niveaux. Choisis le plus petit qui couvre ton changement, mais **le niveau 1 est toujours obligatoire**.

| Niveau | Quand | Durée |
|---|---|---|
| 1. QA code | Avant chaque push, et après chaque rebase | 5-10 min |
| 2. QA visuelle ciblée | Ta PR touche une vue, une navigation, des données fake ou des textes | +10 min |
| 3. QA complète (parcours de démo) | Avant une démo, après une série de merges, ou à la demande d'un humain | 20-30 min |

Lance la QA dans **ton propre worktree** (voir `git-workflow`), à jour : `git fetch origin && git rebase origin/main`.
Pour une QA de `main` : `git worktree add --detach ../AMC-qa-<agent> origin/main`.

## Niveau 1 — QA du code

Utilise un `-derivedDataPath` à toi (`DD=<ton scratchpad>/dd-qa`).

1. **Build de l'app**, sans simulateur :
   ```bash
   xcodebuild -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO \
     OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -warn-long-expression-type-checking=300'
   ```
   - `BUILD SUCCEEDED` exigé.
   - **Zéro nouveau warning** dans les fichiers que tu as touchés. Les warnings déjà sur main ne comptent pas, mais ne les multiplie pas.
   - Toute expression signalée à plus de 300 ms dans tes fichiers est à découper. Sur une machine chargée, Xcode abandonne avec « unable to type-check this expression in reasonable time ».
2. **Tests unitaires complets**, sous le verrou du simulateur (voir `git-workflow`) :
   ```bash
   until mkdir /tmp/amc-sim.lock 2>/dev/null; do sleep 10; done
   xcodebuild test -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
     -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
     -derivedDataPath "$DD" -only-testing:AMC-MobileAppTests CODE_SIGNING_ALLOWED=NO \
     2>&1 | grep -E "recorded an issue|Test run with|TEST (SUCCEEDED|FAILED)"
   rmdir /tmp/amc-sim.lock
   ```
   - **0 échec exigé.**
   - Un test rouge déjà présent sur main n'est pas une excuse. Vérifie-le sur main sans ton commit, signale-le dans le board avec la PR qui l'a cassé, et ne merge pas par-dessus sans le dire.
   - Tu as changé des données fake (`Core/Repositories/Fake/`) ? Lance **toute** la suite : beaucoup de tests lisent ces données.
3. **Règles Firestore**, si `firestore.rules`, `storage.rules` ou un dépôt Firestore a changé :
   ```bash
   npm ci --prefix scripts/rules-tests && npm --prefix scripts/rules-tests run test:emulators
   ```
   Sur l'émulateur seulement, jamais contre la prod. Le déploiement suit le bandeau du board.
4. **Revue de ton diff** (`git diff origin/main...HEAD`), case par case :
   - [ ] Aucun secret : `.env`, `GoogleService-Info.plist`, clés. Aucun `project.pbxproj` ni `.xcstrings` modifié par erreur : réglages locaux de signature, extraction automatique d'Xcode.
   - [ ] MVVM respecté : pas de logique métier dans les vues ; les ViewModels dépendent des protocoles de dépôts.
   - [ ] Swift 6 strict : pas de `@unchecked Sendable` ni de `nonisolated(unsafe)` ajoutés sans raison écrite.
   - [ ] Textes en **français**, ton tutoiement de l'app. Aucun prénom de persona en dur (« Amina », « Camille ») hors `FakeData`. Le nom affiché est **LeGrenier**.
   - [ ] Couleurs et polices sémantiques (voir `ios26-design`) : pas de hex ni de taille de police en dur.
   - [ ] Accessibilité : labels VoiceOver sur les boutons-icônes, cibles ≥ 44 pt, Reduce Motion respecté pour toute animation ajoutée.
   - [ ] Chaque logique ajoutée a un test unitaire. Chaque vue ajoutée a un `#Preview` avec données fake.
   - [ ] Pas de doublon : cherche (`grep -rn`) si un composant ou une fonction équivalente existe déjà. Deux « Créer un groupe » fusionnés ont cassé main.

## Niveau 2 — QA visuelle ciblée

Sur le simulateur partagé, **sous le verrou pendant toute l'interaction**. Ne rends le verrou qu'à la fin. Si tu le rends trop tôt, un autre agent relance l'app sous tes yeux.

1. Installer et lancer en mode démo :
   ```bash
   SIM='iPhone 17'
   APP="$DD/Build/Products/Debug-iphonesimulator/AMC-MobileApp.app"
   xcodebuild -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp -destination "platform=iOS Simulator,name=$SIM" \
     -derivedDataPath "$DD" build CODE_SIGNING_ALLOWED=NO
   xcrun simctl install "$SIM" "$APP"
   xcrun simctl launch --terminate-running-process "$SIM" ca.amc2026.mobileapp \
     -useFakeData -demoFamilyPortal -AppleLanguages "(fr-CA)" -AppleLocale fr_CA
   ```
   Autres arguments de démo : `-demoOnboarding` (onboarding après l'inscription), `-demoVendorOnboarding`, `-demoTour` (visite guidée de Noisette), `-GrenierLiveActivityDemo`.
2. Pour **chaque écran touché**, capture :
   - **clair**, puis **sombre** : `xcrun simctl ui "$SIM" appearance dark` ;
   - **grand texte** : `xcrun simctl ui "$SIM" content_size accessibility-extra-extra-extra-large`, puis remets `large` ;
   - en option, **mode aîné** (Profil → Mode aîné).

   Commande de capture : `xcrun simctl io "$SIM" screenshot qa-<écran>-<variante>.png`. Pour toucher l'écran, utilise l'outil de contrôle du simulateur s'il est disponible.
3. Regarde chaque capture avec la checklist de `ios26-design`. Est KO :
   - un texte tronqué, coupé par un tiret ou qui chevauche autre chose ;
   - un bouton sous la barre d'onglets, ou sous ou derrière le clavier ;
   - une icône vide (carré) ;
   - du texte anglais ;
   - un état vide sec, sans explication ni action ;
   - un chargement de plus de 1 s en mode fake ;
   - une incohérence de données entre écrans : prénom, prix, nombre de parts.
4. Remets le simulateur comme tu l'as trouvé (clair, taille `large`, mode aîné coupé), puis `rmdir /tmp/amc-sim.lock`.

## Niveau 3 — QA complète (parcours de démo du jury)

Rejoue le parcours de `docs/presentation/captures/README.md` (le plus récent sur main fait foi) de bout en bout, chronomètre en main, avec les mêmes captures qu'au niveau 2 à chaque étape :

1. premier lancement : intro, connexion (Google fake et courriel fake), onboarding, Accueil ;
2. réserver une part qui fait franchir un palier : le prix baisse en direct, et l'Accueil est à jour au retour ;
3. panier suspendu en un geste ;
4. Profil → Portail → Vendeurs → carte de la Demande : les bulles sont sur les bons quartiers ;
5. Cueillette : QR côté famille, puis « Récupéré » côté hôte ;
6. Impact ;
7. mode aîné, widget, Live Activity.

Mets à jour `docs/presentation/captures/` (captures + README) dans une PR `docs(qa): …`.

## Rapport (obligatoire, tous niveaux)

Dans la description de ta PR, et en résumé d'une ligne dans le Journal du board :

```
QA niveau <1|2|3> — <branche ou main@sha> — <date heure>
Build : OK (0 nouveau warning) | Tests : 1306/1306 | Règles : OK / non concernées
| Étape / écran | Variante | OK/KO | Remarque | Capture |
KO bloquants : …   (P0 = casse la démo ou main ; P1 = visible par le jury ; P2 = polish)
```

- **Un KO P0 bloque le merge.** Corrige-le, ou retire l'auto-merge (`gh pr merge <n> --disable-auto`) et préviens dans le board.
- Les KO P1/P2 hors de ta tâche : propose-les dans le board (ID `FB-xx` ou `D-xx`, voir `agent-coordination`) au lieu de les coder en douce.
- Ne prétends jamais avoir vérifié ce que tu n'as pas regardé. Écris « compilé seulement » ou « non vérifié au simulateur ».
