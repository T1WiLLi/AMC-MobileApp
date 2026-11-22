# LeGrenier — liste des fonctionnalités (livrable obligatoire)

> **Plus on est, moins ça coûte.**
> Les familles d'un même quartier se regroupent pour acheter en gros, directement aux producteurs et grossistes du Québec. Plus il y a de familles, plus le prix baisse pour tout le monde.

**Équipe :** Zachari Lavallée, William Beaudin, Yann Cedrick Kouekam, Samuel Courchesne · **Sphère principale :** sécurité alimentaire (la faim à Montréal) · **Plateforme :** iOS 26 natif (SwiftUI, Liquid Glass) · **Backend :** Firebase (Auth, Firestore), sans serveur

État au 2026-11-22, vérifié dans le code de `main` (`431a301`, `AMC-MobileApp/Features/`) : 336 PR mergées, environ 1 600 tests unitaires. Chaque ligne se teste dans l'app installée.

**Légende :** ✅ fonctionne dans l'app · 🟡 présente mais partielle · 💳 fonctionne de bout en bout, mais aucun argent réel ne circule (pas de processeur de paiement branché).

---

## Démarrage et compte

| Fonctionnalité | Statut |
|---|---|
| Présentation animée en 3 écrans au premier lancement | ✅ |
| Nouvelle page de connexion et d'inscription : en-tête photo, sélecteur Connexion / Inscription, champs vérifiés en direct, messages d'erreur lus par VoiceOver | ✅ |
| Connexion avec Google, ou par courriel et mot de passe | ✅ |
| Création de compte par courriel avec lien de vérification, et mot de passe oublié | ✅ |
| Choix du portail à l'inscription : Famille ou Vendeur ; un même compte peut avoir les deux et basculer de l'un à l'autre sans se déconnecter | ✅ |
| Compte d'organisme : il va directement à son portail Organismes, sans choix de portail ni onboarding ménage, et n'a pas accès aux portails Famille et Vendeur | ✅ |
| Après l'inscription : goûts, quartier, adresse vérifiée et ménage en quelques écrans | ✅ |
| Visites guidées par une mascotte, rejouables depuis le Profil : Noisette l'écureuil (portail Famille) et Racoonette le raton laveur (portail Vendeur) | ✅ |
| Boutons « i » et états vides qui expliquent chaque écran | ✅ |
| Application entièrement en français et en anglais, changement de langue immédiat dans le Profil | ✅ |
| Modifier son compte, se déconnecter, supprimer son compte | ✅ |
| Verrouiller l'app avec Face ID | ✅ |
| Thèmes de couleurs interchangeables dans le Profil | ✅ |
| Signaler un contenu ou un membre | ✅ |
| Données en cache : l'app s'ouvre hors ligne, avec un indicateur « hors ligne » et un rechargement automatique au retour du réseau | ✅ |
| Adresses vérifiées avec Apple Plans (suggestions pendant la saisie, adresse introuvable refusée) | ✅ |
| Validations alignées sur le serveur : code postal A1A 1A1, taille du foyer, plafonds des lots, des produits et du panier suspendu | ✅ |

## Portail Famille

Onglets : **Accueil · Groupes · Cueillette · Impact · Recherche**.

