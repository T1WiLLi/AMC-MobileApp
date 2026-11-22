# Validation du parcours de démo sur simulateur (Q-034)

- Date : 2026-11-21, `main` à `d5a16ac` (après #209).
- Simulateur : `5CF103EE-EC08-4F1B-8703-8D27530199AB` (en réalité **iPhone 17e**, iOS 26), build Debug, `CODE_SIGNING_ALLOWED=NO`.
- Lancement : `-useFakeData` (+ `-resetOnboarding`, puis `-demoOnboarding`, puis `-GrenierLiveActivityDemo`) et **`-AppleLanguages "(fr-CA)" -AppleLocale fr_CA`**.
- Aucun vrai identifiant : compte courriel de test local (FakeAuthService) et bouton Google du mode fake (aucun appel réseau, renvoie le compte « Camille »).
- Captures réduites à 585 × 1266 px.

## Bloquants ou risques pour la démo (à régler avant le jury)

1. **Inscription par courriel bloquée en mode fake** : après « Créer mon compte », l'écran « Vérifie tes courriels » ne se débloque jamais (« Pas encore vérifié »). Rien n'appelle `FakeAuthService.markEmailVerified()` dans l'app. Seul Google (fake) permet d'entrer. → capture 04.
2. **Mode aîné quasi sans effet** : `.seniorModeTextSize()` n'est appliqué qu'à `PreferencesScreen` et `HouseholdProfileScreen`. L'Accueil, la Cueillette et les autres onglets ne grossissent pas, et « garde seulement l'essentiel » n'existe pas. → captures 23-24.
3. **Pas de bouton « Récupéré » côté hôte ni de scanner** : `GroupOrderRepository.confirmPickup` / `PickupDesk` existent, mais aucune vue ne les appelle. Aucun code caméra (`AVCaptureSession`, `DataScannerViewController`) dans l'app. Le menu de la Cueillette propose seulement « Mon créneau », « Point du groupe » et « Devenir hôte ». → captures 15-16.
4. **Panier suspendu absent du parcours de commande** : `SuspendedBasketPicker` n'est utilisé que dans ses propres `#Preview`. La fiche du lot (Réserver → Part réservée) n'offre aucun don. Le don n'existe que dans le portail Organismes (`DonationSheet`). L'Impact affiche « 0 panier suspendu offert ». → capture 13.
5. **Identité incohérente** : le choix du portail dit « Bienvenue, Camille », l'Accueil dit « Bonjour Amina », le Profil montre « Camille Tremblay ». Un juge le verra. → captures 05, 07, 19.
6. **Le script ne colle pas aux données** : il n'y a ni « Ferme Lafleur » ni « Parc-Extension » côté app. Le riz basmati vient des **Moulins du Nord**, en **sac de 10 kg** (choix 10, 20 ou 30 kg, pas de 5 kg), et Amina est dans **Saint-Michel**. Réserver du riz ne franchit aucun palier (1 part sur 30, il en faut 8 pour lancer la commande). **Le palier qui fonctionne en direct, ce sont les pommes de terre jaunes (Ferme Bio-Rive)** : de 19 à 20 parts, le prix passe de 11,50 $ à 9,90 $. La Live Activity et le widget, eux, montrent « Riz basmati · Parc-Ex Ouest · 2,10 $/kg » : c'est un troisième jeu de chiffres.

## Tableau

| # | Étape | Résultat | Remarque | Capture |
|---|---|---|---|---|
| 1a | Intro (3 écrans) | OK | Belle animation. « Passer » marche. | `01-intro.png` |
| 1b | Connexion : courriel et Google | OK partiel | Le bouton Google est là. **Le simulateur est en en-CA** : sans `-AppleLanguages (fr-CA)`, on voit « Email / Password / Sign in / Create account ». Sur l'iPhone 17e, « Déjà membre ? Se connecter » chevauche le bouton Google, et quand le clavier est ouvert il flotte sur le champ Mot de passe et capte les touches. | `02-connexion.png`, `03-inscription.png` |
| 1c | Inscription par courriel (mode fake) | **KO** | Bloquée sur la vérification (bloquant 1). Contourné avec Google en mode fake. | `04-verification-courriel-bloquee.png` |
| 1d | Choix du portail | OK | « Bienvenue, Camille » (bloquant 5). | `05-choix-portail.png` |
| 1e | Onboarding (goûts, quartier, ménage) | OK avec `-demoOnboarding` | 3 étapes plus un récapitulatif. **Sans `-demoOnboarding`, on va droit à l'Accueil.** Quartier et ménage préremplis (Saint-Michel, Famille Benali). | `06a`…`06d` |
| 1f | Arrivée sur l'Accueil | OK | Squelette de chargement d'environ 2 s. | `07-accueil-amina.png` |
| 2a | Lot « Riz basmati — Ferme Lafleur », 5 kg | **KO (script)** | Pas de Ferme Lafleur ni de 5 kg (point 6). « Réserver » réserve en un tap, sans confirmation. | `08-lot-riz-basmati.png`, `09-riz-part-reservee-sans-palier.png` |
| 2b | Barre de palier et prix en direct | **OK sur les pommes de terre** | 19 → 20 parts, feuille « Palier débloqué ! », 11,50 $ → 9,90 $, barre animée. **Après retour à l'Accueil, la carte affiche encore 11,50 $ et « Encore 1 part »** (pas de rafraîchissement), ainsi que « Tu n'as pas encore de part » après la réservation du riz. Elle se met à jour plus tard (après une bascule de portail). | `10-palier-avant.png`, `11-palier-franchi-anim.png`, `12-palier-debloque.png`, `14-accueil-prix-perime.png` |
| 3 | Panier suspendu de 5 $ en un geste avant de valider | **KO** | Absent du parcours de commande (bloquant 4). | `13-commande-sans-panier-suspendu.png` |
| 4 | Portail Vendeur et demande sur la carte | OK partiel | **Le bouton se trouve dans Profil (avatar en haut à droite) → section « Portail » → « Vendeurs »**. Il faut 2 touches, plus 3 à 5 s de voile animé « LeGrenier · Vendeurs ». Le vendeur ouvert est Les Moulins du Nord (la part de riz d'Amina y apparaît). Onglet Demande : la carte affiche des bulles (Saint-Michel 23, Hochelaga 4). **Les bulles sont mal placées** : « Saint-Michel » tombe près du Mont-Royal et du Quartier des spectacles, « Hochelaga » près du Plateau. Un Montréalais le verra. Il y a aussi environ 3 s de « Chargement de la demande… ». | `19-profil-bascule-portail.png`, `20-bascule-vendeurs-splash.png`, `21-portail-vendeur-tableau.png`, `22-vendeur-carte-demande.png` |
| 5a | Cueillette : QR d'Amina | OK | QR GRN-2135, point « Chez Amina, rue Jarry ». **Environ 5 à 7 s de « Chargement… »** à la première ouverture. « Montre ce code à Amina » s'affiche alors que l'utilisatrice est Amina. Le total à payer (32,90 $) compte le riz, dont la commande n'est pas lancée. L'icône de « Livraison par un voisin » est vide (carré violet). | `15-cueillette-qr.png` |
| 5b | L'hôte marque « Récupéré », scanner caméra | **KO** | Ni bouton ni scanner (bloquant 3). | `16-cueillette-menu-sans-recupere.png` |
| 6 | Impact : économies, kg, trajets évités | OK | 12,08 $ économisés (Amina), 127,79 $ pour le quartier, « 0,2 t de produits » (affiché en tonnes, pas en kg), 21 emballages, 19 trajets de livraison en moins, −41 km et 12 trajets vers l'épicerie évités. « 0 panier suspendu » et « 0 ménage aidé » : rien à montrer pour la solidarité. | `17-impact-haut.png`, `18-impact-spheres.png` |
| 7a | Mode aîné | **KO partiel** | **4 gestes** depuis l'Accueil : Profil → Préférences → défiler → interrupteur « Mode aîné ». Seul l'écran Préférences grossit (bloquant 2). | `23-mode-aine-active.png`, `24-accueil-mode-aine-sans-effet.png` |
| 7b | Widget « Prochain palier » | OK | Présent dans la galerie de widgets (« LeGrenier », 2 tailles) : « Parc-Ex Ouest · Encore 2 familles · 2,60 $ → 2,10 $/kg ». Données statiques, sans lien avec Saint-Michel. | `27-widget-prochain-palier.png` |
| 7c | Live Activity (`-GrenierLiveActivityDemo`) | OK | Elle s'enchaîne seule : « Palier débloqué : 2,10 $/kg », puis « Arrivée : 7420 rue Ogilvy, code GRN-4821 à Fatima ». L'iPhone 17e n'a pas de Dynamic Island : on la voit en bannière dans le Centre de notifications ou sur l'écran verrouillé. | `25-live-activity-palier.png`, `26-live-activity-etape2.png` |
| 8 | Nom « LeGrenier » partout | OK, à 1 détail près | Icône, connexion, intro, voile de bascule, réglages et galerie de widgets disent tous « LeGrenier ». Aucun « AMC » visible dans l'app. Écarts : le message d'invitation de groupe dit « sur **Grenier** » (`GroupInvitationsViewModel.swift:97`), et `INFOPLIST_KEY_CFBundleDisplayName = Grenier` pour la cible widgets dans le pbxproj (la galerie affiche quand même « LeGrenier »). Le bundle id reste `ca.amc2026.mobileapp` (invisible). Sur un autre simulateur (iPhone 18 Pro), une vieille app « AMC-MobileApp » est encore installée : à supprimer de l'iPhone de démo s'il en a une aussi. | `01`, `02`, `20` |

## Chronométrage (2) → (6)

Données fake, latence simulée réaliste, présentateur qui connaît le chemin :

| Segment | Touches | Temps estimé |
|---|---|---|
| Accueil → lot pommes de terre → Réserver → feuille du palier → Voir ma part | 5 (1 défilement, 4 taps) | environ 25 s |
| (3) Panier suspendu | 0 (absent) | — |
| (4) Profil → Vendeurs → Demande (carte) → Profil → Familles | 5 | environ 30 s (2 voiles de 3 à 5 s, plus 3 s de chargement de la carte) |
| (5) Onglet Cueillette → QR → défiler jusqu'au point | 2 | environ 15 s (dont 5 à 7 s de « Chargement… ») |
| (6) Onglet Impact → défiler les sphères | 2 | environ 15 s |
| **Total** | **environ 14 touches** | **environ 1 min 30 à 2 min**, dont 15 à 20 s d'attente de chargement |

Démarrer la démo avec la session déjà ouverte : en mode fake, la session ne survit pas à un relancement (il faut repasser par la connexion à chaque lancement).

## Recommandations pour le script du pitch

- Remplacer « Riz basmati — Ferme Lafleur, 5 kg » par **« Pommes de terre jaunes — Ferme Bio-Rive, 10 kg »** : c'est le seul lot qui franchit un palier en direct. Sinon, aligner les fake data sur le script.
- Lancer avec `-useFakeData -demoFamilyPortal -AppleLanguages "(fr-CA)" -AppleLocale fr_CA`, et passer l'iPhone de démo en français.
- Ne pas montrer l'inscription par courriel (bloquée). Utiliser Google ou une session déjà ouverte.
- Ne pas promettre le scanner ni le panier suspendu en un geste tant qu'ils ne sont pas branchés. Pour le mode aîné, montrer seulement l'écran Préférences.

## Corrigé depuis (PR « Accueil rafraîchi, carte Demande, latence fake réduite »)

- **Accueil après une réservation** : la fiche du lot signale chaque part enregistrée (`ShareActivity`), et l'Accueil recharge tout de suite son flux. Au retour, la carte montre le nouveau prix et ta part, plus « Encore 1 part ».
- **Carte Demande du vendeur** : en vue « Quartiers », chaque bulle est posée sur le centre connu du quartier (`MontrealNeighborhood`). En vue « Groupes », un centre de groupe à plus de 1,5 km de son quartier est ramené au quartier. Saint-Michel, Hochelaga et Parc-Extension tombent au bon endroit.
- **Latence en mode `-useFakeData`** : 5 à 25 ms par appel (`FakeBehavior.demo`) au lieu de 300 à 800 ms. Les 5 à 7 s de la Cueillette, les 3 s de la carte Demande et les 2 s de squelette de l'Accueil deviennent moins de 300 ms par écran. Les previews gardent la latence réaliste.
