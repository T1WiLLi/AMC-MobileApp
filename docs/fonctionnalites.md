# LeGrenier — liste des fonctionnalités

> **Plus on est, moins ça coûte.**
> Les familles d'un même quartier se regroupent pour acheter en gros, directement aux producteurs et grossistes du Québec. Plus il y a de familles, plus le prix baisse pour tout le monde.

**Équipe :** Zachari Lavallée, William Beaudin, Yann Cedrick Kouekam, Samuel Courchesne · **Sphère principale :** sécurité alimentaire (la faim à Montréal) · **Plateforme :** iOS 26 natif (SwiftUI, Liquid Glass) · **Backend :** Firebase (Auth, Firestore), sans serveur

État au 2026-11-22, d'après le code de `main` (`ec7079b`, `AMC-MobileApp/Features/`) et environ 325 PR mergées. Chaque ligne se teste dans l'app installée.

**Légende :** ✅ fonctionne dans l'app · 🟡 présente mais partielle · 🧪 simulée (aucun argent réel, aucune livraison réelle).

---

## Démarrage et compte (tous les portails)

| Fonctionnalité | Statut |
|---|---|
| Présentation animée en 3 écrans au premier lancement | ✅ |
| Connexion avec Google, ou par courriel et mot de passe | ✅ |
| Création de compte par courriel avec lien de vérification et mot de passe oublié | ✅ |
| Choix du portail à l'inscription : Famille ou Vendeur ; un même compte peut avoir les deux. Le portail Organismes est réservé aux organismes inscrits par l'équipe | ✅ |
| Après l'inscription : goûts, quartier, adresse vérifiée et ménage en quelques écrans | ✅ |
| Bascule animée entre les portails, sans se déconnecter | ✅ |
| Visites guidées par une mascotte, rejouables depuis le Profil : Noisette l'écureuil (12 étapes, portail Famille) et Racoonette le raton laveur (portail Vendeur) | ✅ |
| Boutons « i » et états vides qui expliquent chaque écran | ✅ |
| Application entièrement en français et en anglais, changement de langue immédiat dans le Profil ; le widget et la Live Activity suivent la langue de l'app sur iPhone | ✅ |
| Modifier son compte, se déconnecter, supprimer son compte | ✅ |
| Verrouiller l'app avec Face ID | ✅ |
| Thèmes de couleurs interchangeables dans le Profil | ✅ |
| Signaler un contenu ou un membre | ✅ |
| Données en cache : l'app s'ouvre hors ligne, avec un indicateur « hors ligne » et un rechargement automatique au retour du réseau | ✅ |
| Adresses vérifiées avec Apple Plans (suggestions pendant la saisie, adresse introuvable refusée) | ✅ |

## Portail Famille

Onglets : **Accueil · Groupes · Cueillette · Impact · Recherche**.