| Fonctionnalité | Statut |
|---|---|
| Accueil : mon groupe, mes économies, « Tes commandes en cours » en cartes allégées, « Commandes ouvertes du groupe », nouveaux lots près de chez moi ; filtres par type de produit | ✅ |
| Changer de groupe actif quand mon ménage est dans plusieurs groupes | ✅ |
| Réorganiser et masquer les sections de l'Accueil dans une vue en 3D isométrique | ✅ |
| Chercher un lot ou un produit, avec filtres par catégorie | ✅ |
| Fiche d'un lot : producteur, origine, paliers de prix, nombre de familles engagées, temps restant | ✅ |
| Choisir sa part (ex. un sac de 5 kg) et voir tout de suite le prix, l'économie et le prix maximum à payer | ✅ |
| Réserver sa part, la modifier ou l'annuler tant que la commande est ouverte | ✅ |
| Prix par palier en temps réel : la barre montre combien de parts il manque pour le palier suivant | ✅ |
| Célébration « Palier débloqué ! » quand ma part fait baisser le prix de tout le groupe | ✅ |
| Avertissement quand le minimum de lancement d'un lot risque de ne pas être atteint | ✅ |
| Panier suspendu en un geste dans la réservation (+5, +10 ou +20 $) pour offrir la part d'une famille en difficulté | 💳 |
| Paiement : la première réservation enregistre une carte (feuille style Apple Pay), rien n'est débité avant le prix final | 💳 |
| Clôture complète d'une commande par le coordonnateur (« Fermer la commande » sur la fiche du lot) ou le vendeur : prix figé au meilleur palier atteint, subventions du fonds solidaire appliquées aux ménages admissibles, un paiement enregistré par part, reçu pour chaque famille, état « Fermée » partout | 💳 |
| Page publique d'un producteur : description, photos, coups de cœur, zones desservies, ses lots et les étoiles des familles | ✅ |
| Noter un producteur après la cueillette | ✅ |
| Groupes de quartier près de moi, sur une liste et sur une carte centrée sur Montréal ; les pins proches se regroupent selon le zoom | ✅ |
| Carte des familles, des groupes, des producteurs et des points de cueillette du quartier ; le rayon suit le zoom | ✅ |
| Vraies photos partout : groupes, vitrines des vendeurs, familles, logos des organismes (images libres de droits, crédits dans le dépôt) | ✅ |
| Créer un groupe depuis l'app (nom, quartier, centre sur la carte, public ou privé) | ✅ |
| Rejoindre un groupe avec un code, un code QR ou un lien d'invitation qui ouvre l'app ; invitations à usage unique | ✅ |
| Fiche publique d'un groupe, même sans en être membre : familles membres avec leur vrai nom, avis, lots ouverts (consultables, réservation réservée aux membres) | ✅ |
| Noter son groupe avec des étoiles et des commentaires rapides (le créateur ne note pas le sien) | ✅ |
| Groupe à l'image de son quartier : couleur, emblème, bannière et photo choisis par le coordonnateur | ✅ |
| Le créateur peut retirer une famille du groupe | ✅ |
| Passation du groupe : le créateur qui part confie le groupe à un héritier | ✅ |
| Plusieurs comptes dans un même ménage (même adresse, demande et acceptation) ; le propriétaire peut céder son rôle | ✅ |
| « Ce que le groupe veut » : chaque famille dit ce qu'elle veut acheter, la demande s'additionne en direct | ✅ |
| Planificateur du mois : mes besoins et mon budget, et les lots qui y répondent | ✅ |
| Cueillette rangée par groupe : un seul code QR par groupe pour toutes mes commandes, adresse, créneau, itinéraire à pied, liste de ce que je récupère | ✅ |
| Code de cueillette protégé par un jeton privé ; une seule cueillette par ménage, « Récupéré par » le membre qui s'est présenté | ✅ |
| Suivi de la commande : « En route », puis « Arrivée ! Viens la chercher » quand l'hôte la marque comme arrivée | ✅ |
| Réserver un créneau de cueillette | ✅ |
| Devenir hôte : offrir son garage ou son entrée comme point de cueillette, avec adresse vérifiée, photo, créneaux et capacité | ✅ |
| Écran de l'hôte : « Marquer comme arrivée », puis « Remettre les parts » en scannant le QR du groupe (ou en tapant le code sans caméra), listes « À servir » et « Servis », recherche | ✅ |
| Livraison entre voisins : une famille demande la livraison de sa part, un voisin bénévole du groupe la prend en charge (adresse visible seulement par eux deux) | ✅ |
| Ménage soutenu : bandeau discret pour une famille dont la part est financée ; statut subventionné privé | ✅ |
| Profil du ménage : quartier de Montréal, taille du foyer, préférences | ✅ |
| Impact : mes économies et celles du quartier, graphique dans le temps, effets sur 7 sphères de Montréal | ✅ |
| Classement solidaire des arrondissements, calculé sur les vraies commandes | ✅ |
| Historique de mes commandes | ✅ |
| Live Activity sur l'écran verrouillé : état de ma commande jusqu'à la cueillette | ✅ |
| Widget « prochain palier » : combien de parts il manque | ✅ (dans l'IPA, il suit la langue de l'appareil) |
| Notifications : palier débloqué, commande fermée, commande arrivée, rappel de cueillette ; toucher une notification ouvre le bon écran | 🟡 notifications locales (pas de push serveur) |

## Portail Vendeur

Onglets : **Tableau · Lots · Demande · Revenus**. Ouvert à tout producteur, avec un onboarding (boutique, photos, premier produit).

