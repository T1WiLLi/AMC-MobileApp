# Plan de présentation — AMC 2026 (B-007)

> Format kiosque : **5 min pitch → 5 min essai par les juges → 2 min questions.**
> Le deck PowerPoint est **obligatoire** (téléversé sur le SharePoint avant dimanche 11:00).
> Règle d'or : **vendre le produit.** Thème et mission doivent être clairs avant la fin de la 1re minute.

Placeholders à remplacer une fois l'idée choisie (candidat actuel : **I-011 Surplus**, problème P-01 aide alimentaire) :

| Placeholder | Signification | Exemple (Surplus) |
|---|---|---|
| `[NOM_APP]` | Nom du produit | Surplus |
| `[SPHÈRE]` | Sphère de Montréal bonifiée | Aide alimentaire / anti-gaspillage |
| `[PROBLÈME]` | Le problème en une phrase | Des surplus jetés pendant que des Montréalais ont faim |
| `[CHIFFRE_CHOC]` | Statistique sourcée sur Montréal | à sourcer (ex. Moisson Montréal, Ville de Montréal) |
| `[PERSONA]` | Utilisateur principal, prénom + quartier | « Amina, Hochelaga » |
| `[ACTION_CLÉ]` | Le geste central dans l'app | Réserver un panier de surplus |
| `[FEATURE_1..3]` | Les 3 fonctionnalités phares | à définir |
| `[INTACT]` | Intégration du défi Intact | défi annoncé sur place |

## Slides (9 slides, 5:00)

| # | Slide | Temps | Cumul | Ce qu'on dit | Critère(s) visé(s) |
|---|---|---|---|---|---|
| 1 | **Accroche** : titre `[NOM_APP]` + une phrase-mission | 0:20 | 0:20 | « Marquize à Montréal, Mamdani à New York : n'importe qui peut agir pour sa ville. Nous, on a choisi `[SPHÈRE]`. » | Présentation & mission (10), Adéquation au thème (15) |
| 2 | **Le problème à Montréal** : `[CHIFFRE_CHOC]` + photo/carte de Montréal | 0:30 | 0:50 | `[PROBLÈME]`, chiffre sourcé, un quartier précis. Ancrer **local**, pas générique. | Adéquation au thème (15) |
| 3 | **Persona** : `[PERSONA]` et sa journée | 0:20 | 1:10 | Une personne réelle, un irritant concret. « Aujourd'hui, Amina doit… » | Présentation & mission (10) |
| 4 | **La solution** : `[NOM_APP]` en une phrase + capture héro | 0:30 | 1:40 | Ce que fait l'app, pour qui, pourquoi maintenant. Pas encore de détails techniques. | Originalité (10), Mission (10) |
| 5 | **Comment ça marche** : 3 captures, `[FEATURE_1..3]` | 0:45 | 2:25 | Le parcours en 3 étapes jusqu'à `[ACTION_CLÉ]`. Montrer le Liquid Glass. | Esthétique (10), Cohérence du design (10) |
| 6 | **Impact sur Montréal** : avant / après | 0:30 | 2:55 | Ce qui change pour le quartier, la ville, les organismes. Un chiffre projeté réaliste. | Adéquation au thème (15), Mission (10) |
| 7 | **Ce qui nous distingue** : vs alternatives existantes | 0:25 | 3:20 | Pourquoi pas une app existante ? Notre angle unique. | Originalité (10) |
| 8 | **Sous le capot** : iOS 26 SwiftUI, Liquid Glass, Firebase (Auth Google, Firestore temps réel), MVVM, accessibilité | 0:30 | 3:50 | Natif, synchro en temps réel, VoiceOver + Dynamic Type, gestion d'erreurs. Mentionner `[INTACT]` si applicable. | Fluidité/Réactivité (20), Accessibilité (5), Bonus Intact (10) |
| 9 | **Démo en direct → passage aux juges** | 1:10 | 5:00 | Démo live du parcours (voir script ci-dessous, étapes 1–3), puis on tend le téléphone : « À vous ! » | Facilité d'utilisation (5), Exactitude (10) |

