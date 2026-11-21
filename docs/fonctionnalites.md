# LeGrenier — liste des fonctionnalités

> **Plus on est, moins ça coûte.**
> Les familles d'un même quartier se regroupent pour acheter en gros, directement aux producteurs et grossistes du Québec. Plus il y a de familles, plus le prix baisse pour tout le monde.

**Équipe :** willi, samuel, zachary, yann · **Sphère principale :** sécurité alimentaire (la faim à Montréal) · **Plateforme :** iOS 26 natif (SwiftUI, Liquid Glass) · **Backend :** Firebase (Auth, Firestore, Storage), sans serveur

État au 2026-11-21, d'après le code de `main` (`AMC-MobileApp/Features/`) et les 160 PR mergées. Chaque ligne se teste dans l'app installée.

**Légende :** ✅ fonctionne dans l'app · 🟡 présente mais partielle · 🧪 simulée (aucun argent réel, aucune livraison réelle).

---

## Démarrage et compte (tous les portails)

| Fonctionnalité | Statut |
|---|---|
| Présentation animée en 3 écrans au premier lancement | ✅ |
| Connexion avec Apple, avec Google, ou par courriel et mot de passe | ✅ |
| Création de compte par courriel avec lien de vérification et mot de passe oublié | ✅ |
| Choix du portail à l'inscription : Famille, Vendeur, Organisme ; un même compte peut en avoir plusieurs | ✅ |
| Bascule animée entre les portails, sans se déconnecter | ✅ |
| Modifier son compte, se déconnecter, supprimer son compte | ✅ |
| Verrouiller l'app avec Face ID | ✅ |
| Thèmes de couleurs interchangeables dans le Profil | ✅ |
| Mode aîné : texte très grand et parcours simplifié | ✅ |
| Signaler un contenu ou un membre | ✅ |
| Données en cache : l'app s'ouvre hors ligne, avec un indicateur « hors ligne » et un rechargement automatique au retour du réseau | ✅ |
| Choix de la langue (renvoie aux réglages iOS) ; l'interface n'est traduite qu'en français pour l'instant | 🟡 |

## Portail Famille

Onglets : **Accueil · Groupes · Cueillette · Impact**.

| Fonctionnalité | Statut |
|---|---|
| Accueil : ma commande en cours, mes économies, les lots ouverts près de chez moi | ✅ |
| Réorganiser et masquer les sections de l'Accueil | ✅ |
| Chercher un lot ou un produit, avec filtres par catégorie | ✅ |
| Fiche d'un lot : producteur, origine, paliers de prix, nombre de familles engagées, temps restant | ✅ |
| Choisir sa part (ex. 5 kg sur un sac de 20 kg) et voir tout de suite le prix et l'économie | ✅ |
| Réserver sa part, la modifier ou l'annuler tant que la commande est ouverte | ✅ |
| Prix par palier en temps réel : la barre montre combien de familles il manque pour le palier suivant | ✅ |
| Célébration « Palier débloqué ! » quand ma part fait baisser le prix de tout le groupe | ✅ |
| Avertissement quand le minimum de lancement d'un lot risque de ne pas être atteint | ✅ |
| Page publique d'un producteur : description, photos, zones desservies, ses lots | ✅ |
| Groupes de quartier près de moi, sur une liste et sur une carte | ✅ |
| Carte des familles et des points de cueillette du quartier | ✅ |
| Rejoindre ou quitter un groupe ; inviter des voisins par code ou code QR | ✅ |
| Groupe à l'image de son quartier : couleur, emblème et bannière propres au groupe | ✅ |
| « Ce que le groupe veut » : chaque famille dit ce qu'elle veut acheter, la demande s'additionne en direct | ✅ |
| Planificateur du mois : mes besoins et mon budget, et les lots qui y répondent | ✅ |
| Cueillette : code QR de ma commande, adresse, itinéraire à pied, liste de ce que je récupère | ✅ |
| Réserver un créneau de cueillette | ✅ |
| Devenir hôte : offrir son garage ou son entrée comme point de cueillette, avec créneaux et capacité | ✅ |
| Livraison à domicile par un voisin bénévole (aînés, personnes sans auto) | ✅ |
| Le scan du code QR par l'hôte au moment de la remise | 🟡 le QR de la commande est affiché ; il n'y a pas encore de scanner côté hôte |
| Paiement de la part : « payé à la cueillette » | 🧪 aucun paiement en ligne réel |
| Panier suspendu : ajouter quelques dollars à sa part pour payer, anonymement, celle d'une famille en difficulté | 🧪 montant simulé |
| Ménage soutenu : bandeau discret pour une famille dont la part est financée ; personne dans le groupe ne voit qui reçoit de l'aide | ✅ |
| Profil du ménage : quartier de Montréal, taille du foyer, préférences ; statut subventionné privé | ✅ |
| Impact : mes économies et celles du quartier, graphique dans le temps, effets sur 7 sphères de Montréal | ✅ |
| Historique de mes commandes | ✅ |
| Live Activity sur l'écran verrouillé : état de ma commande jusqu'à la cueillette | ✅ |
| Widget « prochain palier » : combien de familles il manque | ✅ |
| Notifications : palier débloqué, commande fermée, rappel de cueillette | ✅ notifications locales (pas de push serveur) |