| Fonctionnalité | Statut |
|---|---|
| Accueil : mon groupe, mes économies, ma commande en cours, les nouveaux lots près de chez moi (filtrables par type de produit) | ✅ |
| Changer de groupe actif quand mon ménage est dans plusieurs groupes | ✅ |
| Réorganiser et masquer les sections de l'Accueil dans une vue en 3D isométrique | ✅ |
| Chercher un lot ou un produit, avec filtres par catégorie | ✅ |
| Fiche d'un lot : producteur, origine, paliers de prix, nombre de familles engagées, temps restant | ✅ |
| Choisir sa part (ex. un sac de 5 kg) et voir tout de suite le prix, l'économie et le prix maximum à payer | ✅ |
| Réserver sa part, la modifier ou l'annuler tant que la commande est ouverte | ✅ |
| Prix par palier en temps réel : la barre montre combien de parts il manque pour le palier suivant | ✅ |
| Célébration « Palier débloqué ! » quand ma part fait baisser le prix de tout le groupe | ✅ |
| Avertissement quand le minimum de lancement d'un lot risque de ne pas être atteint (« Il manque 7 parts pour commander · plus que 1 jour ») | ✅ |
| Panier suspendu en un geste dans la réservation (+5, +10 ou +20 $) pour offrir la part d'une famille en difficulté | 🧪 montant simulé |
| Paiement : la première réservation enregistre une carte (« Apple Pay (démo) »), rien n'est débité avant le prix final ; à la clôture, les parts sont payées au pot du groupe, avec reçu | 🧪 aucun argent réel |
| Subventions appliquées à la clôture : le fonds solidaire du groupe paie tout ou partie de la part d'un ménage admissible | 🧪 fonds simulé |
| Page publique d'un producteur : description, photos, coups de cœur, zones desservies, ses lots et les étoiles des familles | ✅ |
| Noter un producteur après la cueillette | ✅ |
| Groupes de quartier près de moi, sur une liste et sur une carte centrée sur Montréal ; les pins proches se regroupent selon le zoom | ✅ |
| Carte des familles, des groupes, des producteurs et des points de cueillette du quartier ; le rayon suit le zoom | ✅ |
| Créer un groupe depuis l'app (nom, quartier, centre sur la carte, public ou privé) | ✅ |
| Rejoindre un groupe avec un code, un code QR ou un lien d'invitation qui ouvre l'app ; invitations à usage unique | ✅ |
| Fiche publique d'un groupe, même sans en être membre : membres, avis des familles, lots ouverts (consultables, réservation réservée aux membres) | ✅ |
| Noter son groupe avec des étoiles et des commentaires rapides (le créateur ne note pas le sien) | ✅ |
| Groupe à l'image de son quartier : couleur, emblème, bannière et photo choisis par le coordonnateur | ✅ |
| Le créateur peut retirer un membre, quitter son groupe et le confier à un héritier | ✅ |
| Plusieurs comptes dans un même ménage (même adresse, demande et acceptation) ; le propriétaire peut céder son rôle | ✅ |
| « Ce que le groupe veut » : chaque famille dit ce qu'elle veut acheter, la demande s'additionne en direct | ✅ |
| Planificateur du mois : mes besoins et mon budget, et les lots qui y répondent | ✅ |
| Cueillette rangée par groupe : un seul code QR par groupe pour toutes mes commandes, adresse, créneau, itinéraire à pied, liste de ce que je récupère | ✅ |
| Code de cueillette protégé par un jeton privé ; une seule cueillette par ménage, « Récupéré par » le membre qui s'est présenté | ✅ |
| Suivi de la commande : « En route », puis « Arrivée ! Viens la chercher » quand l'hôte la marque comme arrivée | ✅ |
| Réserver un créneau de cueillette | ✅ |
| Devenir hôte : offrir son garage ou son entrée comme point de cueillette, avec adresse vérifiée, photo, créneaux et capacité | ✅ |
| Écran de l'hôte : « Marquer comme arrivée », puis « Remettre les parts » en scannant le QR (ou en tapant le code sans caméra), listes « À servir » et « Servis », recherche | ✅ |
| Livraison à domicile par un voisin bénévole (aînés, personnes sans auto) | ✅ |
| Ménage soutenu : bandeau discret pour une famille dont la part est financée | ✅ |
| Profil du ménage : quartier de Montréal, taille du foyer, préférences ; statut subventionné privé | ✅ |
| Impact : mes économies et celles du quartier, graphique dans le temps, effets sur 7 sphères de Montréal, classement solidaire des arrondissements calculé sur les vraies commandes | ✅ |
| Historique de mes commandes | ✅ |
| Live Activity sur l'écran verrouillé : état de ma commande jusqu'à la cueillette | ✅ |
| Widget « prochain palier » : combien de parts il manque | ✅ |
| Notifications : palier débloqué, commande fermée, commande arrivée, rappel de cueillette ; toucher une notification ouvre le bon écran | ✅ notifications locales (pas de push serveur) |

## Portail Vendeur

Onglets : **Tableau · Lots · Demande · Revenus**. Ouvert à tout producteur, avec un onboarding (boutique, photos, premier produit).