Règles du deck :
- Une idée par slide, ≤ 15 mots de texte. Captures réelles de l'app (pas de maquettes).
- Charte visuelle identique à l'app (couleurs, typo SF) → renforce la cohérence du design.
- Slide 2 et 6 : citer la source du chiffre en petit.
- Une slide de secours cachée : vidéo de démo enregistrée (au cas où le réseau ou l'app lâche).

## Script d'essai jury (5 min)

Préparation : iPhone chargé, IPA installée, compte Google de démo **déjà connecté** (ou prêt), données de démo réalistes chargées, mode Ne pas déranger, luminosité max.

| Temps | Étape | Ce que le juge fait | Ce qu'on fait remarquer | Critère |
|---|---|---|---|---|
| 0:00–0:30 | 1. Connexion | « Continuer avec Google » (ou session déjà ouverte) | Connexion en un tap, Firebase Auth | Facilité d'utilisation |
| 0:30–1:30 | 2. Écran principal | Parcourt `[ÉCRAN_PRINCIPAL]`, scrolle, ouvre un élément | Liquid Glass, animations, données de Montréal (quartiers réels) | Esthétique, Fluidité |
| 1:30–2:45 | 3. Action clé | Réalise `[ACTION_CLÉ]` de bout en bout | Confirmation claire, résultat exact | Exactitude, Réactivité |
| 2:45–3:30 | 4. Synchro temps réel | On montre la mise à jour sur un 2e appareil / la console | Firestore synchronisé instantanément | Réactivité |
| 3:30–4:15 | 5. Gestion d'erreurs | Mode avion → action ; ou formulaire vide | Message d'erreur clair, état vide soigné, pas de crash | Gestion des erreurs |
| 4:15–5:00 | 6. Accessibilité | Mode sombre + grande taille de texte (réglages rapides) ; VoiceOver si le temps | Dynamic Type, contraste, libellés VoiceOver | Accessibilité, Cohérence |

Règles pendant l'essai :
- **Laisser le juge tenir le téléphone.** On guide à voix haute, on ne touche pas.
- Si le juge sort du chemin : le suivre, c'est un test de robustesse. Ramener vers l'étape suivante.
- Bug inattendu : « Bonne prise — c'est un état qu'on gère comme ça… » puis on enchaîne. Ne jamais s'excuser longuement.

## Questions probables des juges

Format de réponse : **réponse directe (1 phrase) → preuve (chiffre, démo, choix technique) → ouverture (prochaine étape).** 20 s max.

| Question | Cadre de réponse |
|---|---|
| Pourquoi Montréal spécifiquement ? | Problème local chiffré (`[CHIFFRE_CHOC]`) → acteurs montréalais visés (organismes, arrondissements) → déploiement par quartier. |
| Qui l'utiliserait vraiment ? | `[PERSONA]` + 2e type d'utilisateur (ex. organisme/commerçant) → pourquoi ils y gagnent tous les deux. |
| Qu'est-ce qui existe déjà ? Pourquoi vous ? | Nommer 1–2 alternatives honnêtement → notre différence en une phrase → preuve dans l'app. |
| Comment ça se finance / se maintient ? | Modèle simple (partenariat Ville/organismes, gratuit pour citoyens) → coûts Firebase faibles au départ. |
| Qu'avez-vous réellement codé en 24 h ? | Renvoyer à la liste de fonctionnalités : implémenté vs partiel, honnêtement. |
| Que se passe-t-il hors ligne / en cas d'erreur ? | Cache Firestore hors ligne, messages d'erreur, états vides → l'avoir montré à l'étape 5. |
| Accessibilité ? | VoiceOver, Dynamic Type, contraste, mode sombre → testé sur l'app. |
| Données personnelles / sécurité ? | Auth Google via Firebase, règles Firestore par utilisateur, minimum de données collectées. |
| Comment mesurer l'impact ? | 1–2 indicateurs concrets (`[KPI]` : ex. repas sauvés, utilisateurs actifs par quartier). |
| Et le défi Intact ? | `[INTACT]` : où il est dans l'app, pourquoi c'est pertinent → le montrer. |
| Prochaine étape après le hackathon ? | Pilote dans un arrondissement / avec un organisme partenaire → Android / web ensuite. |

## Répétitions

- Chronométrer le pitch **2 fois minimum** ; viser 4:45 (marge de 15 s).
- Rôles fixes : 1 présentateur principal, 1 personne au téléphone pour la démo, tous répondent aux questions dans leur domaine.
