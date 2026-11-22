# Plan de présentation — LeGrenier, AMC 2026

> Format kiosque : **5 min pitch → 5 min essai par les juges → 2 min questions.**
> Deck : [`docs/remise/LeGrenier.pptx`](../remise/LeGrenier.pptx) (12 diapos, notes d'orateur). Liste des fonctionnalités : [`liste-fonctionnalites.md`](liste-fonctionnalites.md).
> Règle d'or : **vendre le produit.** Problème (la faim à Montréal) et mission (« Plus on est, moins ça coûte ») clairs avant la fin de la 1re minute.

## Comptes de démo

| Rôle | Compte | Ce qu'on montre |
|---|---|---|
| Famille | `amina@demo.grenier.local` | Amina, Parc-Extension, membre de Voisins de Parc-Ex |
| Coordonnateur et hôte | `jean@demo.grenier.local` | Jean, coordonnateur de Voisins de Parc-Ex et hôte du point de cueillette |
| Vendeur | `ferme-lafleur@demo.grenier.local` | Ferme Lafleur |
| Organisme | `organisme@demo.grenier.local` | Portail Organismes (le compte y va directement) |

**Mot de passe :** le même pour les quatre comptes, dans l'onglet « Comptes de démo » du board. Il ne s'écrit jamais dans ce dépôt (dépôt public).

Idéalement, un iPhone par rôle, sessions ouvertes avant l'arrivée des juges. Avec un seul iPhone : Profil › Se déconnecter, puis connexion par courriel (environ 20 s par changement de compte).

## Script de démo, 5 minutes

| Temps | Compte | Ce qu'on fait | Ce qu'on dit |
|---|---|---|---|
| **0:00–1:00** | Amina | Nouvelle page de connexion (déjà connectée, on la montre au besoin). Accueil : son groupe, ses économies, « Tes commandes en cours ». On ouvre un lot ouvert du groupe, on choisit sa part, on réserve : la barre des paliers bouge, « Palier débloqué ! » si on franchit un palier. | « Amina choisit sa part, et sa réservation fait baisser le prix de tout le groupe, en direct. Rien n'est débité avant le prix final. » |
| **1:00–2:00** | Amina | Groupes › Voisins de Parc-Ex : familles membres, carte du quartier. Cueillette : un seul QR pour toutes ses commandes du groupe. Impact : économies, 7 sphères, classement solidaire des arrondissements. | « Tout est sur le vrai Firebase : les familles, les commandes et le classement viennent des vraies données. » |
| **2:00–3:00** | Jean | Sur une commande dont le minimum est atteint : « Fermer la commande ». Prix figé au meilleur palier, subventions du fonds appliquées, paiements enregistrés, reçus. Puis Cueillette › « Marquer comme arrivée », et « Remettre les parts » : on scanne le QR d'Amina. | « Le coordonnateur ferme, le fonds solidaire paie la part des familles admissibles, et l'hôte remet les parts avec un seul scan. » |
| **3:00–4:00** | Ferme Lafleur | Tableau : lots ouverts filtrés par type de produit. Lots : « Confirmer la commande » pour fermer soi-même. Revenus : encaissé, part du fonds, commission de 1 %, net, acompte de 50 %. Demande : la carte des familles intéressées. | « Le producteur voit la demande avant de livrer, livre un seul point par quartier, et LeGrenier ne prend que 1 %. » |
| **4:00–5:00** | Organisme | Connexion : le compte va droit au portail Organismes, sans choix de portail. Financer : un don au fonds d'un groupe, aperçu en direct, remerciement. Parrainages, puis Impact. On tend le téléphone : « À vous ! » | « Les banques alimentaires financent directement le fonds d'un quartier, et ce fonds paie les parts à la clôture. » |

Points d'attention :
- **La clôture est définitive** : préparer avant l'essai une commande de Jean au minimum atteint, et en garder une 2e en réserve. Ne pas fermer celle qu'Amina vient de réserver si elle doit rester ouverte pour le juge suivant.
- « Marquer comme arrivée » n'apparaît qu'une fois la commande fermée.
- Aucun argent réel ne circule : si un juge demande, le dire franchement (paiements enregistrés et calculés au cent près, processeur de paiement à brancher après le hackathon).

### Plan B : la connexion Google échoue

1. Ne pas insister : revenir à l'écran de connexion, onglet **Connexion**.
2. Se connecter **par courriel** avec le compte du rôle (`amina@demo.grenier.local`, etc.) et le mot de passe du board.
3. Si le réseau est en cause : l'app s'ouvre hors ligne avec les données en cache et l'indicateur « hors ligne » ; montrer la navigation, et refaire la réservation quand le réseau revient.
4. En dernier recours : la vidéo de démo de secours (2e appareil ou clé USB).

## Pendant l'essai des juges

- **Laisser le juge tenir le téléphone.** On guide à voix haute, on ne touche pas.
- Proposer le parcours d'Amina : rejoindre le groupe, réserver une part, faire tomber un palier.
- Si le juge sort du chemin : le suivre, c'est un test de robustesse, puis ramener vers l'étape suivante.
- Accessibilité si le temps le permet : mode sombre et grande taille de texte depuis le Centre de contrôle, puis VoiceOver.
- Bug inattendu : « Bonne prise, voilà comment on le gère… » puis on enchaîne. Ne jamais s'excuser longuement.

## Questions probables des juges

Format : **réponse directe (1 phrase) → preuve (chiffre, démo, choix technique) → ouverture.** 20 s max.

| Question | Cadre de réponse |
|---|---|
| Pourquoi Montréal ? | 1,25 M de demandes d'aide alimentaire par mois (Moisson Montréal) ; on part d'un quartier, Parc-Extension ou Saint-Michel, puis quartier par quartier. |
| Qui l'utiliserait vraiment ? | Les familles d'un quartier, les producteurs du Québec qui veulent vendre en gros, et les organismes qui financent le fonds solidaire. Les trois y gagnent. |
| Qu'est-ce qui existe déjà ? | Les achats collectifs existent, mais à la main (WhatsApp, Excel, argent comptant). LeGrenier automatise paliers, paiements, cueillette et subventions. |
| Comment ça se finance ? | Une commission de 1 % sur les commandes fermées, Firebase sans serveur à maintenir, partenariats avec les organismes. |
| Qu'avez-vous codé en 24 h ? | La liste des fonctionnalités : trois portails sur le vrai Firebase, environ 1 600 tests unitaires, règles de sécurité testées en CI. Rien de ce qui est listé n'est une maquette. |
| L'argent est réel ? | Non : tout est enregistré et calculé, mais aucun processeur de paiement n'est branché. C'est la prochaine étape. |
| Hors ligne ou en cas d'erreur ? | Cache Firestore, indicateur « hors ligne », messages d'erreur et états vides sur chaque écran. |
| Accessibilité ? | VoiceOver, Dynamic Type jusqu'aux plus grandes tailles, contraste AA, mode sombre, Réduire les animations. |
| Données personnelles ? | Règles Firestore par utilisateur, testées en CI avec des tests d'attaque ; adresse de livraison visible seulement par le demandeur et son bénévole ; statut subventionné privé. |
| Comment mesurer l'impact ? | Économies par famille et par quartier, familles aidées par le fonds, classement solidaire des arrondissements : tout est dans l'onglet Impact. |
| Prochaine étape ? | Pilote dans un arrondissement avec un organisme partenaire et deux ou trois producteurs ; paiements réels, notifications serveur, autres langues. |

## Répétitions

- Chronométrer le pitch et la démo **2 fois minimum** ; viser 4:45.
- Rôles fixes : un présentateur, une personne au téléphone, tout le monde répond aux questions dans son domaine.