## Portail Vendeur

Onglets : **Tableau · Lots · Demande · Revenus**.

| Fonctionnalité | Statut |
|---|---|
| Tableau de bord : lots en vente, familles engagées, revenu prévu, lots dont le minimum est en danger | ✅ |
| Créer, modifier et retirer un produit avec photo | ✅ |
| Publier un lot : quantité, taille des parts, minimum de lancement, date de fermeture | ✅ |
| Éditeur de paliers de prix (ex. 1–10 familles : 3,20 $/kg ; 11–25 : 2,60 $ ; 26+ : 2,10 $) avec aperçu | ✅ |
| Cycle de vie d'un lot : pause, retrait, duplication | ✅ |
| Carte de la demande : les quartiers de Montréal colorés selon le nombre de familles intéressées | ✅ |
| Groupes intéressés et envies qui correspondent à mes produits | ✅ |
| « Mes disponibilités » : déclarer ce que je peux fournir, et créer un lot à partir d'une disponibilité | ✅ |
| Revenus : revenu encaissé et revenu prévu, par lot | 🧪 calculé sur les paiements simulés |
| Statistiques de ventes par produit | ✅ |
| Profil vendeur public : description, photos, zones desservies | ✅ |

## Portail Organismes

Onglets : **Tableau · Financer · Parrainages · Impact**. Pour les banques alimentaires et organismes communautaires. **Tous les paiements de ce portail sont simulés** : un bandeau « Simulation » est affiché sur chaque écran et aucun argent réel n'est prélevé (plafond de 5 000 $ par financement).

| Fonctionnalité | Statut |
|---|---|
| Tableau : fonds disponible, paniers financés, familles aidées | 🧪 |
| Financer des paniers suspendus ou donner au fonds, avec aperçu en direct (paniers, familles couvertes) et remerciement animé | 🧪 |
| Chercher et filtrer les groupes, voir ceux qui en ont le plus besoin | ✅ |
| Parrainer un groupe de quartier | 🧪 |
| Impact de l'organisme : familles aidées, dollars versés, par quartier | 🧪 calculé sur les dons simulés |

## Sous le capot

| Fonctionnalité | Statut |
|---|---|
| SwiftUI pour iOS 26, Liquid Glass natif, mode clair et sombre | ✅ |
| Accessibilité : VoiceOver, Dynamic Type jusqu'aux plus grandes tailles, contraste AA, Réduire les animations | ✅ |
| Firebase : Auth (Apple, Google, courriel), Firestore en temps réel, Storage pour les images | ✅ |
| Règles de sécurité Firestore et Storage testées en CI | ✅ |
| Moteur de paliers et répartition des parts en Swift pur, couvert par des tests unitaires | ✅ |
| États de chargement, vides et d'erreur sur chaque écran | ✅ |
| Données de démo réalistes (personas, groupes de Montréal, producteurs du Québec) dans le projet Firebase de démo | ✅ |

## Ce qui est simulé ou pas encore fait

- **Paiements** : aucun paiement réel. Les familles « paient à la cueillette » ; les paniers suspendus, les revenus des vendeurs et tous les financements des organismes sont simulés.
- **Livraison** : la demande de livraison par un voisin bénévole fonctionne dans l'app ; aucun transporteur n'est relié.
- **Notifications** : locales sur l'appareil, pas de push envoyé par un serveur.
- **Langues** : français seulement ; anglais, arabe, espagnol et créole sont prévus.
- **Scan du QR** par l'hôte : à venir (le QR est généré et affiché).
- **Bordereau de livraison** du vendeur : calculé dans le code (un envoi par point de cueillette), pas encore d'écran dédié.
- **Commandes récurrentes** (panier de base mensuel) et **recettes anti-gaspillage** : prévues après le hackathon.