| Fonctionnalité | Statut |
|---|---|
| Tableau de bord : revenus prévus, parts réservées, familles servies, lots ouverts, lots dont le minimum est en danger ; sections réorganisables | ✅ |
| « Ma vitrine » : description, photos, coups de cœur, zones desservies, comme les familles la voient | ✅ |
| « Mes produits » : créer, modifier et retirer un produit avec photo, réutilisable d'un lot à l'autre | ✅ |
| Publier un lot : produit, part structurée (contenant, poids, valeur), quantité, minimum de lancement, date de fermeture | ✅ |
| Éditeur de paliers de prix (ex. 6 parts : 17,59 $ ; 12 : 15,59 $ ; 20 : 13,59 $) avec courbe d'aperçu | ✅ |
| Conditions d'un lot figées une fois publié | ✅ |
| Cycle de vie d'un lot : pause, retrait, duplication | ✅ |
| Fermer la commande soi-même depuis l'onglet Lots ; état « Fermée, en préparation » sur les cartes | ✅ |
| Carte de la demande : où les familles commandent et ce qu'elles souhaitent, « Proposer un lot ici » | ✅ |
| Groupes intéressés et envies qui correspondent à mes produits | ✅ |
| « Mes disponibilités » : déclarer ce que je peux fournir, et créer un lot à partir d'une disponibilité | ✅ |
| Revenus : revenu encaissé et revenu prévu, par lot | 🧪 calculé sur les paiements simulés |
| Commandes fermées : encaissé, part payée par le fonds solidaire, commission de 6 %, net, acompte de 50 % versé à un vendeur vérifié, reste dû | 🧪 paiements simulés |
| Statistiques de ventes par produit | ✅ |

## Portail Organismes

Onglets : **Tableau · Financer · Parrainages · Impact**. Pour les banques alimentaires et organismes communautaires, inscrits par l'équipe. Branché sur le vrai Firebase. **Tous les paiements de ce portail sont simulés** : un bandeau « Simulation » est affiché sur chaque écran et aucun argent réel n'est prélevé.

| Fonctionnalité | Statut |
|---|---|
| Tableau : fonds disponible, paniers financés, familles aidées | 🧪 |
| Financer des paniers suspendus ou donner au fonds d'un groupe, avec aperçu en direct (paniers, familles couvertes) et remerciement animé | 🧪 |
| Chercher et filtrer les groupes, voir ceux qui en ont le plus besoin | ✅ |
| Parrainer un groupe de quartier | 🧪 |
| Impact de l'organisme : familles aidées, dollars versés, par quartier | 🧪 calculé sur les dons simulés |

## Sous le capot

| Fonctionnalité | Statut |
|---|---|
| SwiftUI pour iOS 26, Liquid Glass natif, mode clair et sombre | ✅ |
| Accessibilité : VoiceOver, Dynamic Type jusqu'aux plus grandes tailles, contraste AA, Réduire les animations | ✅ |
| Firebase : Auth (Google, courriel), Firestore en temps réel ; les images sont stockées dans Firestore (pas de Cloud Storage) | ✅ |
| Règles de sécurité Firestore testées en CI, y compris des tests d'attaque | ✅ |
| Moteur de paliers, répartition des parts, pot de paiement et commission en Swift pur, couverts par des tests unitaires (plus de 1 500 tests) | ✅ |
| Réservations protégées contre les conflits : chaque part se recalcule dans une transaction Firestore | ✅ |
| États de chargement, vides et d'erreur sur chaque écran | ✅ |
| Données de démo réalistes (personas, groupes de Montréal, producteurs du Québec), en mode hors ligne et dans le projet Firebase de démo | ✅ |

## Ce qui est simulé ou pas encore fait

- **Paiements** : aucun argent réel. La carte « Apple Pay (démo) », le pot du groupe, les paniers suspendus, les revenus des vendeurs et tous les financements des organismes sont simulés.
- **Livraison** : la demande de livraison par un voisin bénévole fonctionne dans l'app ; aucun transporteur n'est relié.
- **Notifications** : locales sur l'appareil, pas de push envoyé par un serveur.
- **Langues** : français et anglais ; arabe, espagnol et créole sont prévus.
- **Bordereau de livraison** du vendeur : calculé dans le code (un envoi par point de cueillette), pas encore d'écran dédié.
- **Commandes récurrentes** (panier de base mensuel) et **recettes anti-gaspillage** : prévues après le hackathon.
