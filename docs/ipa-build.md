# Build de l'IPA — procédure compétition (B-006)

> **Règle dure** : dimanche 2026-11-22 à **11:00**, aucun logiciel de développement ouvert (Xcode, Simulator, Terminal, éditeurs, agents…) → **disqualification automatique**. L'IPA final doit être buildé **et installé sur nos iPhones de test avant**.
> Faire une **répétition complète samedi soir** (build + export + install sur 2 appareils). Dimanche matin ne doit rien avoir de nouveau.

Repères : scheme `AMC-MobileApp`, bundle ID attendu **`ca.amc2026.mobileapp`** (celui de `GoogleService-Info.plist`), cible **iOS 26.0**.

---


## 0. Pipeline automatique (recommandé)

```bash
scripts/release/build-ipa.sh --team <TEAM_ID>              # archive + export ad hoc + vérifications
scripts/release/build-ipa.sh --team <TEAM_ID> --release    # + release GitHub vX.Y-<build> avec l'IPA et son SHA-256
```

- Méthode par défaut : `release-testing` (ad hoc, équipe payante). `--method debugging` pour une signature développement.
- Numéro de build = nombre de commits (toujours croissant) ; version = `MARKETING_VERSION` (ou `--version`).
- Vérifie : bundle `ca.amc2026.mobileapp`, version et build, `GoogleService-Info.plist` embarqué, signature, profil (nombre d'appareils, expiration).
- Tout sort dans `build/release/<tag>/` (ignoré par git), journaux compris.
- **Équipe** : il faut l'équipe Apple qui possède déjà les identifiants `ca.amc2026.mobileapp`, `ca.amc2026.mobileapp.widgets` et le groupe `group.ca.amc2026.mobileapp` (App Group du widget, #305). Avec une autre équipe, Xcode refuse : « cannot be registered to your development team because it is not available ».

## 1. Prérequis (à vérifier samedi, pas dimanche)

| Quoi | Détail |
|---|---|
| Mac + Xcode | **Xcode 26.x** (SDK iOS 26). `xcodebuild -version` doit afficher 26.x. |
| iPhones | **iOS 26 ou plus** (la cible est 26.0 : un appareil en iOS 18 ne pourra pas installer l'app). Valable aussi pour les appareils prêtés. |
| Compte Apple | Xcode › Settings › Accounts : le compte Apple de la personne qui build est connecté et voit l'équipe. |
| Bundle ID | Dans la cible : `PRODUCT_BUNDLE_IDENTIFIER = ca.amc2026.mobileapp`. ⚠️ Sur `main` le pbxproj contient encore `com.example.AMC-MobileApp` : à corriger (modif du pbxproj, à annoncer sur le board) sinon Firebase/Google Sign-In ne correspondent pas. |
| Signing | Cible › Signing & Capabilities : **Automatically manage signing** coché, **Team** choisie (aucune `DEVELOPMENT_TEAM` n'est fixée dans le projet). |
| Firebase | `AMC-MobileApp/GoogleService-Info.plist` présent sur le Mac qui build (dossier synchronisé → inclus automatiquement). |
| Google Sign-In | URL Type avec le `REVERSED_CLIENT_ID` du plist dans la cible (Info › URL Types). Sans ça : retour vers l'app impossible après la connexion Google. |
| Mode développeur | Sur chaque iPhone : Réglages › Confidentialité et sécurité › **Mode développeur** → activer, redémarrer. Nécessaire pour les apps signées en développement. |

### Compte gratuit vs payant

| | Apple ID gratuit (« Personal Team ») | Apple Developer Program (99 USD/an) |
|---|---|---|
| Installer sur un iPhone branché via Xcode (Run) | Oui | Oui |
| Durée de validité | **7 jours**, puis l'app ne se lance plus → réinstaller | Profil ~1 an |
| Exporter un IPA (Distribute App) | **Probablement non** (non vérifié ; ne pas compter dessus) | Oui : Debugging (développement) ou Release Testing (ad hoc) |
| Appareils | Seulement ceux branchés au Mac ; ~3 apps « sideloadées » actives par appareil | Jusqu'à 100 iPhones enregistrés par an (par UDID) |
| Appareils prêtés | Les brancher au Mac et faire Run | Enregistrer leur UDID, **re-archiver**, installer l'IPA |
| Premier lancement | Réglages › Général › VPN et gestion de l'appareil › faire confiance au développeur (**avec internet**) | Rien de particulier |

- Un bundle ID appartient à **une seule équipe** : désigner **une seule personne / une seule équipe** qui build. Deux Personal Teams différentes ne peuvent pas signer toutes les deux `ca.amc2026.mobileapp`.
- Le livrable est un **IPA** : un compte payant (le nôtre ou celui d'un membre) est fortement recommandé. En gratuit, le plan B (§ 5) fabrique un IPA à la main, mais il ne s'installera que sur les appareils du profil.
- Les 7 jours ne posent pas de problème si l'app est installée samedi ou dimanche matin.

---

## 2. Build + archive

### En ligne de commande (depuis la racine du repo)

```bash
cp docs/ExportOptions.example.plist build-export.plist   # puis remplacer TEAM_ID_ICI (non commité)

# 0. Packages SPM (Firebase, GoogleSignIn)
xcodebuild -resolvePackageDependencies -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp

# 1. Archive (Release, appareil générique)
xcodebuild archive \
  -project AMC-MobileApp.xcodeproj -scheme AMC-MobileApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/AMC-MobileApp.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=TEAM_ID_ICI

# 2. Export de l'IPA
xcodebuild -exportArchive \
  -archivePath build/AMC-MobileApp.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist build-export.plist \
  -allowProvisioningUpdates

ls build/ipa   # → AMC-MobileApp.ipa
```

- Team ID : developer.apple.com › Account › Membership (10 caractères), ou Xcode › Settings › Accounts.
- `-allowProvisioningUpdates` laisse Xcode créer certificats/profils et y ajouter les appareils enregistrés ; il faut que le compte soit connecté dans Xcode.
- `build/` et `build-export.plist` ne doivent pas être commités.

### Dans Xcode (équivalent)

1. Sélecteur de destination en haut : **Any iOS Device (arm64)**.
2. **Product › Archive** → l'Organizer s'ouvre.
3. **Distribute App** → **Custom** → **Debugging** (ou **Release Testing** pour de l'ad hoc) → Automatically manage signing → **Export** → choisir un dossier. On obtient `AMC-MobileApp.ipa`.

(Xcode 15.3+ a renommé les méthodes : `development` → `debugging`, `ad-hoc` → `release-testing`. Les anciens noms marchent encore avec un avertissement.)

---

## 3. `ExportOptions.example.plist`

Fichier fourni : [`docs/ExportOptions.example.plist`](ExportOptions.example.plist). Méthode **`debugging`** (signature développement, installable sur les appareils enregistrés de l'équipe, fonctionne pour tout membre de l'équipe). Remplacer `TEAM_ID_ICI`. Pour de l'ad hoc (compte payant, rôle Admin/Account Holder), passer `method` à `release-testing`.

---

## 4. Installer l'IPA sur les iPhones

iPhone branché en USB (ou même réseau), déverrouillé, « Faire confiance à cet ordinateur ».

- **Xcode** : Window › Devices and Simulators › choisir l'iPhone › **+** sous *Installed Apps* › sélectionner l'IPA.
- **Ligne de commande** :
  ```bash
  xcrun devicectl list devices                         # nom + identifiant
  xcrun devicectl device install app --device <ID> build/ipa/AMC-MobileApp.ipa
  ```
  Si l'IPA est refusé (non vérifié avec `.ipa`) : `unzip` l'IPA et passer `Payload/AMC-MobileApp.app`.
- **Apple Configurator** (Mac App Store) : glisser l'IPA sur l'appareil, ou Ajouter › Apps.
- **Finder** : glisser l'IPA sur l'iPhone dans la barre latérale fonctionne en général aussi.

Erreur « profil ne contient pas cet appareil » → l'UDID n'est pas enregistré (voir ci-dessous).

### Appareils prêtés par les organisateurs

**Demander tôt** (samedi) : il faut l'appareil en main pour l'enregistrer.

1. Vérifier qu'il est en **iOS 26+** et activer le Mode développeur.
2. Le brancher au Mac. UDID : `xcrun devicectl list devices`, ou Finder (cliquer sous le nom de l'appareil jusqu'à voir l'UDID).
3. Enregistrer : le plus simple, dans Xcode le sélectionner comme destination et faire **Run** une fois (signing automatique = enregistrement automatique). Sinon developer.apple.com › Certificates, IDs & Profiles › Devices › +.
4. **Re-archiver et ré-exporter** (le profil doit inclure le nouvel UDID), puis installer l'IPA.
5. En compte gratuit : seulement Run depuis Xcode sur l'appareil branché.

Alternative sans UDID : **TestFlight** (compte payant, fiche App Store Connect, upload + traitement de quelques minutes à plusieurs heures, testeurs internes à inviter). Trop risqué à improviser dimanche ; seulement si déjà rodé samedi.

---

## 5. Compte à rebours dimanche 22 novembre

| Heure | Action | Fait |
|---|---|---|
| Samedi soir | Répétition complète : archive → IPA → installé sur 2 iPhones. Garder cet IPA comme **IPA de secours**. Appareils prêtés enregistrés. | ☐ |
| 09:30 | **Code freeze**. Plus aucun merge sur `main` sauf correctif bloquant validé par le PO. | ☐ |
| 09:45 | `git pull` sur le Mac de build, vérifier bundle ID, team, `GoogleService-Info.plist`, numéro de build incrémenté. | ☐ |
| 10:00 | **Build final** : archive + export (§ 2). Copier l'IPA sur une clé USB / un drive partagé. | ☐ |
| 10:15 | Installer sur **2 iPhones minimum** (+ appareils prêtés). | ☐ |
| 10:30 | **Smoke test** (§ 6) sur les 2 appareils, en Wi-Fi puis en mode avion. | ☐ |
| 10:40 | Remise de l'IPA selon les consignes des organisateurs. Lancer l'app une fois **avec internet** sur chaque appareil (validation du profil). | ☐ |
| 10:50 | **Tout fermer** : Xcode (⌘Q), Simulator, Apple Configurator, Terminal, éditeurs, Claude/Codex, Android Studio… Vérifier le Dock. En cas de doute, demander aux organisateurs ce qui compte. | ☐ |
| 11:00 | Plus rien d'ouvert. Les iPhones sont prêts. | ☐ |

### Plan B si la signature / l'export échoue (décider avant 10:20)

1. **Relancer une fois** avec `-allowProvisioningUpdates`, vérifier Xcode › Settings › Accounts (session expirée ?) et la Team dans Signing & Capabilities.
2. **IPA manuel depuis l'archive** (l'app de l'archive est déjà signée en développement) :
   ```bash
   cd build && rm -rf Payload && mkdir Payload
   cp -R AMC-MobileApp.xcarchive/Products/Applications/AMC-MobileApp.app Payload/
   zip -qry AMC-MobileApp.ipa Payload
   ```
   Installable seulement sur les appareils inclus dans le profil utilisé à l'archive.
3. **Run direct** depuis Xcode sur chaque iPhone branché (scheme en Release : Product › Scheme › Edit Scheme › Run › Build Configuration = Release). L'app reste installée après fermeture d'Xcode.
4. **IPA de secours** de samedi soir : le remettre et l'installer s'il le faut.
5. À 10:45 au plus tard, on arrête de corriger : on livre ce qui est installé.

---

## 6. Smoke test (essai jury de 5 minutes)

Sur chaque appareil, app supprimée puis réinstallée (état « premier lancement ») :

- [ ] L'app se lance en < 3 s, pas d'écran blanc, icône et nom corrects.
- [ ] **Connexion Google** sur l'appareil réel : la feuille Google s'ouvre, on revient dans l'app connecté (teste l'URL scheme `REVERSED_CLIENT_ID` + le bundle ID côté Firebase).
- [ ] Déconnexion puis reconnexion OK.
- [ ] **Parcours principal de la démo** fait 2 fois de bout en bout, sans crash ni écran vide.
- [ ] Chaque onglet s'ouvre ; retour arrière OK ; rotation / mode sombre sans casse visible.
- [ ] Quitter l'app (balayage) et relancer : la session et les données sont toujours là.
- [ ] **Mode avion** : l'app se lance, affiche les données en cache ou un message clair, aucun crash, aucun spinner infini. Réactiver le réseau : tout revient.
- [ ] Autorisations demandées (localisation, notifications…) : textes en français, refus géré sans crash.
- [ ] Batterie chargée, luminosité haute, notifications coupées (Ne pas déranger), compte Google de démo déjà connu.