| Fonctionnalité | Statut |
|---|---|
| Tableau de bord : revenus prévus, parts réservées, familles servies, lots ouverts (filtrables par type de produit), lots dont le minimum est en danger ; sections réorganisables | ✅ |
| « Ma vitrine » : description, photos, coups de cœur, zones desservies, comme les familles la voient | ✅ |
| « Mes produits » : créer, modifier et retirer un produit avec photo, réutilisable d'un lot à l'autre | ✅ |
| Publier un lot : produit, part structurée (contenant, poids, valeur), quantité, minimum de lancement, date de fermeture | ✅ |
| Éditeur de paliers de prix avec courbe d'aperçu (10 paliers et 10 000 parts au plus) | ✅ |
| Conditions et prix d'un lot figés une fois publié | ✅ |
| Cycle de vie d'un lot : pause, retrait, duplication | ✅ |
| Fermer sa commande soi-même depuis l'onglet Lots (« Confirmer la commande ») ; état « Fermée, en préparation » sur les cartes | ✅ |
| Carte de la demande : où les familles commandent et ce qu'elles souhaitent, bulles regroupées selon le zoom, « Proposer un lot ici » | ✅ |
| Groupes intéressés et envies qui correspondent à mes produits | ✅ |
| « Mes disponibilités » : déclarer ce que je peux fournir, et créer un lot à partir d'une disponibilité | ✅ |
| Revenus réels, calculés sur les commandes fermées : encaissé, part payée par le fonds solidaire, commission de LeGrenier de 1 %, net, acompte de 50 % pour un vendeur vérifié, reste dû ; revenu prévu des lots ouverts | 💳 |
| Statistiques de ventes par produit | ✅ |

## Portail Organismes

Onglets : **Tableau · Financer · Parrainages · Impact · Recherche**. Pour les banques alimentaires et organismes communautaires, inscrits par l'équipe. Branché sur le vrai Firebase : chaque don et chaque parrainage est écrit dans Firestore et se retrouve dans le fonds du groupe.

| Fonctionnalité | Statut |
|---|---|
| Tableau : fonds disponible, paniers financés, familles aidées | ✅ |
| Dons : financer des paniers suspendus ou donner au fonds de solidarité d'un groupe, avec aperçu en direct (paniers, familles couvertes) et remerciement animé | 💳 |
| Le don alimente le fonds de solidarité du groupe, qui paie les parts des ménages admissibles à la clôture | 💳 |
| Chercher et filtrer les groupes, voir ceux qui en ont le plus besoin | ✅ |
| Parrainer un groupe de quartier, suivre ses parrainages | ✅ |
| Impact de l'organisme : familles aidées, dollars versés, par quartier | ✅ |

## Sous le capot

| Fonctionnalité | Statut |
|---|---|
| SwiftUI pour iOS 26, Swift 6, Liquid Glass natif, mode clair et sombre, architecture MVVM | ✅ |
| Accessibilité : VoiceOver, Dynamic Type jusqu'aux plus grandes tailles, contraste AA, Réduire les animations | ✅ |
| Firebase : Auth (Google, courriel), Firestore en temps réel ; les images sont stockées dans Firestore | ✅ |
| Règles de sécurité Firestore testées en CI, y compris des tests d'attaque ; la commission de 1 % et les versements sont vérifiés par les règles | ✅ |
| Moteur de paliers, répartition des parts, pot de paiement, subventions et commission en Swift pur, couverts par des tests unitaires (environ 1 600 tests) | ✅ |
| Réservations protégées contre les conflits : chaque part se recalcule dans une transaction Firestore | ✅ |
| États de chargement, vides et d'erreur sur chaque écran | ✅ |
| Données de démo réalistes (personas, 16 groupes de Montréal, producteurs du Québec, vraies photos) dans le projet Firebase de démo | ✅ |

## Ce qui n'est pas encore réel

- **Argent** : aucun processeur de paiement n'est branché. Cartes, paiements des parts, paniers suspendus, versements aux vendeurs, dons et parrainages des organismes sont enregistrés dans Firestore et calculés au cent près, mais aucun argent ne circule.
- **Notifications** : locales sur l'appareil, pas de push envoyé par un serveur.
- **Langues** : français et anglais ; arabe, espagnol et créole sont prévus.
- **Bordereau de livraison** du vendeur : calculé dans le code (un envoi par point de cueillette), pas encore d'écran dédié.
- **Commandes récurrentes** (panier de base mensuel) et **recettes anti-gaspillage** : prévues après le hackathon.
